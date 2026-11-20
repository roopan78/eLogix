/**
 * eLogix ERP - permission set model.
 *
 * One permission set per business role (CLAUDE.md section 12). Access strings use the letters
 *   C = Create, R = Read, E = Edit, D = Delete, V = View All, M = Modify All.
 * Objects omitted from a role's matrix get no access.
 *
 * Field-level security is derived, not listed by hand:
 *   - every non-required field on a readable object is readable;
 *   - it is editable when the role can create or edit the object, the field is not a formula or
 *     roll-up, and it is not a PROTECTED field (below) that the role is not entitled to edit.
 *
 * PROTECTED fields are system-derived values (computed freight, stock quantities, approval stamps,
 * idempotency keys). Only the owning Apex service writes them, after its own custom permission
 * check - see docs/SECURITY_DESIGN.md. The Administrator role can edit them for support.
 */

export const ADMIN = 'eLogix_Administrator';
const LOGISTICS_MANAGER = 'eLogix_Logistics_Manager';
const FINANCE = 'eLogix_Finance_Executive';

/** Field -> roles (besides Administrator) that may edit it. Empty list = service-only. */
export const PROTECTED_FIELDS = {
    'Account.Credit_Limit__c': [FINANCE],
    'Account.Credit_Terms_Days__c': [FINANCE],

    'Quotation__c.Rate_Card__c': [],
    'Quotation__c.Base_Freight__c': [],
    'Quotation__c.Weight_Charge__c': [],
    'Quotation__c.Distance_Charge__c': [],
    'Quotation__c.Fuel_Surcharge__c': [],
    'Quotation__c.Insurance_Charge__c': [],
    'Quotation__c.Tax_Percent__c': [],
    'Quotation__c.Version__c': [],
    'Quotation__c.Approved_By__c': [],
    'Quotation__c.Approval_Date__c': [],

    'Shipment__c.Freight_Amount__c': [],
    'Shipment__c.Vehicle__c': [],
    'Shipment__c.Driver__c': [],
    'Shipment__c.Latest_Location__c': [],
    'Shipment__c.Latest_Tracking_Timestamp__c': [],

    // Phase 4: setting it requests a dispatched-allocation correction, which the assignment trigger
    // accepts only with eLogix_Correct_Dispatched_Allocation.
    'Vehicle_Assignment__c.Correction_Reason__c': [LOGISTICS_MANAGER],

    // Phase 5: numbered and linked by the delivery triggers, never by users.
    'Delivery__c.Attempt_Number__c': [],
    'Delivery__c.Attempt_Key__c': [],
    'Proof_of_Delivery__c.Shipment__c': [],

    'Freight_Charge__c.Approved_By__c': [],

    'Inventory__c.Available_Quantity__c': [],
    'Inventory__c.Reserved_Quantity__c': [],
    'Inventory__c.Inventory_Key__c': [],

    'Stock_Movement__c.Quantity_Before__c': [],
    'Stock_Movement__c.Quantity_After__c': [],
    'Stock_Movement__c.Movement_Key__c': [],
    'Stock_Movement__c.Performed_By__c': [],

    'Tracking_Event__c.Event_Key__c': [],
    'Tracking_Event__c.From_Status__c': [],
    'Tracking_Event__c.To_Status__c': [],

    'Proof_of_Delivery__c.Verified_By__c': [LOGISTICS_MANAGER],

    'Invoice__c.Invoice_Key__c': [],
    'Payment__c.Gateway_Transaction_Id__c': [],
    'Payment__c.Idempotency_Key__c': [],

    'Return_Request__c.Approved_By__c': [],
    'Return_Request__c.Approval_Date__c': [],

    'Claim__c.Approved_Amount__c': [FINANCE, LOGISTICS_MANAGER],
    'Claim__c.Settlement_Date__c': [FINANCE, LOGISTICS_MANAGER]
};

const ALL = 'CREDVM';

