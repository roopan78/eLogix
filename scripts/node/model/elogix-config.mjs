/**
 * eLogix ERP - configuration metadata: custom permissions and custom metadata types.
 *
 * Custom permissions gate sensitive business operations (CLAUDE.md rule 16). Apex services check
 * them through FeatureManagement.checkPermission(); validation rules through $Permission.
 *
 * Custom metadata types hold configurable business rules (CLAUDE.md rule 14). Pricing values are
 * NOT here - they live on Rate_Card__c records so business users can maintain date-effective
 * pricing without a deployment.
 */

/* ------------------------------------------------------------------ */
/* Custom permissions                                                  */
/* ------------------------------------------------------------------ */

export const CUSTOM_PERMISSIONS = [
    {
        api: 'eLogix_Override_Shipment_Status',
        label: 'eLogix: Override Shipment Status',
        description: 'Bypass the shipment status transition policy to correct a record. Every override is still written to tracking history.'
    },
    {
        api: 'eLogix_Cancel_Confirmed_Shipment',
        label: 'eLogix: Cancel Confirmed Shipment',
        description: 'Cancel a shipment after it has been confirmed, readied for dispatch or placed on hold.'
    },
    {
        api: 'eLogix_Approve_Quotation',
        label: 'eLogix: Approve Quotation',
        description: 'Approve quotations whose discount exceeds the configured no-approval threshold.'
    },
    {
        api: 'eLogix_Allocate_Fleet',
        label: 'eLogix: Allocate Fleet',
        description: 'Allocate vehicles and drivers to shipments through the fleet allocation service.'
    },
    {
        api: 'eLogix_Adjust_Inventory',
        label: 'eLogix: Adjust Inventory',
        description: 'Post manual stock adjustments and damage write-offs.'
    },
    {
        api: 'eLogix_Approve_Return',
        label: 'eLogix: Approve Return',
        description: 'Approve or reject return requests. Approval is required before pickup can be scheduled.'
    },
    {
        api: 'eLogix_Settle_Claim',
        label: 'eLogix: Settle Claim',
        description: 'Approve claim amounts and record claim settlements.'
    },
    {
        api: 'eLogix_Record_Advance_Payment',
        label: 'eLogix: Record Advance Payment',
        description: 'Record a payment above the outstanding invoice balance. Also requires the Allow_Advance_Payments setting.'
    },
    {
        api: 'eLogix_Modify_Paid_Invoice',
        label: 'eLogix: Modify Paid Invoice',
        description: 'Edit an invoice after it has been fully paid.'
    },
    {
        api: 'eLogix_Bypass_Validation_Rules',
        label: 'eLogix: Bypass Validation Rules',
        description: 'Bypass bypassable eLogix validation rules during controlled data migration and demo seeding. Assign temporarily only.'
    }
];

/* ------------------------------------------------------------------ */
/* Custom metadata types                                               */
/* ------------------------------------------------------------------ */

const text = (api, length, o = {}) => ({ kind: 'text', api, length, ...o });
const num = (api, precision, scale, o = {}) => ({ kind: 'number', api, precision, scale, ...o });
const bool = (api, o = {}) => ({ kind: 'checkbox', api, ...o });

/** Statuses without spaces, for record developer names. */
const code = (status) => (status ? status.replace(/ /g, '') : 'New');

/**
 * One allowed shipment status transition. A blank From_Status means "allowed initial status on
 * creation". Shipments start before confirmation so that the at-least-one-item rule is always
 * enforced on the move to Confirmed.
 */
function transition(from, to, o = {}) {
    return {
        name: `${code(from)}_to_${code(to)}`,
        label: from ? `${from} to ${to}` : `New to ${to}`,
        values: {
            From_Status__c: from ?? null,
            To_Status__c: to,
            Tracking_Event_Type__c: o.event ?? to,
            Required_Permission__c: o.permission ?? null,
            Is_Active__c: true,
            Description__c: o.description ?? null
        }
    };
}

const CANCEL = 'eLogix_Cancel_Confirmed_Shipment';

