#!/usr/bin/env node
/**
 * eLogix ERP - metadata scaffolder.
 *
 * Renders the model files in scripts/node/model/ into Metadata API source under
 * force-app/main/default/. Dev-time tool only; the emitted XML is committed and is the source of
 * truth for deployment.
 *
 *   node scripts/node/scaffold-metadata.mjs            # validate the model, then write files
 *   node scripts/node/scaffold-metadata.mjs --dry-run  # validate only and print counts
 *
 * The validation pass exists to catch, before a deploy round trip, the mistakes the Metadata API
 * would otherwise reject one at a time: dangling field references in formulas and validation
 * rules, unknown picklist values, broken master-detail permission dependencies, and so on.
 */

import { fileURLToPath } from 'node:url';
import { mkdirSync, writeFileSync } from 'node:fs';
import { dirname, join, relative } from 'node:path';
import {
    UNIQUE_CAPABLE_KINDS,
    BYPASS_PERMISSION,
    isComputedField,
    isFlsExempt,
    emitApplication,
    emitPages,
    emitCustomPermissions,
    emitGlobalValueSets,
    emitMetadataTypes,
    emitObjects,
    emitPermissionSets
} from './lib/metadata-writer.mjs';
import { GLOBAL_VALUE_SETS, OBJECTS, OBJECTS_BY_API } from './model/elogix-datamodel.mjs';
import { VALIDATION_RULES } from './model/elogix-validation.mjs';
import { EXPERIENCE, APPLICATION, APP_PAGES, RECORD_PAGES } from './model/elogix-experience.mjs';
import { CUSTOM_PERMISSIONS, METADATA_TYPES } from './model/elogix-config.mjs';
import { ADMIN, CONTROLLER_ACCESS, PERMISSION_SETS, PROTECTED_FIELDS } from './model/elogix-security.mjs';
import { existsSync } from 'node:fs';

const here = dirname(fileURLToPath(import.meta.url));
const projectRoot = join(here, '..', '..');
const sourceRoot = join(projectRoot, 'force-app', 'main', 'default');
const dryRun = process.argv.includes('--dry-run');

const errors = [];
const fail = (message) => errors.push(message);

/* ---- merge companion models into the object definitions ---- */

for (const [objectApi, rules] of Object.entries(VALIDATION_RULES)) {
    const object = OBJECTS_BY_API.get(objectApi);
    if (!object) fail(`validation rules defined for unknown object ${objectApi}`);
    else object.rules = rules;
}
for (const [objectApi, experience] of Object.entries(EXPERIENCE)) {
    const object = OBJECTS_BY_API.get(objectApi);
    if (!object) fail(`experience defined for unknown object ${objectApi}`);
    else Object.assign(object, experience);
}

/* ---- derive page layout related lists from the relationships in the model ---- */

for (const parent of OBJECTS.filter((o) => !o.standard)) {
    const lists = [];
    for (const child of OBJECTS.filter((o) => !o.standard)) {
        for (const field of child.fields) {
            if ((field.kind === 'lookup' || field.kind === 'masterdetail') && field.referenceTo === parent.api) {
                const columns = (child.listColumns ?? []).filter((column) => column !== field.api).slice(0, 4);
                lists.push({ relatedList: `${child.api}.${field.api}`, fields: ['NAME', ...columns] });
            }
        }
    }
    if (parent.enableActivities) lists.push({ relatedList: 'RelatedActivityList' }, { relatedList: 'RelatedHistoryList' });
    if (parent.enableHistory) lists.push({ relatedList: 'RelatedEntityHistoryList' });
    if (parent.files) lists.push({ relatedList: 'RelatedFileList' });
    parent.relatedLists = lists;
}

/* ---- helpers ---- */

const gvsByApi = new Map(GLOBAL_VALUE_SETS.map((vs) => [vs.api, vs]));
const permissionNames = new Set(CUSTOM_PERMISSIONS.map((p) => p.api));
const valueName = (v) => (typeof v === 'string' ? v : v.name);
const fieldOf = (objectApi, fieldApi) => OBJECTS_BY_API.get(objectApi)?.fields.find((f) => f.api === fieldApi);

