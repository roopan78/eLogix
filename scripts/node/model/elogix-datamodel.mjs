/**
 * eLogix ERP - canonical data model definition.
 *
 * This is the single compact description of every custom object, field and relationship in the
 * platform. `scripts/node/scaffold-metadata.mjs` renders it into Metadata API source under
 * force-app/main/default/. See docs/DATA_MODEL.md for the design rationale.
 *
 * Conventions
 *   - Transactional objects use an AutoNumber Name and mirror the business key named in CLAUDE.md
 *     section 4 as a Formula(Text) = Name field (e.g. Shipment_Number__c).
 *   - Master data objects use a Text Name plus a unique External ID code, which is what makes the
 *     demo seed script idempotent without hardcoded record IDs.
 *   - Master-Detail is used where the child is an owned line item or an immutable audit record;
 *     Lookup everywhere else.
 *   - Formulas never reference other formula fields, to keep deployment order independent.
 */

/* ------------------------------------------------------------------ */
/* Field shorthand helpers                                             */
/* ------------------------------------------------------------------ */

const text = (api, length, o = {}) => ({ kind: 'text', api, length, ...o });
const area = (api, o = {}) => ({ kind: 'textarea', api, ...o });
const long = (api, length, visibleLines, o = {}) => ({ kind: 'longtextarea', api, length, visibleLines, ...o });
const num = (api, precision, scale, o = {}) => ({ kind: 'number', api, precision, scale, ...o });
const curr = (api, precision, scale, o = {}) => ({ kind: 'currency', api, precision, scale, ...o });
const pct = (api, o = {}) => ({ kind: 'percent', api, precision: 5, scale: 2, ...o });
const date = (api, o = {}) => ({ kind: 'date', api, ...o });
const dt = (api, o = {}) => ({ kind: 'datetime', api, ...o });
const bool = (api, o = {}) => ({ kind: 'checkbox', api, ...o });
const phone = (api, o = {}) => ({ kind: 'phone', api, ...o });
const email = (api, o = {}) => ({ kind: 'email', api, ...o });

/** Picklist bound to a global value set (reused vocabulary). */
const gvs = (api, globalValueSet, o = {}) => ({ kind: 'picklist', api, globalValueSet, ...o });
/** Object-local picklist. Mark one value `{ name, default: true }`. */
const pick = (api, values, o = {}) => ({ kind: 'picklist', api, values, ...o });

const lookup = (api, referenceTo, relationshipName, o = {}) => ({
    kind: 'lookup',
    api,
    referenceTo,
    relationshipName,
    relationshipLabel: o.relationshipLabel ?? relationshipName.replace(/_/g, ' '),
    ...o
});
const master = (api, referenceTo, relationshipName, o = {}) => ({
    kind: 'masterdetail',
    api,
    referenceTo,
    relationshipName,
    relationshipLabel: o.relationshipLabel ?? relationshipName.replace(/_/g, ' '),
    ...o
});

const formula = (api, type, expr, o = {}) => ({ kind: 'formula', api, type, formula: expr, ...o });
const rollup = (api, foreignKey, operation, o = {}) => ({ kind: 'summary', api, foreignKey, operation, ...o });

/* ------------------------------------------------------------------ */
/* Global value sets - shared status and type vocabularies             */
/* ------------------------------------------------------------------ */

export const GLOBAL_VALUE_SETS = [
    {
        api: 'eLogix_Shipment_Status',
        masterLabel: 'eLogix Shipment Status',
        description: 'Controlled shipment lifecycle per CLAUDE.md section 6. Transitions are governed by Shipment_Status_Transition__mdt.',
        values: [
            { name: 'Draft', default: true },
            'Requested',
            'Quoted',
            'Confirmed',
            'Ready for Dispatch',
            'Dispatched',
            'In Transit',
            'Out for Delivery',
            'Delivered',
            'Closed',
            'On Hold',
            'Delayed',
            'Failed Delivery',
            'Damaged',
            'Lost',
            'Cancelled',
            'Return Initiated'
        ]
    },
    {
        api: 'eLogix_Priority',
        masterLabel: 'eLogix Priority',
        values: ['Low', { name: 'Standard', default: true }, 'High', 'Critical']
    },
    {
        api: 'eLogix_Region',
        masterLabel: 'eLogix Region',
        values: ['North', { name: 'South', default: true }, 'East', 'West', 'Central']
    },
    {
        api: 'eLogix_Vehicle_Type',
        masterLabel: 'eLogix Vehicle Type',
        description: 'Shared by Vehicle__c and Rate_Card__c so freight rates always key off the same vocabulary.',
        values: [
            'Mini Truck',
            { name: 'LCV', default: true },
            'Container Truck',
            'Trailer',
            'Refrigerated Truck',
            'Tanker'
        ]
    },
    {
        api: 'eLogix_Package_Type',
        masterLabel: 'eLogix Package Type',
        values: [{ name: 'Box', default: true }, 'Pallet', 'Crate', 'Drum', 'Bag', 'Loose']
    },
    {
        api: 'eLogix_Movement_Type',
        masterLabel: 'eLogix Stock Movement Type',
        values: [
            { name: 'Inbound Receipt', default: true },
            'Outbound Dispatch',
            'Transfer In',
            'Transfer Out',
            'Reservation',
            'Reservation Release',
            'Return Restock',
            'Adjustment',
            'Damage Write Off'
        ]
    },
    {
        api: 'eLogix_Charge_Type',
        masterLabel: 'eLogix Charge Type',
        values: [
            { name: 'Base Freight', default: true },
            'Weight Charge',
            'Distance Charge',
            'Fuel Surcharge',
            'Insurance',
            'Loading',
            'Unloading',
            'Detention',
            'Waiting',
            'Toll',
            'Handling',
            'Packaging',
            'Escort',
            'Discount',
            'Other'
        ]
    },
    {
        api: 'eLogix_Payment_Method',
        masterLabel: 'eLogix Payment Method',
        values: [{ name: 'Bank Transfer', default: true }, 'UPI', 'Cheque', 'Cash', 'Credit Card', 'Adjustment']
    },
    {
        api: 'eLogix_Tracking_Event_Type',
        masterLabel: 'eLogix Tracking Event Type',
        description: 'Every shipment status has a same-named event type so status transitions map 1:1; the remaining values are operational events that do not change status.',
        values: [
            { name: 'Created', default: true },
            'Requested',
            'Quoted',
            'Confirmed',
            'Ready for Dispatch',
            'Dispatched',
            'Picked Up',
            'In Transit',
            'Hub Arrival',
            'Hub Departure',
            'Location Update',
            'Out for Delivery',
            'Delivered',
            'Failed Delivery',
            'On Hold',
            'Delayed',
            'Damaged',
            'Lost',
            'Cancelled',
            'Return Initiated',
            'Closed',
            'Exception'
        ]
    },
    {
        api: 'eLogix_Event_Source',
        masterLabel: 'eLogix Event Source',
        values: [
            { name: 'Manual', default: true },
            'Apex Service',
            'Flow Automation',
            'GPS Integration',
            'Mobile App',
            'Partner API'
        ]
    }
];