const TRANSITIONS = [
    // Creation
    transition(null, 'Draft', { event: 'Created', description: 'Shipment captured without a request.' }),
    transition(null, 'Requested', { event: 'Created', description: 'Shipment created from a submitted shipment request.' }),
    transition(null, 'Quoted', { event: 'Created', description: 'Shipment created from an accepted quotation.' }),

    // Main lifecycle
    transition('Draft', 'Requested'),
    transition('Requested', 'Quoted'),
    transition('Quoted', 'Confirmed', { description: 'Requires at least one shipment item.' }),
    transition('Confirmed', 'Ready for Dispatch', { description: 'Requires vehicle and driver allocation.' }),
    transition('Ready for Dispatch', 'Dispatched', { description: 'Requires inventory to be available for warehouse-sourced items.' }),
    transition('Dispatched', 'In Transit'),
    transition('In Transit', 'Out for Delivery'),
    transition('Out for Delivery', 'Delivered'),
    transition('Delivered', 'Closed'),

    // Cancellation - free before confirmation, permission-gated after
    transition('Draft', 'Cancelled'),
    transition('Requested', 'Cancelled'),
    transition('Quoted', 'Cancelled'),
    transition('Confirmed', 'Cancelled', { permission: CANCEL }),
    transition('Ready for Dispatch', 'Cancelled', { permission: CANCEL }),
    transition('On Hold', 'Cancelled', { permission: CANCEL }),

    // Hold and resume
    transition('Confirmed', 'On Hold'),
    transition('Ready for Dispatch', 'On Hold'),
    transition('Dispatched', 'On Hold'),
    transition('In Transit', 'On Hold'),
    transition('Delayed', 'On Hold'),
    transition('Failed Delivery', 'On Hold'),
    transition('On Hold', 'Confirmed'),
    transition('On Hold', 'Ready for Dispatch'),
    transition('On Hold', 'In Transit'),

    // Delay
    transition('Dispatched', 'Delayed'),
    transition('In Transit', 'Delayed'),
    transition('Out for Delivery', 'Delayed'),
    transition('Delayed', 'In Transit'),
    transition('Delayed', 'Out for Delivery'),

    // Delivery failure and re-attempt
    transition('Out for Delivery', 'Failed Delivery'),
    transition('Failed Delivery', 'Out for Delivery', { description: 'Re-attempt delivery.' }),
    transition('Failed Delivery', 'Return Initiated'),

    // Damage and loss
    transition('In Transit', 'Damaged'),
    transition('Out for Delivery', 'Damaged'),
    transition('Delayed', 'Damaged'),
    transition('In Transit', 'Lost'),
    transition('Out for Delivery', 'Lost'),
    transition('Delayed', 'Lost'),
    transition('Damaged', 'Return Initiated'),
    transition('Damaged', 'Closed', { description: 'Closed after claim settlement.' }),
    transition('Lost', 'Closed', { description: 'Closed after claim settlement.' }),

    // Reverse logistics
    transition('Delivered', 'Return Initiated'),
    transition('Return Initiated', 'Closed')
];

function setting(name, label, values) {
    return {
        name,
        label,
        values: {
            Text_Value__c: values.text ?? null,
            Number_Value__c: values.number ?? null,
            Boolean_Value__c: values.bool === true,
            Description__c: values.description
        }
    };
}

export const METADATA_TYPES = [
    {
        api: 'Shipment_Status_Transition__mdt',
        label: 'Shipment Status Transition',
        pluralLabel: 'Shipment Status Transitions',
        description: 'Allowed shipment status transitions read by ShipmentStatusPolicy. Any change not listed here is rejected unless the user holds eLogix_Override_Shipment_Status.',
        fields: [
            text('From_Status__c', 40, { helpText: 'Blank means the To Status is an allowed initial status when the shipment is created.' }),
            text('To_Status__c', 40, { required: true }),
            text('Tracking_Event_Type__c', 40, { helpText: 'Event type written to Tracking_Event__c when this transition happens.' }),
            text('Required_Permission__c', 80, { helpText: 'API name of a custom permission the user must hold to perform this transition. Blank means no extra permission.' }),
            bool('Is_Active__c', { default: true }),
            text('Description__c', 255)
        ],
        records: TRANSITIONS
    },
    {
        api: 'eLogix_Setting__mdt',
        label: 'eLogix Setting',
        pluralLabel: 'eLogix Settings',
        description: 'Named configuration values for eLogix business rules. Read through a single settings service so that no business threshold is hardcoded in Apex.',
        fields: [
            text('Text_Value__c', 255),
            num('Number_Value__c', 16, 4),
            bool('Boolean_Value__c', { default: false }),
            text('Description__c', 255)
        ],
        records: [
            setting('Default_Tax_Percent', 'Default Tax Percent', {
                number: 12,
                description: 'GST percentage applied to freight when no rate card or customer override applies.'
            }),
            setting('Quotation_Validity_Days', 'Quotation Validity Days', {
                number: 15,
                description: 'Days a quotation stays valid after it is issued.'
            }),
            setting('Max_Discount_Percent_No_Approval', 'Max Discount Percent No Approval', {
                number: 10,
                description: 'Quotations discounted above this percentage of gross freight require approval.'
            }),
            setting('Default_Credit_Terms_Days', 'Default Credit Terms Days', {
                number: 30,
                description: 'Invoice payment terms used when the customer has no credit terms of their own.'
            }),
            setting('Allow_Advance_Payments', 'Allow Advance Payments', {
                bool: false,
                description: 'When true, users with eLogix_Record_Advance_Payment may record payments above the outstanding balance.'
            }),
            setting('Delay_Grace_Hours', 'Delay Grace Hours', {
                number: 6,
                description: 'Hours past the expected delivery date before SLA monitoring flags a shipment as Delayed.'
            }),
            setting('Default_Billing_Milestone', 'Default Billing Milestone', {
                text: 'On Delivery',
                description: 'Billing milestone used for automatically generated invoices.'
            })
        ]
    }
];