function picklistValues(field) {
    if (field.globalValueSet) return gvsByApi.get(field.globalValueSet)?.values.map(valueName) ?? [];
    return (field.values ?? []).map(valueName);
}

/** Resolves `A__r.B__r.Field__c` from `objectApi`; returns an error string or null. */
function resolveReference(objectApi, path) {
    const segments = path.split('.');
    let current = objectApi;
    for (const segment of segments.slice(0, -1)) {
        const relationshipField = fieldOf(current, segment.replace(/__r$/, '__c'));
        if (!relationshipField || !['lookup', 'masterdetail'].includes(relationshipField.kind)) {
            return `${segment} is not a relationship on ${current}`;
        }
        current = relationshipField.referenceTo;
    }
    const last = segments[segments.length - 1];
    if (!OBJECTS_BY_API.has(current)) return null; // standard object outside the model - cannot verify
    return fieldOf(current, last) ? null : `${current}.${last} does not exist`;
}

/** $CustomMetadata.Type__mdt.Record.Field__c - a configuration value read inside a formula (Phase 4). */
const CMDT_REFERENCE = /\$CustomMetadata\.([A-Za-z0-9_]+__mdt)\.([A-Za-z0-9_]+)\.([A-Za-z0-9_]+__c)/g;

/** Checks field references, ISPICKVAL values, $Permission names and $CustomMetadata references inside a formula. */
function checkFormula(context, objectApi, rawFormula) {
    for (const match of rawFormula.matchAll(CMDT_REFERENCE)) {
        const type = METADATA_TYPES.find((t) => t.api === match[1]);
        if (!type) fail(`${context}: unknown custom metadata type ${match[1]}`);
        else {
            if (!type.records.some((r) => r.name === match[2])) fail(`${context}: ${match[1]} has no record ${match[2]}`);
            if (!type.fields.some((f) => f.api === match[3])) fail(`${context}: ${match[1]} has no field ${match[3]}`);
        }
    }
    // Custom metadata references are checked above; field references below are local to objectApi.
    const formula = rawFormula.replace(CMDT_REFERENCE, '0');
    for (const match of formula.matchAll(/\b((?:[A-Za-z][A-Za-z0-9_]*__r\.)*[A-Za-z][A-Za-z0-9_]*__c)\b/g)) {
        const problem = resolveReference(objectApi, match[1]);
        if (problem) fail(`${context}: ${problem}`);
    }
    for (const match of formula.matchAll(/ISPICKVAL\(\s*([A-Za-z0-9_]+__c)\s*,\s*"([^"]*)"\s*\)/g)) {
        const field = fieldOf(objectApi, match[1]);
        if (field && match[2] !== '' && !picklistValues(field).includes(match[2])) {
            fail(`${context}: "${match[2]}" is not a value of ${objectApi}.${match[1]}`);
        }
    }
    for (const match of formula.matchAll(/\$Permission\.([A-Za-z0-9_]+)/g)) {
        if (!permissionNames.has(match[1])) fail(`${context}: unknown custom permission ${match[1]}`);
    }
    // Percent fields are fractions inside formulas (12% -> 0.12); "/ 100" or "> 100" is always a bug.
    for (const field of OBJECTS_BY_API.get(objectApi)?.fields ?? []) {
        if (field.kind !== 'percent') continue;
        const misuse = new RegExp(`${field.api}\\s*(/|>=?|<=?)\\s*100\\b`);
        if (misuse.test(formula)) fail(`${context}: ${field.api} is a fraction in formulas - compare with 1, not 100`);
    }
}

const API_NAME = /^[A-Za-z][A-Za-z0-9]*(_[A-Za-z0-9]+)*$/;

/* ---- objects and fields ---- */

const relationshipsByParent = new Map();

