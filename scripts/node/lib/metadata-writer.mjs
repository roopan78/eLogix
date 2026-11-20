/**
 * eLogix ERP - Metadata XML writer.
 *
 * Dev-time scaffolding utility. Translates the compact definitions in `scripts/node/model/`
 * into Salesforce Metadata API source files under `force-app/main/default/`.
 *
 * The emitted XML is the source of truth for the project and is committed to git. This writer
 * exists so that several hundred field, permission and rule definitions stay internally
 * consistent (naming, picklist reuse, FLS coverage) and can be regenerated deterministically
 * when the model changes.
 *
 * Element ordering follows the Metadata API XSD sequence (alphabetical for every type emitted
 * here). No third-party dependencies (CLAUDE.md section 2, rule 3).
 */

import { mkdirSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';

const XML_HEADER = '<?xml version="1.0" encoding="UTF-8"?>';
const NS = 'http://soap.sforce.com/2006/04/metadata';
const I = '    ';

/** Escapes the five XML entities. Formulas routinely contain < and >. */
function esc(value) {
    return String(value)
        .replace(/&/g, '&amp;')
        .replace(/</g, '&lt;')
        .replace(/>/g, '&gt;')
        .replace(/"/g, '&quot;')
        .replace(/'/g, '&apos;');
}

function tag(name, value, indent) {
    return `${indent}<${name}>${esc(value)}</${name}>`;
}

function writeFile(path, lines) {
    mkdirSync(dirname(path), { recursive: true });
    writeFileSync(path, `${lines.join('\n')}\n`, 'utf8');
    return path;
}

/** Humanises an API name: Expected_Delivery_Date__c -> Expected Delivery Date */
export function labelFor(apiName) {
    return apiName.replace(/__(c|mdt)$/, '').replace(/_/g, ' ');
}

/** Field kinds that the platform allows to be marked unique. */
export const UNIQUE_CAPABLE_KINDS = new Set(['text', 'number', 'email']);

/** True when a field can never be written by a user (and so is read-only in every permission set). */
export function isComputedField(field) {
    return field.kind === 'formula' || field.kind === 'summary';
}

/**
 * True when a permission set must not carry a fieldPermissions entry for the field.
 * The platform rejects FLS on required fields and master-detail fields (always visible/editable).
 */
export function isFlsExempt(field) {
    return field.kind === 'masterdetail' || (field.required === true && !isComputedField(field));
}

/* ------------------------------------------------------------------ */
/* Global value sets                                                   */
/* ------------------------------------------------------------------ */

export function buildGlobalValueSet(def) {
    const lines = [XML_HEADER, `<GlobalValueSet xmlns="${NS}">`];
    for (const value of def.values) {
        const name = typeof value === 'string' ? value : value.name;
        const isDefault = typeof value === 'object' && value.default === true;
        lines.push(`${I}<customValue>`);
        lines.push(tag('fullName', name, `${I}${I}`));
        lines.push(tag('default', isDefault, `${I}${I}`));
        lines.push(tag('label', name, `${I}${I}`));
        lines.push(`${I}</customValue>`);
    }
    if (def.description) lines.push(tag('description', def.description, I));
    lines.push(tag('masterLabel', def.masterLabel, I));
    lines.push(tag('sorted', false, I));
    lines.push('</GlobalValueSet>');
    return lines;
}

/* ------------------------------------------------------------------ */
/* Fields                                                              */
/* ------------------------------------------------------------------ */

/** ValueSet XSD sequence: controllingField, restricted, valueSetDefinition, valueSetName. */
function picklistValueSet(field, lines) {
    lines.push(`${I}<valueSet>`);
    lines.push(tag('restricted', true, `${I}${I}`));
    if (field.globalValueSet) {
        lines.push(tag('valueSetName', field.globalValueSet, `${I}${I}`));
    } else {
        lines.push(`${I}${I}<valueSetDefinition>`);
        lines.push(tag('sorted', false, `${I}${I}${I}`));
        for (const value of field.values) {
            const name = typeof value === 'string' ? value : value.name;
            const isDefault = typeof value === 'object' && value.default === true;
            lines.push(`${I}${I}${I}<value>`);
            lines.push(tag('fullName', name, `${I}${I}${I}${I}`));
            lines.push(tag('default', isDefault, `${I}${I}${I}${I}`));
            lines.push(tag('label', name, `${I}${I}${I}${I}`));
            lines.push(`${I}${I}${I}</value>`);
        }
        lines.push(`${I}${I}</valueSetDefinition>`);
    }
    lines.push(`${I}</valueSet>`);
}

const METADATA_TYPE = {
    text: 'Text',
    textarea: 'TextArea',
    longtextarea: 'LongTextArea',
    number: 'Number',
    currency: 'Currency',
    percent: 'Percent',
    date: 'Date',
    datetime: 'DateTime',
    checkbox: 'Checkbox',
    phone: 'Phone',
    email: 'Email',
    url: 'Url',
    picklist: 'Picklist',
    multipicklist: 'MultiselectPicklist',
    lookup: 'Lookup',
    masterdetail: 'MasterDetail'
};

/**
 * Emits a CustomField. `field.kind` selects the shape; everything else is optional metadata.
 * Element order below matches the CustomField XSD sequence.
 */
export function buildField(field) {
    const label = field.label ?? labelFor(field.api);
    const lines = [XML_HEADER, `<CustomField xmlns="${NS}">`];
    lines.push(tag('fullName', field.api, I));

    const isFormula = field.kind === 'formula';
    const isSummary = field.kind === 'summary';
    const isRelationship = field.kind === 'lookup' || field.kind === 'masterdetail';
    const isNumeric = ['number', 'currency', 'percent'].includes(field.kind);
    const isNumericFormula = isFormula && ['Number', 'Currency', 'Percent'].includes(field.type);

    if (field.kind === 'checkbox') {
        lines.push(tag('defaultValue', field.default === true, I));
    } else if (field.default !== undefined && !isFormula && field.kind !== 'picklist') {
        lines.push(tag('defaultValue', field.default, I));
    }

    if (field.kind === 'lookup') {
        lines.push(tag('deleteConstraint', field.required ? 'Restrict' : (field.deleteConstraint ?? 'SetNull'), I));
    }
    if (field.description) lines.push(tag('description', field.description, I));
    if (field.externalId !== undefined && !isFormula && !isSummary) {
        lines.push(tag('externalId', field.externalId === true, I));
    }
    if (field.manageability) lines.push(tag('fieldManageability', field.manageability, I));
    if (isFormula) {
        lines.push(tag('formula', field.formula, I));
        if (field.type === 'Checkbox') {
            lines.push(tag('formulaTreatBlanksAs', 'BlankAsZero', I));
        } else if (field.type !== 'Text') {
            lines.push(tag('formulaTreatBlanksAs', field.blanksAsZero === false ? 'BlankAsBlank' : 'BlankAsZero', I));
        }
    }
    if (field.helpText) lines.push(tag('inlineHelpText', field.helpText, I));
    lines.push(tag('label', label, I));

    // TextArea (255) carries no length element; Text and LongTextArea do.
    if (field.kind === 'text') lines.push(tag('length', field.length ?? 255, I));
    if (field.kind === 'longtextarea') lines.push(tag('length', field.length ?? 5000, I));

    if (isNumeric) {
        lines.push(tag('precision', field.precision, I));
    } else if (isNumericFormula) {
        lines.push(tag('precision', field.precision ?? 18, I));
    }

    if (isRelationship) {
        lines.push(tag('referenceTo', field.referenceTo, I));
        lines.push(tag('relationshipLabel', field.relationshipLabel ?? `${label}s`, I));
        lines.push(tag('relationshipName', field.relationshipName, I));
    }
    if (field.kind === 'masterdetail') {
        lines.push(tag('relationshipOrder', field.relationshipOrder ?? 0, I));
        lines.push(tag('reparentableMasterDetail', field.reparentable === true, I));
    }
    if (!isFormula && !isSummary && field.kind !== 'masterdetail' && field.kind !== 'checkbox') {
        lines.push(tag('required', field.required === true, I));
    }

    if (isNumeric) {
        lines.push(tag('scale', field.scale, I));
    } else if (isNumericFormula) {
        lines.push(tag('scale', field.scale ?? 2, I));
    }

    if (isSummary) {
        if (field.summarizedField) lines.push(tag('summarizedField', field.summarizedField, I));
        for (const filter of field.filters ?? []) {
            lines.push(`${I}<summaryFilterItems>`);
            lines.push(tag('field', filter.field, `${I}${I}`));
            lines.push(tag('operation', filter.operation, `${I}${I}`));
            if (filter.value !== undefined) lines.push(tag('value', filter.value, `${I}${I}`));
            lines.push(`${I}</summaryFilterItems>`);
        }
        lines.push(tag('summaryForeignKey', field.foreignKey, I));
        lines.push(tag('summaryOperation', field.operation, I));
    }

    if (field.trackHistory) lines.push(tag('trackHistory', true, I));

    if (isFormula) {
        lines.push(tag('type', field.type, I));
    } else if (isSummary) {
        lines.push(tag('type', 'Summary', I));
    } else {
        lines.push(tag('type', METADATA_TYPE[field.kind], I));
    }

    // Only emitted when true; the element is rejected on types that cannot be unique.
    if (field.unique === true) lines.push(tag('unique', true, I));
    if (field.kind === 'picklist') picklistValueSet(field, lines);
    if (field.kind === 'longtextarea') lines.push(tag('visibleLines', field.visibleLines ?? 5, I));
    if (field.kind === 'masterdetail') {
        lines.push(tag('writeRequiresMasterRead', field.writeRequiresMasterRead === true, I));
    }

    lines.push('</CustomField>');
    return lines;
}

/* ------------------------------------------------------------------ */
/* Objects, validation rules, list views                               */
/* ------------------------------------------------------------------ */

export const COMPACT_LAYOUT = 'eLogix_Compact';

export function buildObject(def) {
    const lines = [XML_HEADER, `<CustomObject xmlns="${NS}">`];
    if (def.listColumns) lines.push(tag('compactLayoutAssignment', COMPACT_LAYOUT, I));
    lines.push(tag('deploymentStatus', 'Deployed', I));
    if (def.description) lines.push(tag('description', def.description, I));
    lines.push(tag('enableActivities', def.enableActivities === true, I));
    // enableBulkApi, enableSharing and enableStreamingApi must agree (Enterprise Application object).
    lines.push(tag('enableBulkApi', true, I));
    lines.push(tag('enableFeeds', false, I));
    lines.push(tag('enableHistory', def.enableHistory === true, I));
    lines.push(tag('enableReports', true, I));
    lines.push(tag('enableSearch', true, I));
    lines.push(tag('enableSharing', true, I));
    lines.push(tag('enableStreamingApi', true, I));
    // External access is never wider than internal; Private until Experience Cloud is introduced.
    lines.push(tag('externalSharingModel', def.sharingModel === 'ControlledByParent' ? 'ControlledByParent' : 'Private', I));
    lines.push(tag('label', def.label, I));

    lines.push(`${I}<nameField>`);
    if (def.nameField.displayFormat) {
        lines.push(tag('displayFormat', def.nameField.displayFormat, `${I}${I}`));
    }
    lines.push(tag('label', def.nameField.label, `${I}${I}`));
    lines.push(tag('trackHistory', false, `${I}${I}`));
    lines.push(tag('type', def.nameField.displayFormat ? 'AutoNumber' : 'Text', `${I}${I}`));
    lines.push(`${I}</nameField>`);

    lines.push(tag('pluralLabel', def.pluralLabel, I));
    lines.push(tag('sharingModel', def.sharingModel, I));
    lines.push(tag('visibility', 'Public', I));
    lines.push('</CustomObject>');
    return lines;
}

/**
 * Validation rules carry a bypass guard so the idempotent seed script (and future data
 * migrations) can load historical records under the eLogix_Data_Migration permission set.
 */
export const BYPASS_PERMISSION = 'eLogix_Bypass_Validation_Rules';

export function buildValidationRule(rule) {
    const condition = rule.noBypass ? rule.formula : `AND(\n    NOT($Permission.${BYPASS_PERMISSION}),\n    ${rule.formula}\n)`;
    const lines = [XML_HEADER, `<ValidationRule xmlns="${NS}">`];
    lines.push(tag('fullName', rule.name, I));
    lines.push(tag('active', true, I));
    if (rule.description) lines.push(tag('description', rule.description, I));
    lines.push(tag('errorConditionFormula', condition, I));
    if (rule.field) lines.push(tag('errorDisplayField', rule.field, I));
    lines.push(tag('errorMessage', rule.message, I));
    lines.push('</ValidationRule>');
    return lines;
}

export function buildListView(columns) {
    const lines = [XML_HEADER, `<ListView xmlns="${NS}">`];
    lines.push(tag('fullName', 'All', I));
    for (const column of ['NAME', ...columns]) lines.push(tag('columns', column, I));
    lines.push(tag('filterScope', 'Everything', I));
    lines.push(tag('label', 'All', I));
    lines.push('</ListView>');
    return lines;
}

/** A named list view with filters (Phase 4), e.g. vehicles whose documents expire soon. */
export function buildFilteredListView(view, defaultColumns) {
    const lines = [XML_HEADER, `<ListView xmlns="${NS}">`];
    lines.push(tag('fullName', view.name, I));
    for (const column of ['NAME', ...(view.columns ?? defaultColumns)]) lines.push(tag('columns', column, I));
    lines.push(tag('filterScope', 'Everything', I));
    for (const filter of view.filters ?? []) {
        lines.push(`${I}<filters>`);
        lines.push(tag('field', filter.field, `${I}${I}`));
        lines.push(tag('operation', filter.operation, `${I}${I}`));
        lines.push(tag('value', filter.value, `${I}${I}`));
        lines.push(`${I}</filters>`);
    }
    lines.push(tag('label', view.label, I));
    lines.push('</ListView>');
    return lines;
}

/** Highlights-panel fields on Lightning record pages: Name plus the first list view columns. */
export function buildCompactLayout(columns) {
    const lines = [XML_HEADER, `<CompactLayout xmlns="${NS}">`];
    lines.push(tag('fullName', COMPACT_LAYOUT, I));
    for (const field of ['Name', ...columns]) lines.push(tag('fields', field, I));
    lines.push(tag('label', 'eLogix Compact', I));
    lines.push('</CompactLayout>');
    return lines;
}

/* ------------------------------------------------------------------ */
/* Page layouts                                                        */
/* ------------------------------------------------------------------ */

const NOTE_KINDS = new Set(['textarea', 'longtextarea']);

/** Layout behaviour the platform expects for a field. */
function behaviorFor(field) {
    if (isComputedField(field)) return 'Readonly';
    if (field.kind === 'masterdetail' || (field.required && field.kind !== 'checkbox')) return 'Required';
    return 'Edit';
}

function layoutSection(label, style, columns) {
    const lines = [`${I}<layoutSections>`];
    lines.push(tag('customLabel', label !== 'Information' && label !== 'System Information', `${I}${I}`));
    lines.push(tag('detailHeading', true, `${I}${I}`));
    lines.push(tag('editHeading', true, `${I}${I}`));
    lines.push(tag('label', label, `${I}${I}`));
    for (const items of columns) {
        if (items.length === 0) {
            lines.push(`${I}${I}<layoutColumns/>`);
            continue;
        }
        lines.push(`${I}${I}<layoutColumns>`);
        for (const item of items) {
            lines.push(`${I}${I}${I}<layoutItems>`);
            lines.push(tag('behavior', item.behavior, `${I}${I}${I}${I}`));
            lines.push(tag('field', item.field, `${I}${I}${I}${I}`));
            lines.push(`${I}${I}${I}</layoutItems>`);
        }
        lines.push(`${I}${I}</layoutColumns>`);
    }
    lines.push(tag('style', style, `${I}${I}`));
    lines.push(`${I}</layoutSections>`);
    return lines;
}

/** Splits items top-to-bottom across two columns. */
function twoColumns(items) {
    const half = Math.ceil(items.length / 2);
    return [items.slice(0, half), items.slice(half)];
}

function layoutTail(lines) {
    lines.push(tag('showEmailCheckbox', false, I));
    lines.push(tag('showHighlightsPanel', false, I));
    lines.push(tag('showInteractionLogPanel', false, I));
    lines.push(tag('showRunAssignmentRulesCheckbox', false, I));
    lines.push(tag('showSubmitAndAttachButton', false, I));
    lines.push('</Layout>');
    return lines;
}

/**
 * Page layout for a custom object: Information (editable fields), Totals and Indicators
 * (formulas and roll-ups), Notes (text areas), System Information, then related lists.
 * `relatedLists` is [{ relatedList, fields? }] computed by the scaffolder from the model.
 */
export function buildLayout(def, relatedLists) {
    const lines = [XML_HEADER, `<Layout xmlns="${NS}">`];
    const nameItem = { field: 'Name', behavior: def.nameField.displayFormat ? 'Readonly' : 'Required' };
    const fields = def.fields.map((f) => ({ field: f.api, behavior: behaviorFor(f), kind: f.kind, computed: isComputedField(f) }));

    const info = [nameItem, ...fields.filter((f) => !f.computed && !NOTE_KINDS.has(f.kind))];
    lines.push(...layoutSection('Information', 'TwoColumnsTopToBottom', twoColumns(info)));

    const computed = fields.filter((f) => f.computed);
    if (computed.length) lines.push(...layoutSection('Totals and Indicators', 'TwoColumnsTopToBottom', twoColumns(computed)));

    const notes = fields.filter((f) => !f.computed && NOTE_KINDS.has(f.kind));
    if (notes.length) lines.push(...layoutSection('Notes', 'OneColumn', [notes]));

    const ownerColumn = def.sharingModel === 'ControlledByParent' ? [] : [{ field: 'OwnerId', behavior: 'Edit' }];
    lines.push(
        ...layoutSection('System Information', 'TwoColumnsTopToBottom', [
            [{ field: 'CreatedById', behavior: 'Readonly' }, ...ownerColumn],
            [{ field: 'LastModifiedById', behavior: 'Readonly' }]
        ])
    );

    for (const list of relatedLists) {
        lines.push(`${I}<relatedLists>`);
        for (const field of list.fields ?? []) lines.push(tag('fields', field, `${I}${I}`));
        lines.push(tag('relatedList', list.relatedList, `${I}${I}`));
        lines.push(`${I}</relatedLists>`);
    }
    return layoutTail(lines);
}

/** Page layout for a custom metadata type, mirroring the shape the platform auto-generates. */
export function buildMetadataTypeLayout(def) {
    const lines = [XML_HEADER, `<Layout xmlns="${NS}">`];
    const left = [
        { field: 'MasterLabel', behavior: 'Required' },
        { field: 'DeveloperName', behavior: 'Required' },
        ...def.fields.map((f) => ({ field: f.api, behavior: f.required ? 'Required' : 'Edit' }))
    ];
    const right = [
        { field: 'IsProtected', behavior: 'Edit' },
        { field: 'NamespacePrefix', behavior: 'Required' }
    ];
    lines.push(...layoutSection('Information', 'TwoColumnsTopToBottom', [left, right]));
    lines.push(
        ...layoutSection('System Information', 'TwoColumnsTopToBottom', [
            [{ field: 'CreatedById', behavior: 'Readonly' }],
            [{ field: 'LastModifiedById', behavior: 'Readonly' }]
        ])
    );
    return layoutTail(lines);
}

/* ------------------------------------------------------------------ */
/* Custom metadata types and records                                    */
/* ------------------------------------------------------------------ */

export function buildMetadataType(def) {
    const lines = [XML_HEADER, `<CustomObject xmlns="${NS}">`];
    if (def.description) lines.push(tag('description', def.description, I));
    lines.push(tag('label', def.label, I));
    lines.push(tag('pluralLabel', def.pluralLabel, I));
    lines.push(tag('visibility', 'Public', I));
    lines.push('</CustomObject>');
    return lines;
}

const XSD_TYPE = { text: 'xsd:string', checkbox: 'xsd:boolean', number: 'xsd:double' };

export function buildMetadataRecord(typeDef, record) {
    const lines = [
        XML_HEADER,
        `<CustomMetadata xmlns="${NS}" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xmlns:xsd="http://www.w3.org/2001/XMLSchema">`
    ];
    lines.push(tag('label', record.label, I));
    lines.push(tag('protected', false, I));
    for (const field of typeDef.fields) {
        const value = record.values[field.api];
        lines.push(`${I}<values>`);
        lines.push(tag('field', field.api, `${I}${I}`));
        if (value === undefined || value === null || value === '') {
            lines.push(`${I}${I}<value xsi:nil="true"/>`);
        } else {
            lines.push(`${I}${I}<value xsi:type="${XSD_TYPE[field.kind]}">${esc(value)}</value>`);
        }
        lines.push(`${I}</values>`);
    }
    lines.push('</CustomMetadata>');
    return lines;
}

/* ------------------------------------------------------------------ */
/* Custom permissions, tabs, application                               */
/* ------------------------------------------------------------------ */

export function buildCustomPermission(def) {
    const lines = [XML_HEADER, `<CustomPermission xmlns="${NS}">`];
    lines.push(tag('description', def.description, I));
    lines.push(tag('isLicensed', false, I));
    lines.push(tag('label', def.label, I));
    lines.push('</CustomPermission>');
    return lines;
}

export function buildTab(motif) {
    return [
        XML_HEADER,
        `<CustomTab xmlns="${NS}">`,
        tag('customObject', true, I),
        tag('motif', motif, I),
        '</CustomTab>'
    ];
}

export function buildApplication(app) {
    const lines = [XML_HEADER, `<CustomApplication xmlns="${NS}">`];
    lines.push(`${I}<brand>`);
    lines.push(tag('headerColor', app.headerColor, `${I}${I}`));
    lines.push(tag('shouldOverrideOrgTheme', false, `${I}${I}`));
    lines.push(`${I}</brand>`);
    lines.push(tag('description', app.description, I));
    lines.push(tag('formFactors', 'Small', I));
    lines.push(tag('formFactors', 'Large', I));
    // Element set mirrors a Lightning app retrieved from the target org (API 67/68).
    lines.push(tag('isNavAutoTempTabsDisabled', false, I));
    lines.push(tag('isNavPersonalizationDisabled', false, I));
    lines.push(tag('isNavTabPersistenceDisabled', false, I));
    lines.push(tag('label', app.label, I));
    lines.push(tag('navType', 'Standard', I));
    for (const tab of app.tabs) lines.push(tag('tabs', tab, I));
    lines.push(tag('uiType', 'Lightning', I));
    lines.push('</CustomApplication>');
    return lines;
}

/* ------------------------------------------------------------------ */
/* Permission sets                                                     */
/* ------------------------------------------------------------------ */

/**
 * Access strings use the letters C R E D V M (Create, Read, Edit, Delete, View All, Modify All).
 * `resolved` is produced by the security model: { objects: Map<api, access>, fields: [...], ... }.
 */
export function buildPermissionSet(def, resolved) {
    const lines = [XML_HEADER, `<PermissionSet xmlns="${NS}">`];

    for (const app of resolved.applications) {
        lines.push(`${I}<applicationVisibilities>`);
        lines.push(tag('application', app, `${I}${I}`));
        lines.push(tag('visible', true, `${I}${I}`));
        lines.push(`${I}</applicationVisibilities>`);
    }
    for (const type of resolved.metadataTypes) {
        lines.push(`${I}<customMetadataTypeAccesses>`);
        lines.push(tag('enabled', true, `${I}${I}`));
        lines.push(tag('name', type, `${I}${I}`));
        lines.push(`${I}</customMetadataTypeAccesses>`);
    }
    for (const permission of resolved.customPermissions) {
        lines.push(`${I}<customPermissions>`);
        lines.push(tag('enabled', true, `${I}${I}`));
        lines.push(tag('name', permission, `${I}${I}`));
        lines.push(`${I}</customPermissions>`);
    }
    lines.push(tag('description', def.description, I));
    for (const fp of resolved.fields) {
        lines.push(`${I}<fieldPermissions>`);
        lines.push(tag('editable', fp.editable, `${I}${I}`));
        lines.push(tag('field', fp.field, `${I}${I}`));
        lines.push(tag('readable', true, `${I}${I}`));
        lines.push(`${I}</fieldPermissions>`);
    }
    lines.push(tag('hasActivationRequired', false, I));
    lines.push(tag('label', def.label, I));
    for (const [object, access] of resolved.objects) {
        lines.push(`${I}<objectPermissions>`);
        lines.push(tag('allowCreate', access.includes('C'), `${I}${I}`));
        lines.push(tag('allowDelete', access.includes('D'), `${I}${I}`));
        lines.push(tag('allowEdit', access.includes('E'), `${I}${I}`));
        lines.push(tag('allowRead', access.includes('R'), `${I}${I}`));
        lines.push(tag('modifyAllRecords', access.includes('M'), `${I}${I}`));
        lines.push(tag('object', object, `${I}${I}`));
        lines.push(tag('viewAllRecords', access.includes('V'), `${I}${I}`));
        lines.push(`${I}</objectPermissions>`);
    }
    for (const tab of resolved.tabs) {
        lines.push(`${I}<tabSettings>`);
        lines.push(tag('tab', tab, `${I}${I}`));
        lines.push(tag('visibility', 'Visible', `${I}${I}`));
        lines.push(`${I}</tabSettings>`);
    }
    lines.push('</PermissionSet>');
    return lines;
}

/* ------------------------------------------------------------------ */
/* Orchestration                                                       */
/* ------------------------------------------------------------------ */

export function emitObjects(objects, root) {
    const written = [];
    for (const def of objects) {
        const dir = join(root, 'objects', def.api);
        if (!def.standard) {
            written.push(writeFile(join(dir, `${def.api}.object-meta.xml`), buildObject(def)));
        }
        for (const field of def.fields) {
            written.push(writeFile(join(dir, 'fields', `${field.api}.field-meta.xml`), buildField(field)));
        }
        for (const rule of def.rules ?? []) {
            written.push(writeFile(join(dir, 'validationRules', `${rule.name}.validationRule-meta.xml`), buildValidationRule(rule)));
        }
        if (def.listColumns) {
            written.push(writeFile(join(dir, 'listViews', 'All.listView-meta.xml'), buildListView(def.listColumns)));
            for (const view of def.listViews ?? []) {
                written.push(writeFile(join(dir, 'listViews', `${view.name}.listView-meta.xml`), buildFilteredListView(view, def.listColumns)));
            }
            written.push(
                writeFile(join(dir, 'compactLayouts', `${COMPACT_LAYOUT}.compactLayout-meta.xml`), buildCompactLayout(def.listColumns.slice(0, 4)))
            );
        }
        if (def.tab) {
            written.push(writeFile(join(root, 'tabs', `${def.api}.tab-meta.xml`), buildTab(def.tab)));
        }
        if (!def.standard) {
            written.push(writeFile(join(root, 'layouts', `${def.api}-${def.label} Layout.layout-meta.xml`), buildLayout(def, def.relatedLists ?? [])));
        }
    }
    return written;
}

export function emitGlobalValueSets(valueSets, root) {
    return valueSets.map((def) =>
        writeFile(join(root, 'globalValueSets', `${def.api}.globalValueSet-meta.xml`), buildGlobalValueSet(def))
    );
}

export function emitMetadataTypes(types, root) {
    const written = [];
    for (const def of types) {
        const dir = join(root, 'objects', def.api);
        written.push(writeFile(join(dir, `${def.api}.object-meta.xml`), buildMetadataType(def)));
        for (const field of def.fields) {
            written.push(
                writeFile(join(dir, 'fields', `${field.api}.field-meta.xml`), buildField({ ...field, manageability: 'DeveloperControlled' }))
            );
        }
        const typeName = def.api.replace(/__mdt$/, '');
        written.push(writeFile(join(root, 'layouts', `${def.api}-${def.label} Layout.layout-meta.xml`), buildMetadataTypeLayout(def)));
        for (const record of def.records) {
            written.push(writeFile(join(root, 'customMetadata', `${typeName}.${record.name}.md-meta.xml`), buildMetadataRecord(def, record)));
        }
    }
    return written;
}

export function emitCustomPermissions(permissions, root) {
    return permissions.map((def) =>
        writeFile(join(root, 'customPermissions', `${def.api}.customPermission-meta.xml`), buildCustomPermission(def))
    );
}

export function emitApplication(app, root) {
    return [writeFile(join(root, 'applications', `${app.api}.app-meta.xml`), buildApplication(app))];
}

export function emitPermissionSets(resolvedSets, root) {
    return resolvedSets.map(({ def, resolved }) =>
        writeFile(join(root, 'permissionsets', `${def.api}.permissionset-meta.xml`), buildPermissionSet(def, resolved))
    );
}

export { writeFile, tag, esc };
