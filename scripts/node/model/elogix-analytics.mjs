/**
 * eLogix ERP - Phase 8 analytics: custom report types, reports and dashboards (native Salesforce).
 *
 * Field references:
 *   - In a report type, base-object fields are plain API names; child fields belong to the join.
 *   - In a report, a base field is its API name ('Status__c'); a joined child field is prefixed with
 *     the relationship ('Deliveries__r.Delivery_Status__c'). The generator writes the report column
 *     names (Shipment__c$Status__c, Shipment__c.Deliveries__r$Delivery_Status__c) and checks every
 *     field against the report type and the data model.
 *
 * Metrics use only implemented data. There are no invoices or payments yet (Phase 5B), so money
 * metrics are "delivered freight value" (Shipment__c.Freight_Amount__c on delivered or closed
 * shipments, Is_Billable__c) and quotation value, never invoiced revenue.
 */

export const REPORT_FOLDER = { api: 'eLogix_Reports', label: 'eLogix Reports' };
export const DASHBOARD_FOLDER = { api: 'eLogix_Dashboards', label: 'eLogix Dashboards' };

/** Statuses of a shipment that has been confirmed and is not yet finished. */
export const ACTIVE_SHIPMENT_STATUSES = [
    'Confirmed',
    'Ready for Dispatch',
    'Dispatched',
    'In Transit',
    'Out for Delivery',
    'On Hold',
    'Delayed',
    'Failed Delivery'
];

/* ------------------------------------------------------------------ */
/* Custom report types                                                 */
/* ------------------------------------------------------------------ */

export const REPORT_TYPES = [
    {
        api: 'eLogix_Shipments',
        label: 'eLogix Shipments',
        description: 'Shipments with customer, business unit, lane, dates, freight, status and delivery KPIs.',
        base: 'Shipment__c',
        sectionLabel: 'Shipment',
        fields: [
            'Name', 'CreatedDate', 'Customer__c', 'Business_Unit__c', 'Route__c', 'Origin__c', 'Destination__c',
            'Weight__c', 'Distance__c', 'Freight_Amount__c', 'Pickup_Date__c', 'Expected_Delivery_Date__c',
            'Actual_Delivery_Date__c', 'Status__c', 'Priority__c', 'Vehicle__c', 'Driver__c', 'Latest_Location__c',
            'Is_Delayed__c', 'Is_Billable__c', 'Is_On_Time__c', 'Transit_Days__c'
        ]
    },
    {
        api: 'eLogix_Shipment_Delivery_Attempts',
        label: 'eLogix Shipments with Delivery Attempts',
        description: 'Each delivery attempt with its shipment: outcome, failure reason, attempt number and driver.',
        base: 'Shipment__c',
        sectionLabel: 'Shipment',
        fields: ['Name', 'Customer__c', 'Business_Unit__c', 'Status__c', 'Expected_Delivery_Date__c'],
        join: {
            relationship: 'Deliveries__r',
            object: 'Delivery__c',
            sectionLabel: 'Delivery Attempt',
            fields: ['Name', 'Attempt_Number__c', 'Delivery_Status__c', 'Failure_Reason__c', 'Delivery_Date__c', 'Is_Successful__c', 'Delivered_By__c']
        }
    },
    {
        api: 'eLogix_Shipment_Requests',
        label: 'eLogix Shipment Requests',
        description: 'Shipment requests (the commercial intake) with customer, status, weight and declared value.',
        base: 'Shipment_Request__c',
        sectionLabel: 'Shipment Request',
        fields: [
            'Name', 'CreatedDate', 'Customer__c', 'Business_Unit__c', 'Origin__c', 'Destination__c', 'Status__c',
            'Priority__c', 'Requested_Vehicle_Type__c', 'Total_Weight__c', 'Declared_Value__c', 'Requested_Pickup_Date__c'
        ]
    },
    {
        api: 'eLogix_Quotations',
        label: 'eLogix Quotations',
        description: 'Quotations with their request, customer, status, totals, validity and approval.',
        base: 'Quotation__c',
        sectionLabel: 'Quotation',
        fields: [
            'Name', 'CreatedDate', 'Shipment_Request__c', 'Customer_Name__c', 'Status__c', 'Subtotal__c', 'Discount__c',
            'Tax_Amount__c', 'Total_Amount__c', 'Valid_Until__c', 'Is_Expired__c', 'Approved_By__c', 'Approval_Date__c'
        ]
    },
    {
        api: 'eLogix_Vehicle_Assignments',
        label: 'eLogix Vehicle Assignments',
        description: 'Vehicle and driver assignments (trips) with their shipment, window, status and duration.',
        base: 'Vehicle_Assignment__c',
        sectionLabel: 'Vehicle Assignment',
        fields: [
            'Name', 'CreatedDate', 'Vehicle__c', 'Driver__c', 'Shipment__c', 'Business_Unit__c', 'Assignment_Start__c',
            'Assignment_End__c', 'Status__c', 'Duration_Hours__c'
        ]
    },
    {
        api: 'eLogix_Vehicles',
        label: 'eLogix Vehicles',
        description: 'Vehicles with type, capacity, status, document validity and allocatability.',
        base: 'Vehicle__c',
        sectionLabel: 'Vehicle',
        fields: [
            'Name', 'Vehicle_Number__c', 'Vehicle_Type__c', 'Capacity__c', 'Business_Unit__c', 'Status__c',
            'Registration_Expiry__c', 'Insurance_Expiry__c', 'Document_Status__c', 'Is_Allocatable__c'
        ]
    },
    {
        api: 'eLogix_Drivers',
        label: 'eLogix Drivers',
        description: 'Drivers with status, licence validity and allocatability.',
        base: 'Driver__c',
        sectionLabel: 'Driver',
        fields: ['Name', 'License_Number__c', 'License_Expiry__c', 'License_Status__c', 'Business_Unit__c', 'Status__c', 'Is_Allocatable__c']
    }
];