for (const object of OBJECTS) {
    if (!object.standard && (!object.label || !object.nameField || !object.sharingModel)) {
        fail(`${object.api}: missing label, nameField or sharingModel`);
    }
    const hasMasterDetail = object.fields.some((f) => f.kind === 'masterdetail');
    if (hasMasterDetail !== (object.sharingModel === 'ControlledByParent') && !object.standard) {
        fail(`${object.api}: ControlledByParent sharing must be used exactly when the object has a master-detail field`);
    }
    if (object.fields.filter((f) => f.kind === 'masterdetail').length > 2) {
        fail(`${object.api}: more than two master-detail relationships`);
    }

    const seen = new Set();
    for (const field of object.fields) {
        const where = `${object.api}.${field.api}`;
        if (seen.has(field.api)) fail(`${where}: duplicate field`);
        seen.add(field.api);
        if (!field.api.endsWith('__c')) fail(`${where}: must end with __c`);
        if (field.api.length > 43) fail(`${where}: API name longer than 40 characters before __c`);
        if (field.unique && !UNIQUE_CAPABLE_KINDS.has(field.kind)) fail(`${where}: ${field.kind} fields cannot be unique`);

        if (field.kind === 'lookup' || field.kind === 'masterdetail') {
            const target = field.referenceTo;
            if (target.endsWith('__c') && !OBJECTS_BY_API.has(target)) fail(`${where}: references unknown object ${target}`);
            if (field.relationshipName.length > 40) fail(`${where}: relationshipName exceeds 40 characters`);
            const key = `${target}::${field.relationshipName}`;
            if (relationshipsByParent.has(key)) {
                fail(`${where}: relationshipName "${field.relationshipName}" already used on ${target} by ${relationshipsByParent.get(key)}`);
            }
            relationshipsByParent.set(key, where);
        }

        if (field.kind === 'formula') checkFormula(where, object.api, field.formula);

        if (field.kind === 'summary') {
            const [childObject, childField] = field.foreignKey.split('.');
            const md = fieldOf(childObject, childField);
            if (!md || md.kind !== 'masterdetail' || md.referenceTo !== object.api) {
                fail(`${where}: ${field.foreignKey} is not a master-detail to ${object.api}`);
            }
            if (field.operation !== 'count') {
                const summarized = field.summarizedField?.split('.')[1];
                if (!summarized || !fieldOf(childObject, summarized)) fail(`${where}: summarizedField missing or unknown`);
            }
            for (const filter of field.filters ?? []) {
                const filterField = fieldOf(childObject, filter.field.split('.')[1]);
                if (!filterField) fail(`${where}: filter field ${filter.field} unknown`);
            }
        }

        if (field.kind === 'picklist' && field.globalValueSet && !gvsByApi.has(field.globalValueSet)) {
            fail(`${where}: unknown global value set ${field.globalValueSet}`);
        }
    }

    const ruleNames = new Set();
    for (const rule of object.rules ?? []) {
        const where = `${object.api} rule ${rule.name}`;
        if (ruleNames.has(rule.name)) fail(`${where}: duplicate rule name`);
        ruleNames.add(rule.name);
        if (rule.name.length > 40 || !API_NAME.test(rule.name)) fail(`${where}: invalid name`);
        if (rule.field?.endsWith('__c') && !fieldOf(object.api, rule.field)) fail(`${where}: display field ${rule.field} unknown`);
        if (rule.message.length > 255) fail(`${where}: message longer than 255 characters`);
        checkFormula(where, object.api, rule.formula);
    }

    for (const column of object.listColumns ?? []) {
        if (!fieldOf(object.api, column)) fail(`${object.api} list view: unknown column ${column}`);
    }
    for (const view of object.listViews ?? []) {
        if (!API_NAME.test(view.name) || view.name === 'All') fail(`${object.api} list view ${view.name}: invalid name`);
        if (!object.listColumns) fail(`${object.api} list view ${view.name}: the object needs listColumns`);
        for (const column of view.columns ?? []) {
            if (!fieldOf(object.api, column)) fail(`${object.api} list view ${view.name}: unknown column ${column}`);
        }
        for (const filter of view.filters ?? []) {
            if (!fieldOf(object.api, filter.field)) fail(`${object.api} list view ${view.name}: unknown filter field ${filter.field}`);
        }
    }
    if (object.tab && object.standard) fail(`${object.api}: tabs are only generated for custom objects`);
}

