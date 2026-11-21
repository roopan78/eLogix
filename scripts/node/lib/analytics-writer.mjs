/**
 * eLogix ERP - Phase 8 analytics metadata writer: custom report types, report and dashboard folders,
 * summary reports and grid dashboards. Pure functions that return XML lines; scaffold-metadata.mjs
 * validates the model and calls emitAnalytics.
 */
import { join } from 'node:path';
import { writeFile, tag } from './metadata-writer.mjs';

const XML_HEADER = '<?xml version="1.0" encoding="UTF-8"?>';
const NS = 'http://soap.sforce.com/2006/04/metadata';
const I = '    ';
const STANDARD_FIELDS = new Set(['Name', 'CreatedDate']);

/** Report column name: Base$Field, or Base.Relationship$Field for a joined child field. */
export function reportColumn(reportType, field) {
    const dot = field.indexOf('.');
    return dot < 0 ? `${reportType.base}$${field}` : `${reportType.base}.${field.slice(0, dot)}$${field.slice(dot + 1)}`;
}

export function isStandardField(field) {
    return STANDARD_FIELDS.has(field);
}

/* ------------------------------------------------------------------ */
/* Report types and folders                                            */
/* ------------------------------------------------------------------ */

export function buildReportType(def) {
    const lines = [XML_HEADER, `<ReportType xmlns="${NS}">`];
    lines.push(tag('baseObject', def.base, I));
    lines.push(tag('category', 'other', I));
    lines.push(tag('deployed', true, I));
    lines.push(tag('description', def.description, I));
    if (def.join) {
        lines.push(`${I}<join>`);
        lines.push(tag('outerJoin', false, `${I}${I}`));
        lines.push(tag('relationship', def.join.relationship, `${I}${I}`));
        lines.push(`${I}</join>`);
    }
    lines.push(tag('label', def.label, I));
    const section = (table, fields, label) => {
        lines.push(`${I}<sections>`);
        for (const field of fields) {
            lines.push(`${I}${I}<columns>`);
            lines.push(tag('checkedByDefault', false, `${I}${I}${I}`));
            lines.push(tag('field', field, `${I}${I}${I}`));
            lines.push(tag('table', table, `${I}${I}${I}`));
            lines.push(`${I}${I}</columns>`);
        }
        lines.push(tag('masterLabel', label, `${I}${I}`));
        lines.push(`${I}</sections>`);
    };
    section(def.base, def.fields, def.sectionLabel);
    if (def.join) section(`${def.base}.${def.join.relationship}`, def.join.fields, def.join.sectionLabel);
    lines.push('</ReportType>');
    return lines;
}

/** Report and dashboard folders, viewable by every internal user (role-based sharing is Phase 9). */
export function buildFolder(kind, folder) {
    const root = kind === 'report' ? 'ReportFolder' : 'DashboardFolder';
    return [
        XML_HEADER,
        `<${root} xmlns="${NS}">`,
        `${I}<folderShares>`,
        tag('accessLevel', 'View', `${I}${I}`),
        tag('sharedTo', 'AllInternalUsers', `${I}${I}`),
        tag('sharedToType', 'Group', `${I}${I}`),
        `${I}</folderShares>`,
        tag('name', folder.label, I),
        `</${root}>`
    ];
}

/* ------------------------------------------------------------------ */
/* Reports                                                             */
/* ------------------------------------------------------------------ */