/* ------------------------------------------------------------------ */
/* Reports (all summary reports in the eLogix Reports folder)          */
/* ------------------------------------------------------------------ */

/**
 * groupBy: [{ field, granularity? }]; columns: detail columns; sum / average: aggregated columns;
 * filters: [{ field, operator, value }] (checkbox values are '1' or '0'; picklists comma-separated).
 */
export const REPORTS = [
    /* ---- Shipment operations ---- */
    {
        api: 'eLogix_Shipments_By_Status',
        name: 'Shipments by Status',
        description: 'Shipment register grouped by status, with freight value.',
        type: 'eLogix_Shipments',
        groupBy: [{ field: 'Status__c' }],
        columns: ['Name', 'Customer__c', 'Origin__c', 'Destination__c', 'Pickup_Date__c', 'Expected_Delivery_Date__c', 'Vehicle__c'],
        sum: ['Freight_Amount__c']
    },
    {
        api: 'eLogix_Active_Shipments',
        name: 'Active Shipments',
        description: 'Confirmed shipments that are not yet delivered, closed or cancelled.',
        type: 'eLogix_Shipments',
        groupBy: [{ field: 'Status__c' }],
        columns: ['Name', 'Customer__c', 'Origin__c', 'Destination__c', 'Expected_Delivery_Date__c', 'Vehicle__c', 'Latest_Location__c'],
        sum: ['Freight_Amount__c'],
        filters: [{ field: 'Status__c', operator: 'equals', value: ACTIVE_SHIPMENT_STATUSES.join(',') }]
    },
    {
        api: 'eLogix_Delayed_Shipments',
        name: 'Delayed Shipments',
        description: 'Open shipments past their expected delivery date (Is_Delayed__c), by customer.',
        type: 'eLogix_Shipments',
        groupBy: [{ field: 'Customer__c' }],
        columns: ['Name', 'Status__c', 'Origin__c', 'Destination__c', 'Expected_Delivery_Date__c', 'Vehicle__c', 'Latest_Location__c'],
        filters: [{ field: 'Is_Delayed__c', operator: 'equals', value: '1' }]
    },
    {
        api: 'eLogix_Monthly_Shipments',
        name: 'Monthly Shipment Trend',
        description: 'Shipments created per month.',
        type: 'eLogix_Shipments',
        groupBy: [{ field: 'CreatedDate', granularity: 'Month' }],
        columns: ['Name', 'Customer__c', 'Status__c'],
        sum: ['Freight_Amount__c']
    },
    {
        api: 'eLogix_Shipments_By_Business_Unit',
        name: 'Shipments by Business Unit',
        description: 'Shipment volume and freight value per business unit.',
        type: 'eLogix_Shipments',
        groupBy: [{ field: 'Business_Unit__c' }],
        columns: ['Name', 'Customer__c', 'Status__c'],
        sum: ['Freight_Amount__c', 'Weight__c']
    },
    {
        api: 'eLogix_Delivered_Freight_By_Month',
        name: 'Delivered Freight Value by Month',
        description: 'Freight value of delivered or closed shipments by delivery month. Not invoiced revenue: invoicing is not implemented yet.',
        type: 'eLogix_Shipments',
        groupBy: [{ field: 'Actual_Delivery_Date__c', granularity: 'Month' }],
        columns: ['Name', 'Customer__c', 'Status__c'],
        sum: ['Freight_Amount__c'],
        filters: [{ field: 'Is_Billable__c', operator: 'equals', value: '1' }]
    },

    /* ---- Delivery performance ---- */
    {
        api: 'eLogix_On_Time_Delivery',
        name: 'On-Time Delivery',
        description: 'Delivered or closed shipments split by whether they arrived on or before the expected date.',
        type: 'eLogix_Shipments',
        groupBy: [{ field: 'Is_On_Time__c' }],
        columns: ['Name', 'Customer__c', 'Expected_Delivery_Date__c', 'Actual_Delivery_Date__c', 'Transit_Days__c'],
        average: ['Transit_Days__c'],
        filters: [{ field: 'Is_Billable__c', operator: 'equals', value: '1' }]
    },
    {
        api: 'eLogix_Transit_Time_By_Month',
        name: 'Average Transit Days by Month',
        description: 'Average pickup-to-delivery days of delivered shipments, by delivery month.',
        type: 'eLogix_Shipments',
        groupBy: [{ field: 'Actual_Delivery_Date__c', granularity: 'Month' }],
        columns: ['Name', 'Origin__c', 'Destination__c', 'Transit_Days__c'],
        average: ['Transit_Days__c'],
        filters: [{ field: 'Is_Billable__c', operator: 'equals', value: '1' }]
    },
    {
        api: 'eLogix_Delivery_Attempts_By_Outcome',
        name: 'Delivery Attempts by Outcome',
        description: 'Delivery attempts grouped by their status.',
        type: 'eLogix_Shipment_Delivery_Attempts',
        groupBy: [{ field: 'Deliveries__r.Delivery_Status__c' }],
        columns: ['Name', 'Customer__c', 'Deliveries__r.Attempt_Number__c', 'Deliveries__r.Delivery_Date__c', 'Deliveries__r.Delivered_By__c']
    },
    {
        api: 'eLogix_Failed_Delivery_Reasons',
        name: 'Failed Delivery Reasons',
        description: 'Failed delivery attempts grouped by failure reason.',
        type: 'eLogix_Shipment_Delivery_Attempts',
        groupBy: [{ field: 'Deliveries__r.Failure_Reason__c' }],
        columns: ['Name', 'Customer__c', 'Deliveries__r.Attempt_Number__c', 'Deliveries__r.Delivered_By__c'],
        filters: [{ field: 'Deliveries__r.Delivery_Status__c', operator: 'equals', value: 'Failed' }]
    },

    /* ---- Fleet ---- */
    {
        api: 'eLogix_Vehicles_By_Status',
        name: 'Vehicles by Status',
        description: 'Fleet availability: vehicles by status.',
        type: 'eLogix_Vehicles',
        groupBy: [{ field: 'Status__c' }],
        columns: ['Vehicle_Number__c', 'Vehicle_Type__c', 'Capacity__c', 'Business_Unit__c', 'Is_Allocatable__c'],
        sum: ['Capacity__c']
    },
    {
        api: 'eLogix_Vehicle_Document_Status',
        name: 'Vehicle Document Status',
        description: 'Vehicles by registration, insurance and fitness document status.',
        type: 'eLogix_Vehicles',
        groupBy: [{ field: 'Document_Status__c' }],
        columns: ['Vehicle_Number__c', 'Status__c', 'Registration_Expiry__c', 'Insurance_Expiry__c']
    },
    {
        api: 'eLogix_Drivers_By_Status',
        name: 'Drivers by Status',
        description: 'Driver availability by status, with licence status.',
        type: 'eLogix_Drivers',
        groupBy: [{ field: 'Status__c' }],
        columns: ['Name', 'License_Number__c', 'License_Expiry__c', 'License_Status__c', 'Is_Allocatable__c']
    },
    {
        api: 'eLogix_Vehicle_Utilization',
        name: 'Vehicle Utilization',
        description: 'Trips and assigned hours per vehicle (planned, active and completed assignments).',
        type: 'eLogix_Vehicle_Assignments',
        groupBy: [{ field: 'Vehicle__c' }],
        columns: ['Name', 'Driver__c', 'Shipment__c', 'Status__c', 'Assignment_Start__c', 'Assignment_End__c'],
        sum: ['Duration_Hours__c'],
        filters: [{ field: 'Status__c', operator: 'notEqual', value: 'Cancelled' }]
    },
    {
        api: 'eLogix_Driver_Assignments',
        name: 'Driver Assignments',
        description: 'Trips and assigned hours per driver (planned, active and completed assignments).',
        type: 'eLogix_Vehicle_Assignments',
        groupBy: [{ field: 'Driver__c' }],
        columns: ['Name', 'Vehicle__c', 'Shipment__c', 'Status__c', 'Assignment_Start__c'],
        sum: ['Duration_Hours__c'],
        filters: [{ field: 'Status__c', operator: 'notEqual', value: 'Cancelled' }]
    },

    /* ---- Sales and quotations ---- */
    {
        api: 'eLogix_Requests_By_Status',
        name: 'Shipment Requests by Status',
        description: 'Commercial intake funnel: shipment requests by status.',
        type: 'eLogix_Shipment_Requests',
        groupBy: [{ field: 'Status__c' }],
        columns: ['Name', 'Customer__c', 'Origin__c', 'Destination__c', 'Requested_Pickup_Date__c', 'Priority__c'],
        sum: ['Declared_Value__c']
    },
    {
        api: 'eLogix_Quotations_By_Status',
        name: 'Quotations by Status',
        description: 'Quotation pipeline: count and total value by status.',
        type: 'eLogix_Quotations',
        groupBy: [{ field: 'Status__c' }],
        columns: ['Name', 'Customer_Name__c', 'Shipment_Request__c', 'Valid_Until__c'],
        sum: ['Total_Amount__c']
    },
    {
        api: 'eLogix_Quotation_Value_By_Month',
        name: 'Quotation Value by Month',
        description: 'Value of quotations created per month.',
        type: 'eLogix_Quotations',
        groupBy: [{ field: 'CreatedDate', granularity: 'Month' }],
        columns: ['Name', 'Customer_Name__c', 'Status__c'],
        sum: ['Total_Amount__c']
    },
    {
        api: 'eLogix_Quotations_Pending_Approval',
        name: 'Quotations Pending Approval',
        description: 'Quotations waiting for a Logistics Manager decision, by customer.',
        type: 'eLogix_Quotations',
        groupBy: [{ field: 'Customer_Name__c' }],
        columns: ['Name', 'Shipment_Request__c', 'Discount__c', 'Valid_Until__c', 'CreatedDate'],
        sum: ['Total_Amount__c'],
        filters: [{ field: 'Status__c', operator: 'equals', value: 'Pending Approval' }]
    }
];