if (!permissionNames.has(BYPASS_PERMISSION)) fail(`bypass permission ${BYPASS_PERMISSION} is not defined`);

/* ---- application ---- */

const appPagesByApi = new Map(APP_PAGES.map((page) => [page.api, page]));
for (const tab of APPLICATION.tabs) {
    if (!tab.startsWith('standard-') && !OBJECTS_BY_API.get(tab)?.tab && !appPagesByApi.has(tab)) {
        fail(`app ${APPLICATION.api}: no tab generated for ${tab}`);
    }
}

/* ---- Phase 7: Lightning pages and controllers ---- */

const lwcRoot = join(dirname(fileURLToPath(import.meta.url)), '..', '..', 'force-app', 'main', 'default', 'lwc');
const pageComponents = (page) => (page.components ?? Object.values(page.regions).flat()).map((c) => (typeof c === 'string' ? c : c.name));
for (const page of [...APP_PAGES, ...RECORD_PAGES]) {
    for (const name of pageComponents(page)) {
        if (!name.includes(':') && !existsSync(join(lwcRoot, name, `${name}.js-meta.xml`))) fail(`page ${page.api}: no LWC bundle ${name}`);
    }
}
for (const page of APP_PAGES) {
    if (!OBJECTS_BY_API.has(page.requires)) fail(`page ${page.api}: unknown object ${page.requires}`);
    if (!APPLICATION.tabs.includes(page.api)) fail(`page ${page.api}: tab not in app ${APPLICATION.api}`);
}
for (const page of RECORD_PAGES) {
    if (!OBJECTS_BY_API.has(page.object)) fail(`page ${page.api}: unknown object ${page.object}`);
}
APPLICATION.recordPages = RECORD_PAGES;
for (const [controller, objectApi] of Object.entries(CONTROLLER_ACCESS)) {
    if (!OBJECTS_BY_API.has(objectApi)) fail(`controller ${controller}: unknown object ${objectApi}`);
}

/* ---- custom metadata ---- */

const shipmentStatuses = gvsByApi.get('eLogix_Shipment_Status').values.map(valueName);
const trackingEventTypes = gvsByApi.get('eLogix_Tracking_Event_Type').values.map(valueName);

for (const type of METADATA_TYPES) {
    const fieldNames = new Set(type.fields.map((f) => f.api));
    const recordNames = new Set();
    for (const record of type.records) {
        const where = `${type.api} record ${record.name}`;
        if (recordNames.has(record.name)) fail(`${where}: duplicate record`);
        recordNames.add(record.name);
        if (record.name.length > 40 || !API_NAME.test(record.name)) fail(`${where}: invalid developer name`);
        if (record.label.length > 40) fail(`${where}: label longer than 40 characters`);
        for (const key of Object.keys(record.values)) if (!fieldNames.has(key)) fail(`${where}: unknown field ${key}`);
        for (const field of type.fields) {
            const value = record.values[field.api];
            if (field.required && (value === null || value === undefined)) fail(`${where}: ${field.api} is required`);
        }
    }
}