export function buildReport(def, reportType) {
    const col = (field) => reportColumn(reportType, field);
    const lines = [XML_HEADER, `<Report xmlns="${NS}">`];
    const column = (field, aggregate) => {
        lines.push(`${I}<columns>`);
        if (aggregate) lines.push(tag('aggregateTypes', aggregate, `${I}${I}`));
        lines.push(tag('field', col(field), `${I}${I}`));
        lines.push(`${I}</columns>`);
    };
    for (const field of def.columns) column(field);
    for (const field of def.sum ?? []) column(field, 'Sum');
    for (const field of def.average ?? []) column(field, 'Average');
    lines.push(tag('description', def.description, I));
    if (def.filters?.length) {
        lines.push(`${I}<filter>`);
        for (const filter of def.filters) {
            lines.push(`${I}${I}<criteriaItems>`);
            lines.push(tag('column', col(filter.field), `${I}${I}${I}`));
            lines.push(tag('isUnlocked', true, `${I}${I}${I}`));
            lines.push(tag('operator', filter.operator, `${I}${I}${I}`));
            lines.push(tag('value', filter.value, `${I}${I}${I}`));
            lines.push(`${I}${I}</criteriaItems>`);
        }
        lines.push(tag('language', 'en_US', `${I}${I}`));
        lines.push(`${I}</filter>`);
    }
    lines.push(tag('format', 'Summary', I));
    for (const group of def.groupBy) {
        lines.push(`${I}<groupingsDown>`);
        lines.push(tag('dateGranularity', group.granularity ?? 'Day', `${I}${I}`));
        lines.push(tag('field', col(group.field), `${I}${I}`));
        lines.push(tag('sortOrder', 'Asc', `${I}${I}`));
        lines.push(`${I}</groupingsDown>`);
    }
    lines.push(tag('name', def.name, I));
    lines.push(tag('reportType', `${reportType.api}__c`, I));
    lines.push(tag('scope', 'organization', I));
    lines.push(tag('showDetails', true, I));
    lines.push(tag('showGrandTotal', true, I));
    lines.push(tag('showSubTotals', true, I));
    if (reportType.fields.includes('CreatedDate')) {
        lines.push(`${I}<timeFrameFilter>`);
        lines.push(tag('dateColumn', col('CreatedDate'), `${I}${I}`));
        lines.push(tag('interval', 'INTERVAL_CUSTOM', `${I}${I}`));
        lines.push(`${I}</timeFrameFilter>`);
    }
    lines.push('</Report>');
    return lines;
}

/* ------------------------------------------------------------------ */
/* Dashboards                                                          */
/* ------------------------------------------------------------------ */

function summaryLines(summary, reportType, indent) {
    const lines = [`${indent}<chartSummary>`];
    const inner = `${indent}${I}`;
    if (summary === 'RowCount') {
        lines.push(tag('axisBinding', 'y', inner));
        lines.push(tag('column', 'RowCount', inner));
    } else {
        const [aggregate, field] = summary.sum ? ['Sum', summary.sum] : ['Average', summary.average];
        lines.push(tag('aggregate', aggregate, inner));
        lines.push(tag('axisBinding', 'y', inner));
        lines.push(tag('column', reportColumn(reportType, field), inner));
    }
    lines.push(`${indent}</chartSummary>`);
    return lines;
}

/**
 * runningUser: the fixed running user's username (decision of 2026-11-20), from the generator's
 * environment (ELOGIX_DASHBOARD_RUNNING_USER) so that no username is stored in the model. When it is
 * not set, the element is omitted.
 */
