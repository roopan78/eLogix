/**
 * eLogix ERP - Phase 9 role hierarchy and owner-based sharing rules. Pure functions returning XML
 * lines; scaffold-metadata.mjs validates the model and calls emitSharing.
 */
import { join } from 'node:path';
import { writeFile, tag } from './metadata-writer.mjs';

const XML_HEADER = '<?xml version="1.0" encoding="UTF-8"?>';
const NS = 'http://soap.sforce.com/2006/04/metadata';
const I = '    ';

/**
 * Match the target org's standard-object defaults: Case and Opportunity are Public Read/Write, so both
 * role access levels must be Edit. Contact remains None because its org default permits it.
 */
export function buildRole(role) {
    const lines = [XML_HEADER, `<Role xmlns="${NS}">`];
    lines.push(tag('caseAccessLevel', 'Edit', I));
    lines.push(tag('contactAccessLevel', 'None', I));
    lines.push(tag('description', role.description, I));
    lines.push(tag('mayForecastManagerShare', false, I));
    lines.push(tag('name', role.label, I));
    lines.push(tag('opportunityAccessLevel', 'Edit', I));
    if (role.parent) lines.push(tag('parentRole', role.parent, I));
    lines.push('</Role>');
    return lines;
}

/** Owner-based sharing rules for one object: records owned by `fromRoleAndSubordinates` shared to a role. */
export function buildSharingRules(rules) {
    const lines = [XML_HEADER, `<SharingRules xmlns="${NS}">`];
    for (const rule of rules) {
        lines.push(`${I}<sharingOwnerRules>`);
        lines.push(tag('fullName', rule.api, `${I}${I}`));
        lines.push(tag('accessLevel', rule.access, `${I}${I}`));
        lines.push(tag('description', rule.description, `${I}${I}`));
        lines.push(tag('label', rule.label, `${I}${I}`));
        lines.push(`${I}${I}<sharedFrom>`);
        lines.push(tag('roleAndSubordinates', rule.fromRoleAndSubordinates, `${I}${I}${I}`));
        lines.push(`${I}${I}</sharedFrom>`);
        lines.push(`${I}${I}<sharedTo>`);
        lines.push(tag('role', rule.toRole, `${I}${I}${I}`));
        lines.push(`${I}${I}</sharedTo>`);
        lines.push(`${I}</sharingOwnerRules>`);
    }
    lines.push('</SharingRules>');
    return lines;
}

export function emitSharing(roles, sharingRules, root) {
    const written = roles.map((role) => writeFile(join(root, 'roles', `${role.api}.role-meta.xml`), buildRole(role)));
    const byObject = new Map();
    for (const rule of sharingRules) {
        if (!byObject.has(rule.object)) byObject.set(rule.object, []);
        byObject.get(rule.object).push(rule);
    }
    for (const [object, rules] of byObject) {
        written.push(writeFile(join(root, 'sharingRules', `${object}.sharingRules-meta.xml`), buildSharingRules(rules)));
    }
    return written;
}