const transitionType = METADATA_TYPES.find((t) => t.api === 'Shipment_Status_Transition__mdt');
const transitionKeys = new Set();
for (const { name, values } of transitionType.records) {
    const where = `transition ${name}`;
    if (values.From_Status__c && !shipmentStatuses.includes(values.From_Status__c)) fail(`${where}: unknown from status`);
    if (!shipmentStatuses.includes(values.To_Status__c)) fail(`${where}: unknown to status`);
    if (!trackingEventTypes.includes(values.Tracking_Event_Type__c)) fail(`${where}: unknown tracking event type`);
    if (values.Required_Permission__c && !permissionNames.has(values.Required_Permission__c)) fail(`${where}: unknown permission`);
    const key = `${values.From_Status__c}->${values.To_Status__c}`;
    if (transitionKeys.has(key)) fail(`${where}: duplicate transition`);
    transitionKeys.add(key);
}
for (const terminal of ['Closed', 'Cancelled']) {
    if (transitionType.records.some((r) => r.values.From_Status__c === terminal)) fail(`terminal status ${terminal} has outgoing transitions`);
}
if (transitionType.records.some((r) => r.values.From_Status__c === 'Delivered' && r.values.To_Status__c === 'Dispatched')) {
    fail('Delivered shipments must not be dispatchable again');
}

/* ---- permission sets ---- */

const permissionSetNames = new Set(PERMISSION_SETS.map((p) => p.api));
for (const [fieldPath, roles] of Object.entries(PROTECTED_FIELDS)) {
    const [objectApi, fieldApi] = fieldPath.split('.');
    const field = fieldOf(objectApi, fieldApi);
    if (!field) fail(`protected field ${fieldPath} does not exist`);
    else if (isFlsExempt(field) || isComputedField(field)) fail(`protected field ${fieldPath} is required/computed and cannot be protected by FLS`);
    for (const role of roles) if (!permissionSetNames.has(role)) fail(`protected field ${fieldPath}: unknown role ${role}`);
}

const masterOf = (objectApi) => OBJECTS_BY_API.get(objectApi)?.fields.find((f) => f.kind === 'masterdetail')?.referenceTo;

function resolvePermissionSet(def) {
    const objects = new Map();
    for (const object of OBJECTS) {
        if (def.objects[object.api]) objects.set(object.api, def.objects[object.api]);
    }
    for (const objectApi of Object.keys(def.objects)) {
        if (!OBJECTS_BY_API.has(objectApi)) fail(`${def.api}: unknown object ${objectApi}`);
    }

    for (const [objectApi, access] of objects) {
        const where = `${def.api} ${objectApi} "${access}"`;
        if (!/^[CREDVM]+$/.test(access)) fail(`${where}: invalid access letters`);
        const has = (letter) => access.includes(letter);
        if (!has('R')) fail(`${where}: every grant needs Read`);
        if (has('D') && !has('E')) fail(`${where}: Delete requires Edit`);
        if (has('M') && !(has('E') && has('D') && has('V'))) fail(`${where}: Modify All requires Edit, Delete and View All`);

        const parents = [masterOf(objectApi), objectApi === 'Contact' ? 'Account' : null].filter(Boolean);
        for (const parent of parents) {
            const parentAccess = objects.get(parent) ?? '';
            if (!parentAccess.includes('R')) fail(`${where}: requires Read on master ${parent}`);
            if (has('V') && !parentAccess.includes('V')) fail(`${where}: View All requires View All on master ${parent}`);
            if (has('M') && !parentAccess.includes('M')) fail(`${where}: Modify All requires Modify All on master ${parent}`);
        }
    }

    const fields = [];
    for (const [objectApi, access] of objects) {
        const canWrite = access.includes('C') || access.includes('E');
        for (const field of OBJECTS_BY_API.get(objectApi).fields) {
            if (isFlsExempt(field)) continue;
            const fieldPath = `${objectApi}.${field.api}`;
            const protectedFor = PROTECTED_FIELDS[fieldPath];
            const entitled = !protectedFor || def.api === ADMIN || protectedFor.includes(def.api);
            fields.push({ field: fieldPath, editable: canWrite && !isComputedField(field) && entitled });
        }
    }

    for (const permission of def.customPermissions) {
        if (!permissionNames.has(permission)) fail(`${def.api}: unknown custom permission ${permission}`);
    }
    for (const apexClass of def.apexClasses ?? []) {
        if (!/^[A-Za-z][A-Za-z0-9_]*$/.test(apexClass)) fail(`${def.api}: invalid Apex class name ${apexClass}`);
    }

    // Phase 7: UI controllers and page tabs follow read access to the screen's object.
    const canRead = (objectApi) => !def.noApp && (objects.get(objectApi) ?? '').includes('R');
    const controllers = Object.entries(CONTROLLER_ACCESS).filter(([, objectApi]) => canRead(objectApi)).map(([name]) => name);
    const pageTabs = APP_PAGES.filter((page) => canRead(page.requires)).map((page) => page.api);

    return {
        applications: def.noApp ? [] : [APPLICATION.api],
        metadataTypes: def.noApp ? [] : METADATA_TYPES.map((t) => t.api),
        customPermissions: def.customPermissions,
        apexClasses: [...new Set([...(def.apexClasses ?? []), ...controllers])].sort(),
        fields,
        objects,
        tabs: [...[...objects.keys()].filter((api) => OBJECTS_BY_API.get(api).tab), ...pageTabs]
    };
}