export function buildDashboard(def, reportsByApi, reportTypesByApi, folder, runningUser) {
    const lines = [XML_HEADER, `<Dashboard xmlns="${NS}">`];
    lines.push(tag('backgroundEndColor', '#FFFFFF', I));
    lines.push(tag('backgroundFadeDirection', 'Diagonal', I));
    lines.push(tag('backgroundStartColor', '#FFFFFF', I));
    lines.push(tag('chartTheme', 'light', I));
    lines.push(tag('colorPalette', 'unity', I));
    lines.push(tag('dashboardChartTheme', 'light', I));
    lines.push(tag('dashboardColorPalette', 'unity', I));
    lines.push(`${I}<dashboardGridLayout>`);
    const I2 = `${I}${I}`;
    const I3 = `${I2}${I}`;
    const I4 = `${I3}${I}`;
    for (const component of def.components) {
        const report = reportsByApi.get(component.report);
        const reportType = reportTypesByApi.get(report.type);
        const isMetric = component.type === 'Metric';
        lines.push(`${I2}<dashboardGridComponents>`);
        lines.push(tag('colSpan', component.colSpan, I3));
        lines.push(tag('columnIndex', component.col, I3));
        lines.push(`${I3}<dashboardComponent>`);
        // Explicit chartSummary and groupingColumn: not taken from the report.
        lines.push(tag('autoselectColumnsFromReport', false, I4));
        if (!isMetric) lines.push(tag('chartAxisRange', 'Auto', I4));
        lines.push(...summaryLines(component.summary, reportType, I4));
        lines.push(tag('componentType', component.type, I4));
        lines.push(tag('displayUnits', 'Auto', I4));
        if (!isMetric) {
            lines.push(tag('drillEnabled', false, I4));
            lines.push(tag('drillToDetailEnabled', false, I4));
            lines.push(tag('enableHover', true, I4));
            lines.push(tag('expandOthers', false, I4));
            lines.push(tag('groupingColumn', reportColumn(reportType, report.groupBy[0].field), I4));
        }
        lines.push(`${I4}<groupingSortProperties/>`);
        lines.push(tag('header', component.header, I4));
        if (isMetric) {
            lines.push(tag('indicatorHighColor', '#54C254', I4));
            lines.push(tag('indicatorLowColor', '#C25454', I4));
            lines.push(tag('indicatorMiddleColor', '#C2C254', I4));
        } else {
            lines.push(tag('legendPosition', 'Bottom', I4));
        }
        lines.push(tag('report', `${folder.api}/${report.api}`, I4));
        if (component.type === 'Donut') {
            lines.push(tag('showPercentage', true, I4));
        }
        if (isMetric) {
            lines.push(tag('showRange', false, I4));
        } else {
            lines.push(tag('showTotal', component.type === 'Donut', I4));
            lines.push(tag('showValues', true, I4));
            lines.push(tag('sortBy', 'RowLabelAscending', I4));
            lines.push(tag('useReportChart', false, I4));
        }
        lines.push(`${I3}</dashboardComponent>`);
        lines.push(tag('rowIndex', component.row, I3));
        lines.push(tag('rowSpan', component.rowSpan, I3));
        lines.push(`${I2}</dashboardGridComponents>`);
    }
    lines.push(tag('numberOfColumns', 12, I2));
    lines.push(tag('rowHeight', 36, I2));
    lines.push(`${I}</dashboardGridLayout>`);
    lines.push(tag('dashboardType', 'SpecifiedUser', I));
    lines.push(tag('description', def.description, I));
    lines.push(tag('isGridLayout', true, I));
    if (runningUser) lines.push(tag('runningUser', runningUser, I));
    lines.push(tag('textColor', '#000000', I));
    lines.push(tag('title', def.title, I));
    lines.push(tag('titleColor', '#000000', I));
    lines.push(tag('titleSize', 12, I));
    lines.push('</Dashboard>');
    return lines;
}

/* ------------------------------------------------------------------ */
/* Orchestration                                                       */
/* ------------------------------------------------------------------ */

export function emitAnalytics({ reportTypes, reports, dashboards, reportFolder, dashboardFolder }, root, runningUser) {
    const written = [];
    const reportTypesByApi = new Map(reportTypes.map((t) => [t.api, t]));
    const reportsByApi = new Map(reports.map((r) => [r.api, r]));
    for (const def of reportTypes) {
        written.push(writeFile(join(root, 'reportTypes', `${def.api}.reportType-meta.xml`), buildReportType(def)));
    }
    written.push(writeFile(join(root, 'reports', `${reportFolder.api}.reportFolder-meta.xml`), buildFolder('report', reportFolder)));
    for (const def of reports) {
        written.push(
            writeFile(join(root, 'reports', reportFolder.api, `${def.api}.report-meta.xml`), buildReport(def, reportTypesByApi.get(def.type)))
        );
    }
    written.push(writeFile(join(root, 'dashboards', `${dashboardFolder.api}.dashboardFolder-meta.xml`), buildFolder('dashboard', dashboardFolder)));
    for (const def of dashboards) {
        written.push(
            writeFile(
                join(root, 'dashboards', dashboardFolder.api, `${def.api}.dashboard-meta.xml`),
                buildDashboard(def, reportsByApi, reportTypesByApi, reportFolder, runningUser)
            )
        );
    }
    return written;
}