/* ------------------------------------------------------------------ */
/* Objects                                                             */
/* ------------------------------------------------------------------ */

export const OBJECTS = [
    /* --- A. Customer management: extensions to standard objects --- */
    {
        api: 'Account',
        standard: true,
        fields: [
            text('Customer_Code__c', 30, { unique: true, externalId: true, helpText: 'Unique business key used by the demo seed script instead of record IDs.' }),
            pick('Customer_Classification__c', [{ name: 'Standard', default: true }, 'Key Account', 'Occasional', 'Prospect']),
            bool('Is_Active_Customer__c', { default: true, helpText: 'Inactive customers cannot raise new shipment requests.' }),
            curr('Credit_Limit__c', 16, 2),
            num('Credit_Terms_Days__c', 3, 0, { helpText: 'Payment terms in days, used to derive invoice due dates.' }),
            text('GSTIN__c', 20),
            lookup('Business_Unit__c', 'Business_Unit__c', 'Customers', { relationshipLabel: 'Customers' })
        ]
    },
    {
        api: 'Contact',
        standard: true,
        fields: [
            pick('Contact_Role__c', [
                { name: 'Primary', default: true },
                'Billing',
                'Operations',
                'Escalation',
                'Logistics Coordinator'
            ]),
            bool('Is_Primary_Contact__c', { default: false })
        ]
    },

    /* --- B. Business unit management --- */
    {
        api: 'Business_Unit__c',
        label: 'Business Unit',
        pluralLabel: 'Business Units',
        sharingModel: 'Read',
        description: 'Regional operating unit. Supports multiple business units within one org.',
        nameField: { label: 'Business Unit Name' },
        fields: [
            text('Business_Unit_Code__c', 20, { required: true, unique: true, externalId: true }),
            gvs('Region__c', 'eLogix_Region'),
            bool('Is_Active__c', { default: true }),
            text('Head_Office_Location__c', 120),
            area('Description__c')
        ]
    },

    /* --- C. Shipment request and quotation --- */
    {
        api: 'Shipment_Request__c',
        label: 'Shipment Request',
        pluralLabel: 'Shipment Requests',
        sharingModel: 'Private',
        description: 'Customer demand capture. Converts into a Quotation and then a Shipment.',
        nameField: { label: 'Request Name', displayFormat: 'SR-{00000}' },
        fields: [
            formula('Request_Number__c', 'Text', 'Name', { helpText: 'Business key mirrored from the AutoNumber Name field.' }),
            lookup('Customer__c', 'Account', 'Shipment_Requests', { required: true, relationshipLabel: 'Shipment Requests' }),
            lookup('Business_Unit__c', 'Business_Unit__c', 'Shipment_Requests', { required: true, relationshipLabel: 'Shipment Requests' }),
            lookup('Route__c', 'Route__c', 'Shipment_Requests', { relationshipLabel: 'Shipment Requests' }),
            text('Origin__c', 120, { required: true }),
            text('Destination__c', 120, { required: true }),
            date('Requested_Pickup_Date__c', { required: true }),
            date('Expected_Delivery_Date__c'),
            num('Total_Weight__c', 12, 2, { helpText: 'Total consignment weight in kilograms.' }),
            curr('Declared_Value__c', 16, 2),
            gvs('Requested_Vehicle_Type__c', 'eLogix_Vehicle_Type'),
            gvs('Priority__c', 'eLogix_Priority'),
            pick('Status__c', [
                { name: 'Draft', default: true },
                'Submitted',
                'Under Review',
                'Quoted',
                'Approved',
                'Converted',
                'Rejected',
                'Cancelled'
            ]),
            area('Cargo_Description__c'),
            long('Special_Instructions__c', 2000, 4),
            area('Rejection_Reason__c')
        ]
    },
    {
        api: 'Quotation__c',
        label: 'Quotation',
        pluralLabel: 'Quotations',
        sharingModel: 'Private',
        description: 'Priced offer against a shipment request. Charge components are snapshotted from the applicable rate card; totals are derived.',
        nameField: { label: 'Quotation Name', displayFormat: 'QT-{00000}' },
        fields: [
            formula('Quotation_Number__c', 'Text', 'Name'),
            lookup('Shipment_Request__c', 'Shipment_Request__c', 'Quotations', { required: true, relationshipLabel: 'Quotations' }),
            lookup('Rate_Card__c', 'Rate_Card__c', 'Quotations', { relationshipLabel: 'Quotations' }),
            formula('Customer_Name__c', 'Text', 'Shipment_Request__r.Customer__r.Name'),
            curr('Base_Freight__c', 16, 2, { helpText: 'Snapshot of the rate card base freight at quotation time.' }),
            curr('Weight_Charge__c', 16, 2),
            curr('Distance_Charge__c', 16, 2),
            curr('Fuel_Surcharge__c', 16, 2),
            curr('Insurance_Charge__c', 16, 2),
            curr('Discount__c', 16, 2),
            pct('Tax_Percent__c'),
            rollup('Line_Total__c', 'Quotation_Line__c.Quotation__c', 'sum', {
                summarizedField: 'Quotation_Line__c.Amount__c',
                label: 'Additional Charges'
            }),
            // Phase 3 (decision Q14): only lines marked Is_Taxable__c enter the tax base.
            rollup('Taxable_Line_Total__c', 'Quotation_Line__c.Quotation__c', 'sum', {
                summarizedField: 'Quotation_Line__c.Amount__c',
                label: 'Taxable Additional Charges',
                filters: [{ field: 'Quotation_Line__c.Is_Taxable__c', operation: 'equals', value: 'true' }],
                helpText: 'Sum of quotation lines marked taxable. Only these lines are included in the tax base.'
            }),
            formula('Subtotal__c', 'Currency', 'Base_Freight__c + Weight_Charge__c + Distance_Charge__c + Fuel_Surcharge__c + Insurance_Charge__c + Line_Total__c - Discount__c'),
            // Percent fields evaluate as fractions in formulas (12% -> 0.12), so no division by 100.
            // Tax base (decision Q14) = freight components + taxable lines - discount, never below zero.
            formula('Tax_Amount__c', 'Currency', 'MAX(0, Base_Freight__c + Weight_Charge__c + Distance_Charge__c + Fuel_Surcharge__c + Insurance_Charge__c + Taxable_Line_Total__c - Discount__c) * Tax_Percent__c'),
            formula('Total_Amount__c', 'Currency', '(Base_Freight__c + Weight_Charge__c + Distance_Charge__c + Fuel_Surcharge__c + Insurance_Charge__c + Line_Total__c - Discount__c) + MAX(0, Base_Freight__c + Weight_Charge__c + Distance_Charge__c + Fuel_Surcharge__c + Insurance_Charge__c + Taxable_Line_Total__c - Discount__c) * Tax_Percent__c'),
            date('Valid_Until__c'),
            pick('Status__c', [
                { name: 'Draft', default: true },
                'Pending Approval',
                'Approved',
                'Sent',
                'Accepted',
                'Rejected',
                'Expired',
                'Superseded'
            ]),
            num('Version__c', 3, 0, { default: 1 }),
            lookup('Approved_By__c', 'User', 'eLogix_Approved_Quotations', { relationshipLabel: 'eLogix Approved Quotations' }),
            dt('Approval_Date__c'),
            formula('Is_Expired__c', 'Checkbox', 'AND(NOT(ISBLANK(Valid_Until__c)), Valid_Until__c < TODAY())'),
            long('Notes__c', 2000, 4)
        ]
    },
    {
        api: 'Quotation_Line__c',
        label: 'Quotation Line',
        pluralLabel: 'Quotation Lines',
        sharingModel: 'ControlledByParent',
        description: 'Itemised additional charge on a quotation.',
        nameField: { label: 'Quotation Line Name', displayFormat: 'QTL-{000000}' },
        fields: [
            master('Quotation__c', 'Quotation__c', 'Quotation_Lines', { relationshipLabel: 'Quotation Lines' }),
            gvs('Charge_Type__c', 'eLogix_Charge_Type', { required: true }),
            text('Description__c', 255),
            num('Quantity__c', 10, 2, { default: 1 }),
            curr('Unit_Price__c', 16, 2),
            curr('Amount__c', 16, 2, { required: true }),
            bool('Is_Taxable__c', { default: true }),
            num('Sort_Order__c', 3, 0)
        ]
    },

    /* --- D. Shipment management --- */
    {
        api: 'Shipment__c',
        label: 'Shipment',
        pluralLabel: 'Shipments',
        sharingModel: 'Private',
        enableHistory: true,
        enableActivities: true,
        description: 'Central transactional object. Status transitions are governed by ShipmentStatusPolicy and always emit a Tracking_Event__c.',
        nameField: { label: 'Shipment Name', displayFormat: 'SHP-{00000}' },
        fields: [
            formula('Shipment_Number__c', 'Text', 'Name'),
            lookup('Shipment_Request__c', 'Shipment_Request__c', 'Shipments', { relationshipLabel: 'Shipments' }),
            lookup('Quotation__c', 'Quotation__c', 'Shipments', { relationshipLabel: 'Shipments' }),
            lookup('Customer__c', 'Account', 'Shipments', { required: true, relationshipLabel: 'Shipments' }),
            lookup('Business_Unit__c', 'Business_Unit__c', 'Shipments', { required: true, relationshipLabel: 'Shipments' }),
            lookup('Route__c', 'Route__c', 'Shipments', { relationshipLabel: 'Shipments' }),
            text('Origin__c', 120, { required: true }),
            text('Destination__c', 120, { required: true }),
            num('Weight__c', 12, 2, { required: true, helpText: 'Chargeable weight in kilograms. Must be greater than zero.' }),
            num('Distance__c', 10, 2, { required: true, helpText: 'Route distance in kilometres. Must be greater than zero.' }),
            curr('Freight_Amount__c', 16, 2, { trackHistory: true }),
            date('Pickup_Date__c'),
            date('Expected_Delivery_Date__c'),
            date('Actual_Delivery_Date__c'),
            gvs('Status__c', 'eLogix_Shipment_Status', { trackHistory: true }),
            gvs('Priority__c', 'eLogix_Priority'),
            lookup('Vehicle__c', 'Vehicle__c', 'Shipments', { trackHistory: true, relationshipLabel: 'Shipments' }),
            lookup('Driver__c', 'Driver__c', 'Shipments', { trackHistory: true, relationshipLabel: 'Shipments' }),
            text('Latest_Location__c', 255),
            dt('Latest_Tracking_Timestamp__c'),
            rollup('Item_Count__c', 'Shipment_Item__c.Shipment__c', 'count', {
                helpText: 'A shipment must have at least one item before it can be confirmed.'
            }),
            rollup('Total_Item_Weight__c', 'Shipment_Item__c.Shipment__c', 'sum', {
                summarizedField: 'Shipment_Item__c.Weight__c'
            }),
            rollup('Total_Declared_Value__c', 'Shipment_Item__c.Shipment__c', 'sum', {
                summarizedField: 'Shipment_Item__c.Declared_Value__c'
            }),
            rollup('Additional_Charges__c', 'Freight_Charge__c.Shipment__c', 'sum', {
                summarizedField: 'Freight_Charge__c.Amount__c'
            }),
            formula('Is_Delayed__c', 'Checkbox', 'AND(NOT(ISBLANK(Expected_Delivery_Date__c)), NOT(ISPICKVAL(Status__c, "Delivered")), NOT(ISPICKVAL(Status__c, "Closed")), NOT(ISPICKVAL(Status__c, "Cancelled")), Expected_Delivery_Date__c < TODAY())'),
            formula('Is_Billable__c', 'Checkbox', 'OR(ISPICKVAL(Status__c, "Delivered"), ISPICKVAL(Status__c, "Closed"))'),
            formula('Transit_Days__c', 'Number', 'IF(OR(ISBLANK(Actual_Delivery_Date__c), ISBLANK(Pickup_Date__c)), null, Actual_Delivery_Date__c - Pickup_Date__c)', { scale: 0 }),
            area('Hold_Reason__c'),
            area('Cancellation_Reason__c'),
            long('Special_Instructions__c', 2000, 4)
        ]
    },
    {
        api: 'Shipment_Item__c',
        label: 'Shipment Item',
        pluralLabel: 'Shipment Items',
        sharingModel: 'ControlledByParent',
        description: 'Consignment line on a shipment.',
        nameField: { label: 'Shipment Item Name', displayFormat: 'SHI-{000000}' },
        fields: [
            master('Shipment__c', 'Shipment__c', 'Shipment_Items', { relationshipLabel: 'Shipment Items' }),
            text('Item_Name__c', 120, { required: true }),
            text('SKU__c', 50),
            num('Quantity__c', 10, 2, { required: true }),
            num('Weight__c', 12, 2),
            curr('Declared_Value__c', 16, 2),
            gvs('Package_Type__c', 'eLogix_Package_Type'),
            lookup('Inventory__c', 'Inventory__c', 'Shipment_Items', { relationshipLabel: 'Shipment Items' }),
            lookup('Warehouse__c', 'Warehouse__c', 'Shipment_Items', { relationshipLabel: 'Shipment Items' }),
            text('Remarks__c', 255)
        ]
    },

    /* --- E. Fleet management --- */
    {
        api: 'Vehicle__c',
        label: 'Vehicle',
        pluralLabel: 'Vehicles',
        sharingModel: 'Read',
        description: 'Fleet asset. Allocation eligibility is derived from status plus document validity.',
        nameField: { label: 'Vehicle Name' },
        fields: [
            text('Vehicle_Number__c', 20, { required: true, unique: true, externalId: true, helpText: 'Registration number, e.g. TN-01-AB-1234.' }),
            gvs('Vehicle_Type__c', 'eLogix_Vehicle_Type', { required: true }),
            num('Capacity__c', 10, 2, { required: true, helpText: 'Maximum carrying capacity in kilograms.' }),
            lookup('Business_Unit__c', 'Business_Unit__c', 'Vehicles', { required: true, relationshipLabel: 'Vehicles' }),
            date('Registration_Expiry__c'),
            date('Insurance_Expiry__c'),
            date('Fitness_Expiry__c'),
            pick('Status__c', [
                { name: 'Available', default: true },
                'Assigned',
                'In Transit',
                'Under Maintenance',
                'Inactive'
            ]),
            num('Current_Odometer__c', 10, 0),
            formula('Is_Active__c', 'Checkbox', 'NOT(ISPICKVAL(Status__c, "Inactive"))'),
            // Phase 4 (decision Q4): a fitness certificate counts only when its expiry is filled in.
            formula('Is_Documents_Valid__c', 'Checkbox', 'AND(NOT(ISBLANK(Registration_Expiry__c)), Registration_Expiry__c >= TODAY(), NOT(ISBLANK(Insurance_Expiry__c)), Insurance_Expiry__c >= TODAY(), OR(ISBLANK(Fitness_Expiry__c), Fitness_Expiry__c >= TODAY()))'),
            // Phase 4 (decision Q2): status is administrative availability only; allocation does not change it.
            // Indicative for today: FleetAllocationService also checks documents through the assignment window,
            // maintenance and overlapping bookings.
            formula('Is_Allocatable__c', 'Checkbox', 'AND(NOT(ISPICKVAL(Status__c, "Under Maintenance")), NOT(ISPICKVAL(Status__c, "Inactive")), AND(NOT(ISBLANK(Registration_Expiry__c)), Registration_Expiry__c >= TODAY(), NOT(ISBLANK(Insurance_Expiry__c)), Insurance_Expiry__c >= TODAY(), OR(ISBLANK(Fitness_Expiry__c), Fitness_Expiry__c >= TODAY())))', {
                helpText: 'Indicative for today. Allocation also checks documents through the assignment window, maintenance and overlapping bookings.'
            }),
            // Phase 4 (decision Q15): registration, insurance and (when filled in) fitness, as one status.
            formula('Document_Status__c', 'Text', 'IF(OR(ISBLANK(Registration_Expiry__c), ISBLANK(Insurance_Expiry__c)), "Missing", IF(OR(Registration_Expiry__c < TODAY(), Insurance_Expiry__c < TODAY(), AND(NOT(ISBLANK(Fitness_Expiry__c)), Fitness_Expiry__c < TODAY())), "Expired", IF(OR(Registration_Expiry__c <= TODAY() + $CustomMetadata.eLogix_Setting__mdt.Document_Expiry_Warning_Days.Number_Value__c, Insurance_Expiry__c <= TODAY() + $CustomMetadata.eLogix_Setting__mdt.Document_Expiry_Warning_Days.Number_Value__c, AND(NOT(ISBLANK(Fitness_Expiry__c)), Fitness_Expiry__c <= TODAY() + $CustomMetadata.eLogix_Setting__mdt.Document_Expiry_Warning_Days.Number_Value__c)), "Expiring Soon", "Valid")))', {
                helpText: 'Missing, Expired, Expiring Soon (within the eLogix setting Document_Expiry_Warning_Days) or Valid, across registration, insurance and fitness.'
            }),
            rollup('Open_Maintenance_Count__c', 'Vehicle_Maintenance__c.Vehicle__c', 'count', {
                filters: [{ field: 'Vehicle_Maintenance__c.Status__c', operation: 'notEqual', value: 'Completed, Cancelled' }],
                helpText: 'Scheduled or in-progress maintenance. Vehicles with open maintenance cannot be allocated.'
            })
        ]
    },
    {
        api: 'Driver__c',
        label: 'Driver',
        pluralLabel: 'Drivers',
        sharingModel: 'Read',
        description: 'Fleet operator. Allocation eligibility is derived from status plus licence validity.',
        nameField: { label: 'Driver Name' },
        fields: [
            text('License_Number__c', 30, { required: true, unique: true, externalId: true }),
            date('License_Expiry__c', { required: true }),
            phone('Phone__c'),
            email('Email__c'),
            lookup('Business_Unit__c', 'Business_Unit__c', 'Drivers', { required: true, relationshipLabel: 'Drivers' }),
            pick('Status__c', [{ name: 'Available', default: true }, 'On Duty', 'On Leave', 'Inactive']),
            date('Date_of_Joining__c'),
            lookup('User__c', 'User', 'eLogix_Driver_Records', { relationshipLabel: 'eLogix Driver Records' }),
            formula('Is_License_Valid__c', 'Checkbox', 'AND(NOT(ISBLANK(License_Expiry__c)), License_Expiry__c >= TODAY())'),
            // Phase 4 (decision Q2): status is administrative availability only; allocation does not change it.
            formula('Is_Allocatable__c', 'Checkbox', 'AND(NOT(ISPICKVAL(Status__c, "On Leave")), NOT(ISPICKVAL(Status__c, "Inactive")), NOT(ISBLANK(License_Expiry__c)), License_Expiry__c >= TODAY())', {
                helpText: 'Indicative for today. Allocation also checks the licence through the assignment window and overlapping bookings.'
            }),
            // Phase 4 (decision Q15): Missing, Expired, Expiring Soon (within Document_Expiry_Warning_Days) or Valid.
            formula('License_Status__c', 'Text', 'IF(ISBLANK(License_Expiry__c), "Missing", IF(License_Expiry__c < TODAY(), "Expired", IF(License_Expiry__c <= TODAY() + $CustomMetadata.eLogix_Setting__mdt.Document_Expiry_Warning_Days.Number_Value__c, "Expiring Soon", "Valid")))', {
                helpText: 'Expiring Soon means the licence expires within the eLogix setting Document_Expiry_Warning_Days.'
            })
        ]
    },
    {
        api: 'Vehicle_Assignment__c',
        label: 'Vehicle Assignment',
        pluralLabel: 'Vehicle Assignments',
        sharingModel: 'ReadWrite',
        description: 'Allocation of a vehicle and driver to a shipment for a time window. Overlap detection lives in VehicleAvailabilityService.',
        nameField: { label: 'Assignment Name', displayFormat: 'VA-{000000}' },
        fields: [
            lookup('Vehicle__c', 'Vehicle__c', 'Vehicle_Assignments', { required: true, relationshipLabel: 'Vehicle Assignments' }),
            lookup('Driver__c', 'Driver__c', 'Vehicle_Assignments', { required: true, relationshipLabel: 'Vehicle Assignments' }),
            lookup('Shipment__c', 'Shipment__c', 'Vehicle_Assignments', { relationshipLabel: 'Vehicle Assignments' }),
            lookup('Business_Unit__c', 'Business_Unit__c', 'Vehicle_Assignments', { relationshipLabel: 'Vehicle Assignments' }),
            dt('Assignment_Start__c', { required: true }),
            dt('Assignment_End__c'),
            pick('Status__c', [{ name: 'Planned', default: true }, 'Active', 'Completed', 'Cancelled']),
            formula('Is_Open__c', 'Checkbox', 'OR(ISPICKVAL(Status__c, "Planned"), ISPICKVAL(Status__c, "Active"))', {
                helpText: 'Open assignments are the ones that can conflict with a new allocation.'
            }),
            formula('Duration_Hours__c', 'Number', 'IF(OR(ISBLANK(Assignment_Start__c), ISBLANK(Assignment_End__c)), null, (Assignment_End__c - Assignment_Start__c) * 24)', { scale: 2 }),
            text('Remarks__c', 255),
            text('Correction_Reason__c', 255, {
                helpText: 'Reason for the latest correction of a dispatched allocation. Setting it requests a correction: allowed only while the shipment is On Hold, with the Correct Dispatched Allocation permission. Each correction is also written to tracking history.'
            })
        ]
    },
    {
        api: 'Vehicle_Maintenance__c',
        label: 'Vehicle Maintenance',
        pluralLabel: 'Vehicle Maintenance',
        sharingModel: 'ControlledByParent',
        description: 'Service history and scheduled maintenance for a vehicle.',
        nameField: { label: 'Maintenance Name', displayFormat: 'VM-{000000}' },
        fields: [
            master('Vehicle__c', 'Vehicle__c', 'Vehicle_Maintenances', { relationshipLabel: 'Vehicle Maintenance' }),
            pick('Maintenance_Type__c', [
                { name: 'Preventive', default: true },
                'Corrective',
                'Breakdown',
                'Inspection',
                'Tyre Replacement',
                'Oil Change'
            ], { required: true }),
            date('Scheduled_Date__c', { required: true }),
            date('Completion_Date__c'),
            curr('Cost__c', 14, 2),
            pick('Status__c', [{ name: 'Scheduled', default: true }, 'In Progress', 'Completed', 'Cancelled']),
            text('Service_Provider__c', 120),
            num('Odometer_Reading__c', 10, 0),
            area('Remarks__c')
        ]
    },

    /* --- F. Warehouse and inventory --- */
    {
        api: 'Warehouse__c',
        label: 'Warehouse',
        pluralLabel: 'Warehouses',
        sharingModel: 'Read',
        nameField: { label: 'Warehouse Name' },
        fields: [
            text('Warehouse_Code__c', 20, { required: true, unique: true, externalId: true }),
            text('Location__c', 255, { required: true }),
            num('Capacity__c', 12, 2, { helpText: 'Storage capacity in cubic metres.' }),
            pick('Status__c', [{ name: 'Active', default: true }, 'Inactive', 'Full', 'Under Maintenance']),
            lookup('Business_Unit__c', 'Business_Unit__c', 'Warehouses', { required: true, relationshipLabel: 'Warehouses' }),
            gvs('Region__c', 'eLogix_Region'),
            lookup('Manager__c', 'User', 'eLogix_Managed_Warehouses', { relationshipLabel: 'eLogix Managed Warehouses' }),
            rollup('SKU_Count__c', 'Inventory__c.Warehouse__c', 'count'),
            rollup('Total_Available_Quantity__c', 'Inventory__c.Warehouse__c', 'sum', {
                summarizedField: 'Inventory__c.Available_Quantity__c'
            }),
            rollup('Total_Reserved_Quantity__c', 'Inventory__c.Warehouse__c', 'sum', {
                summarizedField: 'Inventory__c.Reserved_Quantity__c'
            })
        ]
    },
    {
        api: 'Inventory__c',
        label: 'Inventory',
        pluralLabel: 'Inventory',
        sharingModel: 'ControlledByParent',
        description: 'Stock position for one SKU in one warehouse. Quantities change only through Stock_Movement__c records.',
        nameField: { label: 'Inventory Name' },
        fields: [
            master('Warehouse__c', 'Warehouse__c', 'Inventories', { relationshipLabel: 'Inventory' }),
            text('SKU__c', 50, { required: true }),
            text('Product_Name__c', 120, { required: true }),
            text('Inventory_Key__c', 80, { unique: true, externalId: true, helpText: 'Warehouse code and SKU composite key. Keeps stock seeding idempotent.' }),
            num('Available_Quantity__c', 12, 2, { default: 0 }),
            num('Reserved_Quantity__c', 12, 2, { default: 0 }),
            num('Reorder_Level__c', 12, 2, { default: 0 }),
            pick('Unit_of_Measure__c', [{ name: 'EA', default: true }, 'KG', 'L', 'BOX', 'PALLET']),
            curr('Unit_Value__c', 14, 2),
            formula('Net_Available_Quantity__c', 'Number', 'Available_Quantity__c - Reserved_Quantity__c', { scale: 2 }),
            formula('Is_Below_Reorder__c', 'Checkbox', '(Available_Quantity__c - Reserved_Quantity__c) <= Reorder_Level__c'),
            formula('Stock_Value__c', 'Currency', 'Available_Quantity__c * Unit_Value__c'),
            rollup('Last_Movement_Date__c', 'Stock_Movement__c.Inventory__c', 'max', {
                summarizedField: 'Stock_Movement__c.Movement_Date__c'
            })
        ]
    },
    {
        api: 'Stock_Movement__c',
        label: 'Stock Movement',
        pluralLabel: 'Stock Movements',
        sharingModel: 'ControlledByParent',
        description: 'Immutable audit trail for every stock change. Never update inventory quantities without one.',
        nameField: { label: 'Movement Name', displayFormat: 'SM-{000000}' },
        fields: [
            master('Inventory__c', 'Inventory__c', 'Stock_Movements', { relationshipLabel: 'Stock Movements' }),
            lookup('Warehouse__c', 'Warehouse__c', 'Stock_Movements', { relationshipLabel: 'Stock Movements' }),
            gvs('Movement_Type__c', 'eLogix_Movement_Type', { required: true }),
            num('Quantity__c', 12, 2, { required: true }),
            lookup('Reference_Shipment__c', 'Shipment__c', 'Stock_Movements', { relationshipLabel: 'Stock Movements' }),
            lookup('Reference_Return__c', 'Return_Request__c', 'Stock_Movements', { relationshipLabel: 'Stock Movements' }),
            dt('Movement_Date__c', { required: true }),
            num('Quantity_Before__c', 12, 2),
            num('Quantity_After__c', 12, 2),
            text('Movement_Key__c', 80, { unique: true, externalId: true, helpText: 'Idempotency key. Prevents the same stock transaction being applied twice.' }),
            lookup('Performed_By__c', 'User', 'eLogix_Stock_Movements', { relationshipLabel: 'eLogix Stock Movements' }),
            text('Remarks__c', 255)
        ]
    },

    /* --- G. Route and pricing --- */
    {
        api: 'Route__c',
        label: 'Route',
        pluralLabel: 'Routes',
        sharingModel: 'Read',
        nameField: { label: 'Route Name' },
        fields: [
            text('Route_Code__c', 20, { required: true, unique: true, externalId: true }),
            text('Origin__c', 120, { required: true }),
            text('Destination__c', 120, { required: true }),
            num('Distance__c', 10, 2, { required: true, helpText: 'Total route distance in kilometres.' }),
            num('Estimated_Transit_Hours__c', 6, 2),
            pick('Status__c', [{ name: 'Active', default: true }, 'Inactive', 'Seasonal']),
            gvs('Region__c', 'eLogix_Region'),
            curr('Toll_Charges__c', 12, 2),
            rollup('Stop_Count__c', 'Route_Stop__c.Route__c', 'count')
        ]
    },
    {
        api: 'Route_Stop__c',
        label: 'Route Stop',
        pluralLabel: 'Route Stops',
        sharingModel: 'ControlledByParent',
        nameField: { label: 'Route Stop Name', displayFormat: 'RS-{000000}' },
        fields: [
            master('Route__c', 'Route__c', 'Route_Stops', { relationshipLabel: 'Route Stops' }),
            text('Stop_Name__c', 120, { required: true }),
            num('Sequence__c', 3, 0, { required: true }),
            num('Distance_From_Origin__c', 10, 2),
            num('Estimated_Arrival_Hours__c', 6, 2),
            pick('Stop_Type__c', [{ name: 'Checkpoint', default: true }, 'Pickup', 'Drop', 'Hub', 'Fuel Stop']),
            lookup('Warehouse__c', 'Warehouse__c', 'Route_Stops', { relationshipLabel: 'Route Stops' })
        ]
    },
    {
        api: 'Rate_Card__c',
        label: 'Rate Card',
        pluralLabel: 'Rate Cards',
        sharingModel: 'Read',
        description: 'Date-aware freight pricing configuration. FreightCalculationService selects the applicable card; no pricing is hardcoded in Apex.',
        nameField: { label: 'Rate Card Name' },
        fields: [
            formula('Rate_Card_Name__c', 'Text', 'Name'),
            text('Rate_Card_Code__c', 30, { required: true, unique: true, externalId: true }),
            gvs('Vehicle_Type__c', 'eLogix_Vehicle_Type', { required: true }),
            lookup('Business_Unit__c', 'Business_Unit__c', 'Rate_Cards', { relationshipLabel: 'Rate Cards' }),
            gvs('Region__c', 'eLogix_Region'),
            curr('Base_Freight__c', 14, 2, { required: true }),
            curr('Rate_Per_KG__c', 10, 2, { required: true }),
            curr('Rate_Per_KM__c', 10, 2, { required: true }),
            pct('Fuel_Surcharge_Percent__c'),
            pct('Insurance_Percent__c'),
            curr('Minimum_Freight__c', 14, 2),
            date('Effective_From__c', { required: true }),
            date('Effective_To__c'),
            bool('Is_Active__c', { default: true }),
            num('Selection_Priority__c', 3, 0, { default: 10, helpText: 'Lower value wins when several cards are effective for the same vehicle type.' }),
            formula('Is_Currently_Effective__c', 'Checkbox', 'AND(Is_Active__c, Effective_From__c <= TODAY(), OR(ISBLANK(Effective_To__c), Effective_To__c >= TODAY()))')
        ]
    },
    {
        api: 'Freight_Charge__c',
        label: 'Freight Charge',
        pluralLabel: 'Freight Charges',
        sharingModel: 'ControlledByParent',
        description: 'Additional charge applied to a shipment after booking.',
        nameField: { label: 'Freight Charge Name', displayFormat: 'FC-{000000}' },
        fields: [
            master('Shipment__c', 'Shipment__c', 'Freight_Charges', { relationshipLabel: 'Freight Charges' }),
            gvs('Charge_Type__c', 'eLogix_Charge_Type', { required: true }),
            text('Description__c', 255),
            curr('Amount__c', 14, 2, { required: true }),
            bool('Is_Billable__c', { default: true }),
            bool('Is_Taxable__c', { default: true }),
            lookup('Approved_By__c', 'User', 'eLogix_Approved_Freight_Charges', { relationshipLabel: 'eLogix Approved Freight Charges' })
        ]
    },

    /* --- H. Tracking and delivery --- */
    {
        api: 'Tracking_Event__c',
        label: 'Tracking Event',
        pluralLabel: 'Tracking Events',
        sharingModel: 'ControlledByParent',
        description: 'Immutable shipment history. Every meaningful status change creates one of these.',
        nameField: { label: 'Tracking Event Name', displayFormat: 'TRK-{000000}' },
        fields: [
            master('Shipment__c', 'Shipment__c', 'Tracking_Events', { relationshipLabel: 'Tracking Events' }),
            gvs('Event_Type__c', 'eLogix_Tracking_Event_Type', { required: true }),
            text('Location__c', 255),
            dt('Event_Timestamp__c', { required: true }),
            gvs('Source__c', 'eLogix_Event_Source'),
            text('From_Status__c', 60),
            text('To_Status__c', 60),
            num('Latitude__c', 10, 7),
            num('Longitude__c', 10, 7),
            text('Event_Key__c', 80, { unique: true, externalId: true, helpText: 'Idempotency key. Stops duplicate GPS pings creating duplicate history.' }),
            area('Remarks__c')
        ]
    },
    {
        api: 'Delivery__c',
        label: 'Delivery',
        pluralLabel: 'Deliveries',
        sharingModel: 'ControlledByParent',
        description: 'A delivery attempt against a shipment. Multiple attempts are tracked by Attempt_Number__c.',
        nameField: { label: 'Delivery Name', displayFormat: 'DEL-{000000}' },
        fields: [
            master('Shipment__c', 'Shipment__c', 'Deliveries', { relationshipLabel: 'Deliveries' }),
            text('Receiver_Name__c', 120),
            phone('Receiver_Phone__c'),
            dt('Delivery_Date__c'),
            pick('Delivery_Status__c', [
                { name: 'Scheduled', default: true },
                'Out for Delivery',
                'Delivered',
                'Partially Delivered',
                'Failed',
                'Rescheduled',
                'Returned'
            ]),
            pick('Failure_Reason__c', [
                'Consignee Unavailable',
                'Address Incorrect',
                'Refused by Consignee',
                'Payment Not Ready',
                'Damaged Goods',
                'Access Restricted',
                'Other'
            ]),
            num('Attempt_Number__c', 2, 0, { default: 1 }),
            text('Attempt_Key__c', 80, {
                unique: true,
                externalId: true,
                helpText: 'Shipment Id and attempt number, set by the system. The unique index makes a duplicate attempt number impossible, even under concurrency.'
            }),
            lookup('Delivered_By__c', 'Driver__c', 'Deliveries', { relationshipLabel: 'Deliveries' }),
            formula('Is_Successful__c', 'Checkbox', 'ISPICKVAL(Delivery_Status__c, "Delivered")'),
            area('Failure_Notes__c')
        ]
    },
    {
        api: 'Proof_of_Delivery__c',
        label: 'Proof of Delivery',
        pluralLabel: 'Proofs of Delivery',
        sharingModel: 'ControlledByParent',
        description: 'Delivery evidence. Uploaded files are attached as Salesforce Files on this record.',
        nameField: { label: 'POD Name', displayFormat: 'POD-{000000}' },
        fields: [
            master('Delivery__c', 'Delivery__c', 'Proofs_of_Delivery', { relationshipLabel: 'Proofs of Delivery' }),
            lookup('Shipment__c', 'Shipment__c', 'Proofs_of_Delivery', { relationshipLabel: 'Proofs of Delivery' }),
            text('Receiver_Name__c', 120, { required: true }),
            text('Signature_Reference__c', 255, { helpText: 'ContentDocument reference or external signature capture id.' }),
            dt('Received_Date__c'),
            bool('Has_Exception__c', { default: false }),
            area('Exception_Notes__c'),
            lookup('Verified_By__c', 'User', 'eLogix_Verified_PODs', { relationshipLabel: 'eLogix Verified PODs' }),
            long('Delivery_Notes__c', 2000, 4)
        ]
    },

    /* --- I. Finance and billing --- */
    {
        api: 'Invoice__c',
        label: 'Invoice',
        pluralLabel: 'Invoices',
        sharingModel: 'Private',
        enableHistory: true,
        description: 'Customer invoice for a shipment and billing milestone. Invoice_Key__c enforces one invoice per shipment per milestone.',
        nameField: { label: 'Invoice Name', displayFormat: 'INV-{00000}' },
        fields: [
            formula('Invoice_Number__c', 'Text', 'Name'),
            lookup('Shipment__c', 'Shipment__c', 'Invoices', { required: true, relationshipLabel: 'Invoices' }),
            lookup('Customer__c', 'Account', 'Invoices', { required: true, relationshipLabel: 'Invoices' }),
            lookup('Business_Unit__c', 'Business_Unit__c', 'Invoices', { relationshipLabel: 'Invoices' }),
            pick('Billing_Milestone__c', [
                'Advance',
                'On Dispatch',
                { name: 'On Delivery', default: true },
                'Final',
                'Supplementary'
            ], { required: true }),
            text('Invoice_Key__c', 80, {
                unique: true,
                externalId: true,
                helpText: 'Shipment and billing milestone composite key. Declarative duplicate invoice prevention.'
            }),
            date('Invoice_Date__c', { required: true }),
            date('Due_Date__c'),
            num('Payment_Terms_Days__c', 3, 0),
            rollup('Subtotal__c', 'Invoice_Line__c.Invoice__c', 'sum', { summarizedField: 'Invoice_Line__c.Amount__c' }),
            rollup('Tax__c', 'Invoice_Line__c.Invoice__c', 'sum', { summarizedField: 'Invoice_Line__c.Tax_Amount__c' }),
            // Roll-up summary fields cannot be history-tracked, so Status__c carries the audit here.
            rollup('Paid_Amount__c', 'Payment__c.Invoice__c', 'sum', {
                summarizedField: 'Payment__c.Amount__c',
                filters: [{ field: 'Payment__c.Status__c', operation: 'equals', value: 'Completed' }]
            }),
            formula('Total_Amount__c', 'Currency', 'Subtotal__c + Tax__c'),
            formula('Balance_Amount__c', 'Currency', 'Subtotal__c + Tax__c - Paid_Amount__c'),
            pick('Status__c', [
                { name: 'Draft', default: true },
                'Issued',
                'Partially Paid',
                'Paid',
                'Overdue',
                'Cancelled',
                'Written Off'
            ], { trackHistory: true }),
            formula('Is_Overdue__c', 'Checkbox', 'AND(NOT(ISBLANK(Due_Date__c)), Due_Date__c < TODAY(), (Subtotal__c + Tax__c - Paid_Amount__c) > 0)'),
            long('Notes__c', 2000, 4)
        ]
    },
    {
        api: 'Invoice_Line__c',
        label: 'Invoice Line',
        pluralLabel: 'Invoice Lines',
        sharingModel: 'ControlledByParent',
        nameField: { label: 'Invoice Line Name', displayFormat: 'INL-{000000}' },
        fields: [
            master('Invoice__c', 'Invoice__c', 'Invoice_Lines', { relationshipLabel: 'Invoice Lines' }),
            gvs('Charge_Type__c', 'eLogix_Charge_Type', { required: true }),
            text('Description__c', 255),
            num('Quantity__c', 10, 2, { default: 1 }),
            curr('Unit_Price__c', 14, 2),
            curr('Amount__c', 14, 2, { required: true }),
            pct('Tax_Percent__c'),
            curr('Tax_Amount__c', 14, 2),
            lookup('Freight_Charge__c', 'Freight_Charge__c', 'Invoice_Lines', { relationshipLabel: 'Invoice Lines' }),
            formula('Line_Total__c', 'Currency', 'Amount__c + Tax_Amount__c')
        ]
    },
    {
        api: 'Payment__c',
        label: 'Payment',
        pluralLabel: 'Payments',
        sharingModel: 'ControlledByParent',
        description: 'Payment received against an invoice. Only Completed payments roll up into Invoice__c.Paid_Amount__c.',
        nameField: { label: 'Payment Name', displayFormat: 'PAY-{000000}' },
        fields: [
            master('Invoice__c', 'Invoice__c', 'Payments', { relationshipLabel: 'Payments' }),
            text('Payment_Reference__c', 50, { required: true, unique: true, externalId: true }),
            date('Payment_Date__c', { required: true }),
            curr('Amount__c', 14, 2, { required: true }),
            gvs('Payment_Method__c', 'eLogix_Payment_Method', { required: true }),
            pick('Status__c', [{ name: 'Pending', default: true }, 'Completed', 'Failed', 'Refunded', 'Reversed']),
            text('Gateway_Transaction_Id__c', 100),
            text('Idempotency_Key__c', 80, { unique: true, externalId: true, helpText: 'Prevents a gateway callback being applied twice.' }),
            lookup('Received_By__c', 'User', 'eLogix_Received_Payments', { relationshipLabel: 'eLogix Received Payments' }),
            text('Remarks__c', 255)
        ]
    },

    /* --- J. Reverse logistics --- */
    {
        api: 'Return_Request__c',
        label: 'Return Request',
        pluralLabel: 'Return Requests',
        sharingModel: 'Private',
        description: 'Reverse logistics request against an original shipment. Approval precedes pickup; inspection precedes resolution.',
        nameField: { label: 'Return Name', displayFormat: 'RET-{00000}' },
        fields: [
            formula('Return_Number__c', 'Text', 'Name'),
            lookup('Original_Shipment__c', 'Shipment__c', 'Return_Requests', { required: true, relationshipLabel: 'Return Requests' }),
            lookup('Return_Shipment__c', 'Shipment__c', 'Reverse_Return_Requests', { relationshipLabel: 'Reverse Return Requests', helpText: 'The reverse leg shipment created to collect the goods.' }),
            lookup('Customer__c', 'Account', 'Return_Requests', { required: true, relationshipLabel: 'Return Requests' }),
            lookup('Business_Unit__c', 'Business_Unit__c', 'Return_Requests', { relationshipLabel: 'Return Requests' }),
            lookup('Warehouse__c', 'Warehouse__c', 'Return_Requests', { relationshipLabel: 'Return Requests', helpText: 'Restock destination once inspection passes.' }),
            pick('Return_Reason__c', [
                'Damaged in Transit',
                'Wrong Item',
                'Quality Issue',
                'Customer Refused',
                'Excess Quantity',
                'Order Cancelled',
                'Other'
            ], { required: true }),
            pick('Return_Type__c', [{ name: 'Full Return', default: true }, 'Partial Return', 'Replacement', 'Repair'], { required: true }),
            area('Pickup_Address__c', { required: true }),
            date('Requested_Pickup_Date__c'),
            pick('Status__c', [
                { name: 'Draft', default: true },
                'Submitted',
                'Pending Approval',
                'Approved',
                'Rejected',
                'Pickup Scheduled',
                'In Transit',
                'Received',
                'Under Inspection',
                'Inspection Passed',
                'Inspection Failed',
                'Restocked',
                'Closed',
                'Cancelled'
            ]),
            lookup('Approved_By__c', 'User', 'eLogix_Approved_Returns', { relationshipLabel: 'eLogix Approved Returns' }),
            dt('Approval_Date__c'),
            area('Rejection_Reason__c'),
            dt('Inspection_Completed_Date__c'),
            long('Inspection_Notes__c', 2000, 4)
        ]
    },
    {
        api: 'Claim__c',
        label: 'Claim',
        pluralLabel: 'Claims',
        sharingModel: 'Private',
        description: 'Financial claim raised for damage, loss or service failure.',
        nameField: { label: 'Claim Name', displayFormat: 'CLM-{00000}' },
        fields: [
            lookup('Return_Request__c', 'Return_Request__c', 'Claims', { relationshipLabel: 'Claims' }),
            lookup('Shipment__c', 'Shipment__c', 'Claims', { required: true, relationshipLabel: 'Claims' }),
            lookup('Customer__c', 'Account', 'Claims', { relationshipLabel: 'Claims' }),
            pick('Claim_Type__c', ['Damage', 'Loss', 'Shortage', 'Delay', 'Service Failure', 'Other'], { required: true }),
            curr('Claim_Amount__c', 14, 2, { required: true }),
            date('Claim_Date__c', { required: true }),
            curr('Approved_Amount__c', 14, 2),
            pick('Resolution__c', [
                { name: 'Pending', default: true },
                'Full Settlement',
                'Partial Settlement',
                'Rejected',
                'Insurance Claim',
                'Credit Note Issued'
            ]),
            pick('Status__c', [
                { name: 'Draft', default: true },
                'Submitted',
                'Under Investigation',
                'Pending Approval',
                'Approved',
                'Rejected',
                'Settled',
                'Closed'
            ]),
            date('Settlement_Date__c'),
            lookup('Assigned_To__c', 'User', 'eLogix_Assigned_Claims', { relationshipLabel: 'eLogix Assigned Claims' }),
            long('Claim_Notes__c', 2000, 4)
        ]
    },

    /* --- Integration logging (CLAUDE.md section 11) --- */
    {
        api: 'Integration_Log__c',
        label: 'Integration Log',
        pluralLabel: 'Integration Logs',
        sharingModel: 'ReadWrite',
        description: 'Request and response audit for every external callout. Payloads are scrubbed of sensitive data before logging.',
        nameField: { label: 'Log Name', displayFormat: 'ILOG-{000000}' },
        fields: [
            text('Correlation_Id__c', 80, { externalId: true, helpText: 'Groups all log rows belonging to one logical transaction.' }),
            text('Integration_Name__c', 80, { required: true }),
            pick('Direction__c', [{ name: 'Outbound', default: true }, 'Inbound']),
            text('Endpoint__c', 255),
            pick('HTTP_Method__c', [{ name: 'POST', default: true }, 'GET', 'PUT', 'PATCH', 'DELETE']),
            long('Request_Payload__c', 5000, 10),
            long('Response_Payload__c', 5000, 10),
            num('Status_Code__c', 4, 0),
            pick('Status__c', [{ name: 'Success', default: true }, 'Failed', 'Retrying', 'Dead Letter', 'Skipped']),
            pick('Error_Category__c', [
                { name: 'None', default: true },
                'Timeout',
                'Authentication',
                'Validation',
                'Rate Limit',
                'Server Error',
                'Client Error',
                'Serialization',
                'Unknown'
            ]),
            long('Error_Message__c', 2000, 4),
            num('Retry_Count__c', 3, 0, { default: 0 }),
            text('Idempotency_Key__c', 80, { unique: true, externalId: true }),
            num('Duration_Ms__c', 9, 0),
            text('Related_Record_Id__c', 18),
            dt('Log_Timestamp__c', { required: true })
        ]
    }
];

/** Map of object API name -> definition, for lookups by the other model files. */
export const OBJECTS_BY_API = new Map(OBJECTS.map((o) => [o.api, o]));