const resolvedSets = PERMISSION_SETS.map((def) => ({ def, resolved: resolvePermissionSet(def) }));

/* ---- report ---- */

if (errors.length > 0) {
    console.error(`Model validation failed with ${errors.length} error(s):`);
    for (const error of errors) console.error(`  - ${error}`);
    process.exit(1);
}

const customObjects = OBJECTS.filter((o) => !o.standard);
const counts = {
    'custom objects': customObjects.length,
    'standard object extensions': OBJECTS.length - customObjects.length,
    fields: OBJECTS.reduce((sum, o) => sum + o.fields.length, 0),
    'validation rules': OBJECTS.reduce((sum, o) => sum + (o.rules?.length ?? 0), 0),
    'list views': OBJECTS.filter((o) => o.listColumns).length + OBJECTS.reduce((n, o) => n + (o.listViews?.length ?? 0), 0),
    'compact layouts': OBJECTS.filter((o) => o.listColumns).length,
    'page layouts': customObjects.length + METADATA_TYPES.length,
    tabs: OBJECTS.filter((o) => o.tab).length + APP_PAGES.length,
    'lightning pages': APP_PAGES.length + RECORD_PAGES.length,
    'global value sets': GLOBAL_VALUE_SETS.length,
    'custom metadata types': METADATA_TYPES.length,
    'custom metadata records': METADATA_TYPES.reduce((sum, t) => sum + t.records.length, 0),
    'custom permissions': CUSTOM_PERMISSIONS.length,
    'permission sets': PERMISSION_SETS.length,
    applications: 1
};

/* ---- generated documentation: field-level catalogue that can never drift from the metadata ---- */

const cell = (value) => String(value).replace(/\|/g, '\\|').replace(/\n\s*/g, ' ');

function describeType(field) {
    switch (field.kind) {
        case 'text': return `Text(${field.length})`;
        case 'textarea': return 'Text Area(255)';
        case 'longtextarea': return `Long Text(${field.length})`;
        case 'number': return `Number(${field.precision},${field.scale})`;
        case 'currency': return `Currency(${field.precision},${field.scale})`;
        case 'percent': return 'Percent';
        case 'picklist': return field.globalValueSet ? `Picklist (GVS ${field.globalValueSet})` : `Picklist: ${field.values.map(valueName).join(', ')}`;
        case 'lookup': return `Lookup → ${field.referenceTo}`;
        case 'masterdetail': return `Master-Detail → ${field.referenceTo}`;
        case 'formula': return `Formula(${field.type}): \`${field.formula}\``;
        case 'summary': return `Roll-up ${field.operation.toUpperCase()}${field.summarizedField ? ` of ${field.summarizedField}` : ''} (${field.foreignKey})${(field.filters ?? []).map((f) => ` where ${f.field} ${f.operation} "${f.value}"`).join('')}`;
        default: return field.kind.charAt(0).toUpperCase() + field.kind.slice(1);
    }
}