/* ------------------------------------------------------------------ */
/* Dashboards (fixed running user, decision of 2026-11-20)             */
/* ------------------------------------------------------------------ */

/**
 * Components on a 12-column grid: { report, type: Metric | Donut | Column | Bar | Line, header,
 * summary: 'RowCount' | { sum: field } | { average: field }, col, row, colSpan, rowSpan }.
 * Charts group by the report's first grouping.
 */
const metric = (report, header, summary, col, row) => ({ report, type: 'Metric', header, summary, col, row, colSpan: 3, rowSpan: 3 });
const chart = (report, type, header, summary, col, row, colSpan = 6) => ({ report, type, header, summary, col, row, colSpan, rowSpan: 8 });

export const DASHBOARDS = [
    {
        api: 'eLogix_Executive_Overview',
        title: 'eLogix - Executive Operations Dashboard',
        description: 'Shipments, delivery performance, delivered freight value, fleet availability and quotation pipeline.',
        components: [
            metric('eLogix_Shipments_By_Status', 'Total Shipments', 'RowCount', 0, 0),
            metric('eLogix_Active_Shipments', 'Active Shipments', 'RowCount', 3, 0),
            metric('eLogix_Delayed_Shipments', 'Delayed Shipments', 'RowCount', 6, 0),
            metric('eLogix_Delivered_Freight_By_Month', 'Delivered Freight Value', { sum: 'Freight_Amount__c' }, 9, 0),
            chart('eLogix_Shipments_By_Status', 'Donut', 'Shipment Status Distribution', 'RowCount', 0, 3),
            chart('eLogix_Monthly_Shipments', 'Column', 'Monthly Shipment Trend', 'RowCount', 6, 3),
            chart('eLogix_Delivered_Freight_By_Month', 'Line', 'Delivered Freight Value Trend', { sum: 'Freight_Amount__c' }, 0, 11),
            chart('eLogix_On_Time_Delivery', 'Donut', 'On-Time Delivery', 'RowCount', 6, 11),
            chart('eLogix_Vehicles_By_Status', 'Donut', 'Fleet Availability', 'RowCount', 0, 19),
            chart('eLogix_Quotations_By_Status', 'Bar', 'Quotation Pipeline Value', { sum: 'Total_Amount__c' }, 6, 19)
        ]
    },
    {
        api: 'eLogix_Sales_Quotations',
        title: 'eLogix - Sales and Quotations',
        description: 'Shipment request intake, quotation pipeline, quotation value trend and pending approvals.',
        components: [
            metric('eLogix_Requests_By_Status', 'Shipment Requests', 'RowCount', 0, 0),
            metric('eLogix_Quotations_By_Status', 'Quotations', 'RowCount', 3, 0),
            metric('eLogix_Quotations_By_Status', 'Quotation Value', { sum: 'Total_Amount__c' }, 6, 0),
            metric('eLogix_Quotations_Pending_Approval', 'Pending Approval', 'RowCount', 9, 0),
            chart('eLogix_Requests_By_Status', 'Bar', 'Shipment Requests by Status', 'RowCount', 0, 3),
            chart('eLogix_Quotations_By_Status', 'Donut', 'Quotations by Status', 'RowCount', 6, 3),
            chart('eLogix_Quotation_Value_By_Month', 'Column', 'Quotation Value by Month', { sum: 'Total_Amount__c' }, 0, 11),
            chart('eLogix_Quotations_Pending_Approval', 'Bar', 'Pending Approval by Customer', { sum: 'Total_Amount__c' }, 6, 11)
        ]
    },
    {
        api: 'eLogix_Shipment_Operations',
        title: 'eLogix - Shipment Operations',
        description: 'Active and delayed shipments, status distribution, business units and monthly volume.',
        components: [
            metric('eLogix_Active_Shipments', 'Active Shipments', 'RowCount', 0, 0),
            metric('eLogix_Delayed_Shipments', 'Delayed Shipments', 'RowCount', 3, 0),
            metric('eLogix_Active_Shipments', 'Active Freight Value', { sum: 'Freight_Amount__c' }, 6, 0),
            metric('eLogix_Shipments_By_Status', 'Total Shipments', 'RowCount', 9, 0),
            chart('eLogix_Active_Shipments', 'Bar', 'Active Shipments by Status', 'RowCount', 0, 3),
            chart('eLogix_Delayed_Shipments', 'Bar', 'Delayed Shipments by Customer', 'RowCount', 6, 3),
            chart('eLogix_Shipments_By_Business_Unit', 'Column', 'Shipments by Business Unit', 'RowCount', 0, 11),
            chart('eLogix_Monthly_Shipments', 'Line', 'Monthly Shipment Trend', 'RowCount', 6, 11)
        ]
    },
    {
        api: 'eLogix_Fleet_Performance',
        title: 'eLogix - Fleet Performance',
        description: 'Fleet and driver availability, document status and utilization by vehicle and driver.',
        components: [
            metric('eLogix_Vehicles_By_Status', 'Vehicles', 'RowCount', 0, 0),
            metric('eLogix_Drivers_By_Status', 'Drivers', 'RowCount', 3, 0),
            metric('eLogix_Vehicle_Utilization', 'Trips', 'RowCount', 6, 0),
            metric('eLogix_Vehicle_Utilization', 'Assigned Hours', { sum: 'Duration_Hours__c' }, 9, 0),
            chart('eLogix_Vehicles_By_Status', 'Donut', 'Vehicles by Status', 'RowCount', 0, 3, 4),
            chart('eLogix_Drivers_By_Status', 'Donut', 'Drivers by Status', 'RowCount', 4, 3, 4),
            chart('eLogix_Vehicle_Document_Status', 'Donut', 'Vehicle Document Status', 'RowCount', 8, 3, 4),
            chart('eLogix_Vehicle_Utilization', 'Bar', 'Assigned Hours by Vehicle', { sum: 'Duration_Hours__c' }, 0, 11),
            chart('eLogix_Driver_Assignments', 'Bar', 'Trips by Driver', 'RowCount', 6, 11)
        ]
    },
    {
        api: 'eLogix_Delivery_Performance',
        title: 'eLogix - Delivery Performance',
        description: 'On-time delivery, delivery attempt outcomes, failure reasons and transit time.',
        components: [
            metric('eLogix_On_Time_Delivery', 'Delivered Shipments', 'RowCount', 0, 0),
            metric('eLogix_On_Time_Delivery', 'Average Transit Days', { average: 'Transit_Days__c' }, 3, 0),
            metric('eLogix_Delivery_Attempts_By_Outcome', 'Delivery Attempts', 'RowCount', 6, 0),
            metric('eLogix_Failed_Delivery_Reasons', 'Failed Attempts', 'RowCount', 9, 0),
            chart('eLogix_On_Time_Delivery', 'Donut', 'On-Time vs Late', 'RowCount', 0, 3),
            chart('eLogix_Delivery_Attempts_By_Outcome', 'Donut', 'Attempts by Outcome', 'RowCount', 6, 3),
            chart('eLogix_Failed_Delivery_Reasons', 'Bar', 'Failed Delivery Reasons', 'RowCount', 0, 11),
            chart('eLogix_Transit_Time_By_Month', 'Line', 'Average Transit Days by Month', { average: 'Transit_Days__c' }, 6, 11)
        ]
    }
];