export const PERMISSION_SETS = [
    {
        api: ADMIN,
        label: 'eLogix Administrator',
        description: 'Full eLogix administration: all objects, all fields and every business custom permission. Pair with the System Administrator profile. Does not include validation bypass.',
        objects: {
            Account: ALL,
            Contact: ALL,
            Business_Unit__c: ALL,
            Shipment_Request__c: ALL,
            Quotation__c: ALL,
            Quotation_Line__c: ALL,
            Shipment__c: ALL,
            Shipment_Item__c: ALL,
            Vehicle__c: ALL,
            Driver__c: ALL,
            Vehicle_Assignment__c: ALL,
            Vehicle_Maintenance__c: ALL,
            Warehouse__c: ALL,
            Inventory__c: ALL,
            Stock_Movement__c: ALL,
            Route__c: ALL,
            Route_Stop__c: ALL,
            Rate_Card__c: ALL,
            Freight_Charge__c: ALL,
            Tracking_Event__c: ALL,
            Delivery__c: ALL,
            Proof_of_Delivery__c: ALL,
            Invoice__c: ALL,
            Invoice_Line__c: ALL,
            Payment__c: ALL,
            Return_Request__c: ALL,
            Claim__c: ALL,
            Integration_Log__c: ALL
        },
        customPermissions: [
            'eLogix_Override_Shipment_Status',
            'eLogix_Cancel_Confirmed_Shipment',
            'eLogix_Approve_Quotation',
            'eLogix_Allocate_Fleet',
            'eLogix_Correct_Dispatched_Allocation',
            'eLogix_Ingest_GPS',
            'eLogix_Adjust_Inventory',
            'eLogix_Approve_Return',
            'eLogix_Settle_Claim',
            'eLogix_Record_Advance_Payment',
            'eLogix_Modify_Paid_Invoice'
        ]
    },
    {
        api: LOGISTICS_MANAGER,
        label: 'eLogix Logistics Manager',
        description: 'Oversees end-to-end operations: sees every operational record, manages requests, quotations, shipments, routes and pricing, and holds the operational approval permissions.',
        objects: {
            Account: 'RV',
            Contact: 'RV',
            Business_Unit__c: 'RV',
            Shipment_Request__c: 'CREV',
            Quotation__c: 'CREV',
            Quotation_Line__c: 'CREDV',
            Shipment__c: 'CREV',
            Shipment_Item__c: 'CREDV',
            Vehicle__c: 'RV',
            Driver__c: 'RV',
            Vehicle_Assignment__c: 'CREV',
            Vehicle_Maintenance__c: 'RV',
            Warehouse__c: 'RV',
            Inventory__c: 'RV',
            Stock_Movement__c: 'RV',
            Route__c: 'CREV',
            Route_Stop__c: 'CREDV',
            Rate_Card__c: 'CREV',
            Freight_Charge__c: 'CREDV',
            Tracking_Event__c: 'CRV',
            Delivery__c: 'CREV',
            Proof_of_Delivery__c: 'CREV',
            Invoice__c: 'RV',
            Invoice_Line__c: 'RV',
            Payment__c: 'RV',
            Return_Request__c: 'CREV',
            Claim__c: 'CREV',
            Integration_Log__c: 'RV'
        },
        customPermissions: [
            'eLogix_Override_Shipment_Status',
            'eLogix_Cancel_Confirmed_Shipment',
            'eLogix_Approve_Quotation',
            'eLogix_Allocate_Fleet',
            'eLogix_Correct_Dispatched_Allocation',
            'eLogix_Approve_Return',
            'eLogix_Settle_Claim'
        ]
    },
    {
        api: 'eLogix_Sales_Executive',
        label: 'eLogix Sales Executive',
        description: 'Manages customers, captures shipment requests and builds quotations. Pricing components are computed by the freight service and are read-only.',
        objects: {
            Account: 'CRE',
            Contact: 'CRED',
            Business_Unit__c: 'R',
            Shipment_Request__c: 'CRE',
            Quotation__c: 'CRE',
            Quotation_Line__c: 'CRED',
            Shipment__c: 'R',
            Shipment_Item__c: 'R',
            Route__c: 'R',
            Route_Stop__c: 'R',
            Rate_Card__c: 'R',
            Freight_Charge__c: 'R',
            Tracking_Event__c: 'R',
            Invoice__c: 'R',
            Return_Request__c: 'R'
        },
        customPermissions: []
    },
    {
        api: 'eLogix_Operations_Executive',
        label: 'eLogix Operations Executive',
        description: 'Runs day-to-day shipment execution: shipments and items, tracking events, deliveries and proof of delivery.',
        objects: {
            Account: 'R',
            Contact: 'R',
            Business_Unit__c: 'R',
            Shipment_Request__c: 'RE',
            Quotation__c: 'R',
            Quotation_Line__c: 'R',
            Shipment__c: 'CRE',
            Shipment_Item__c: 'CRED',
            Vehicle__c: 'R',
            Driver__c: 'R',
            Vehicle_Assignment__c: 'R',
            Warehouse__c: 'R',
            Inventory__c: 'R',
            Stock_Movement__c: 'R',
            Route__c: 'R',
            Route_Stop__c: 'R',
            Rate_Card__c: 'R',
            Freight_Charge__c: 'CRE',
            Tracking_Event__c: 'CR',
            Delivery__c: 'CRE',
            Proof_of_Delivery__c: 'CRE',
            Invoice__c: 'R',
            Return_Request__c: 'RE',
            Claim__c: 'R'
        },
        customPermissions: []
    },
    {
        api: 'eLogix_Fleet_Manager',
        label: 'eLogix Fleet Manager',
        description: 'Maintains vehicles, drivers and maintenance schedules, and allocates fleet to shipments.',
        objects: {
            Account: 'R',
            Business_Unit__c: 'R',
            Shipment__c: 'RV', // Phase 4 (Q13): read-only View All to plan the fleet
            Shipment_Item__c: 'R',
            Vehicle__c: 'CREDV',
            Driver__c: 'CREDV',
            Vehicle_Assignment__c: 'CREV', // Phase 4 audit fix 1: no Delete; release is by cancellation
            Vehicle_Maintenance__c: 'CREDV',
            Route__c: 'R',
            Route_Stop__c: 'R',
            Tracking_Event__c: 'R',
            Delivery__c: 'R'
        },
        customPermissions: ['eLogix_Allocate_Fleet']
    },
    {
        api: 'eLogix_Warehouse_Manager',
        label: 'eLogix Warehouse Manager',
        description: 'Manages warehouses and inventory. Stock quantities change only through stock movements; returns are inspected before restocking.',
        objects: {
            Account: 'R',
            Business_Unit__c: 'R',
            Shipment__c: 'R',
            Shipment_Item__c: 'R',
            Warehouse__c: 'CREV',
            Inventory__c: 'CREV',
            Stock_Movement__c: 'CRV',
            Route__c: 'R',
            Return_Request__c: 'RE'
        },
        customPermissions: ['eLogix_Adjust_Inventory']
    },
    {
        api: FINANCE,
        label: 'eLogix Finance Executive',
        description: 'Owns invoicing, payments, customer credit terms, rate cards and claim settlement.',
        objects: {
            Account: 'RE',
            Contact: 'R',
            Business_Unit__c: 'R',
            Shipment_Request__c: 'R',
            Quotation__c: 'R',
            Quotation_Line__c: 'R',
            Shipment__c: 'R',
            Shipment_Item__c: 'R',
            Warehouse__c: 'R',
            Inventory__c: 'R',
            Route__c: 'R',
            Rate_Card__c: 'CREV',
            Freight_Charge__c: 'R',
            Delivery__c: 'R',
            Proof_of_Delivery__c: 'R',
            Invoice__c: 'CREV',
            Invoice_Line__c: 'CREDV',
            Payment__c: 'CREV',
            Return_Request__c: 'R',
            Claim__c: 'RE'
        },
        customPermissions: ['eLogix_Settle_Claim', 'eLogix_Record_Advance_Payment']
    },
    {
        api: 'eLogix_Customer_Service_Executive',
        label: 'eLogix Customer Service Executive',
        description: 'Answers customer enquiries: reads shipment status and history, raises shipment requests, returns and claims.',
        objects: {
            Account: 'R',
            Contact: 'CRE',
            Business_Unit__c: 'R',
            Shipment_Request__c: 'CRE',
            Quotation__c: 'R',
            Quotation_Line__c: 'R',
            Shipment__c: 'R',
            Shipment_Item__c: 'R',
            Route__c: 'R',
            Tracking_Event__c: 'R',
            Delivery__c: 'R',
            Proof_of_Delivery__c: 'R',
            Invoice__c: 'R',
            Invoice_Line__c: 'R',
            Payment__c: 'R',
            Return_Request__c: 'CRE',
            Claim__c: 'CRE'
        },
        customPermissions: []
    },
    {
        api: 'eLogix_GPS_Integration',
        label: 'eLogix GPS Integration',
        description: 'For the GPS provider integration user (API only): submits GPS pings to the GPS ingestion endpoint. Reads shipments, vehicles and assignments; writes tracking events and integration logs.',
        objects: {
            Shipment__c: 'RV', // the ingestion locks and updates the tracking summary of any shipment on an Active trip
            Vehicle__c: 'R',
            Vehicle_Assignment__c: 'R',
            Tracking_Event__c: 'CR',
            Integration_Log__c: 'CRE'
        },
        customPermissions: ['eLogix_Ingest_GPS'],
        apexClasses: ['GpsPingResource'],
        noApp: true
    },
    {
        api: 'eLogix_Data_Migration',
        label: 'eLogix Data Migration',
        description: 'Temporary assignment for the demo seed script and data migrations: bypasses bypassable eLogix validation rules. Remove after the load.',
        objects: {},
        customPermissions: ['eLogix_Bypass_Validation_Rules'],
        noApp: true
    }
];