function buildCatalogue() {
    const out = [
        '# eLogix ERP - Data Model Catalogue (generated)',
        '',
        '> Generated by `npm run metadata:generate` from `scripts/node/model/`. Do not edit by hand -',
        '> change the model and regenerate. Design rationale lives in [../DATA_MODEL.md](../DATA_MODEL.md).',
        ''
    ];
    for (const object of OBJECTS) {
        const protectedHere = Object.keys(PROTECTED_FIELDS).filter((k) => k.startsWith(`${object.api}.`)).map((k) => k.split('.')[1]);
        out.push(`## ${object.standard ? object.api : `${object.label} (\`${object.api}\`)`}`, '');
        if (object.standard) out.push('Standard object - eLogix custom fields only.', '');
        else {
            out.push(`- Sharing: **${object.sharingModel}** · Name: ${object.nameField.displayFormat ? `Auto Number \`${object.nameField.displayFormat}\`` : 'Text'}${object.enableHistory ? ' · Field history on' : ''}`);
            if (object.description) out.push(`- ${object.description}`);
            out.push('');
        }
        out.push('| Field | Type | Req | Notes |', '|---|---|---|---|');
        for (const field of object.fields) {
            const notes = [
                field.unique && 'Unique',
                field.externalId && 'External ID',
                field.trackHistory && 'History',
                protectedHere.includes(field.api) && 'Protected (service-written)',
                field.helpText
            ].filter(Boolean);
            const required = field.kind === 'masterdetail' || (field.required && !isComputedField(field)) ? '✓' : '';
            out.push(`| \`${field.api}\` | ${cell(describeType(field))} | ${required} | ${cell(notes.join('. '))} |`);
        }
        if (object.rules?.length) {
            out.push('', '**Validation rules**', '', '| Rule | Bypassable | Message |', '|---|---|---|');
            for (const rule of object.rules) out.push(`| \`${rule.name}\` | ${rule.noBypass ? 'No' : 'Yes'} | ${cell(rule.message)} |`);
        }
        out.push('');
    }
    out.push('## Global value sets', '', '| Value set | Values |', '|---|---|');
    for (const vs of GLOBAL_VALUE_SETS) out.push(`| \`${vs.api}\` | ${vs.values.map(valueName).join(', ')} |`);
    out.push('', '## Custom metadata types', '');
    for (const type of METADATA_TYPES) {
        out.push(`### ${type.label} (\`${type.api}\`)`, '', type.description, '', '| Record | ' + type.fields.map((f) => f.api).join(' | ') + ' |', '|---|' + type.fields.map(() => '---').join('|') + '|');
        for (const record of type.records) {
            out.push(`| \`${record.name}\` | ` + type.fields.map((f) => cell(record.values[f.api] ?? '')).join(' | ') + ' |');
        }
        out.push('');
    }
    return out.join('\n');
}

if (dryRun) {
    console.log('Model validation passed. Would write:');
} else {
    const written = [
        ...emitGlobalValueSets(GLOBAL_VALUE_SETS, sourceRoot),
        ...emitObjects(OBJECTS, sourceRoot),
        ...emitMetadataTypes(METADATA_TYPES, sourceRoot),
        ...emitCustomPermissions(CUSTOM_PERMISSIONS, sourceRoot),
        ...emitApplication(APPLICATION, sourceRoot),
        ...emitPages(APP_PAGES, RECORD_PAGES, sourceRoot),
        ...emitPermissionSets(resolvedSets, sourceRoot)
    ];
    const cataloguePath = join(projectRoot, 'docs', 'generated', 'DATA_MODEL_CATALOGUE.md');
    mkdirSync(dirname(cataloguePath), { recursive: true });
    writeFileSync(cataloguePath, `${buildCatalogue()}\n`, 'utf8');
    console.log(`Model validation passed. Wrote ${written.length} files to ${relative(projectRoot, sourceRoot)} and ${relative(projectRoot, cataloguePath)}:`);
}
for (const [label, count] of Object.entries(counts)) console.log(`  ${label.padEnd(28)} ${count}`);
