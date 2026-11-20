/**
 * eLogix ERP - experience-layer metadata: object tabs, default list views and the Lightning app.
 *
 * Tab motifs are taken verbatim from the Salesforce CLI's own motif table
 * (@salesforce/plugin-sobject, `sf schema generate tab`); an unknown motif fails deployment.
 *
 * Owned line-item objects (Quotation_Line__c, Shipment_Item__c, Route_Stop__c, Freight_Charge__c,
 * Invoice_Line__c) get list views but no tab - they are reached through their parent's related list.
 *
 * `files: true` adds the Salesforce Files related list (delivery evidence, claim photos, invoices).
 */

/** Object API name -> { tab motif (optional), All list view columns (after NAME) }. */
export const EXPERIENCE = {
    Business_Unit__c: {
        tab: 'Custom24: Building',
        listColumns: ['Business_Unit_Code__c', 'Region__c', 'Head_Office_Location__c', 'Is_Active__c']
    },
    Shipment_Request__c: {
        tab: 'Custom18: Form',
        listColumns: ['Customer__c', 'Origin__c', 'Destination__c', 'Requested_Pickup_Date__c', 'Total_Weight__c', 'Priority__c', 'Status__c']
    },
    Quotation__c: {
        tab: 'Custom90: Scales',
        listColumns: ['Shipment_Request__c', 'Customer_Name__c', 'Total_Amount__c', 'Valid_Until__c', 'Status__c']
    },
    Quotation_Line__c: { listColumns: ['Quotation__c', 'Charge_Type__c', 'Description__c', 'Amount__c'] },
    Shipment__c: {
        files: true,
        tab: 'Custom13: Box',
        listColumns: ['Customer__c', 'Origin__c', 'Destination__c', 'Pickup_Date__c', 'Expected_Delivery_Date__c', 'Status__c', 'Priority__c', 'Vehicle__c']
    },
    Shipment_Item__c: { listColumns: ['Shipment__c', 'Item_Name__c', 'SKU__c', 'Quantity__c', 'Weight__c'] },
    Vehicle__c: {
        tab: 'Custom98: Truck',
        listColumns: ['Vehicle_Number__c', 'Vehicle_Type__c', 'Capacity__c', 'Status__c', 'Business_Unit__c', 'Insurance_Expiry__c', 'Document_Status__c'],
        // Phase 4 (decision Q15): expired and expiring-soon documents stay distinguishable.
        listViews: [
            {
                name: 'Documents_Expired',
                label: 'Documents Expired',
                columns: ['Vehicle_Number__c', 'Status__c', 'Registration_Expiry__c', 'Insurance_Expiry__c', 'Fitness_Expiry__c', 'Business_Unit__c'],
                filters: [{ field: 'Document_Status__c', operation: 'equals', value: 'Expired' }]
            },
            {
                name: 'Documents_Expiring_Soon',
                label: 'Documents Expiring Soon',
                columns: ['Vehicle_Number__c', 'Status__c', 'Registration_Expiry__c', 'Insurance_Expiry__c', 'Fitness_Expiry__c', 'Business_Unit__c'],
                filters: [{ field: 'Document_Status__c', operation: 'equals', value: 'Expiring Soon' }]
            },
            {
                name: 'Documents_Missing',
                label: 'Documents Missing',
                columns: ['Vehicle_Number__c', 'Status__c', 'Registration_Expiry__c', 'Insurance_Expiry__c', 'Business_Unit__c'],
                filters: [{ field: 'Document_Status__c', operation: 'equals', value: 'Missing' }]
            }
        ]
    },
    Driver__c: {
        tab: 'Custom15: People',
        listColumns: ['License_Number__c', 'License_Expiry__c', 'Phone__c', 'Status__c', 'Business_Unit__c', 'License_Status__c'],
        // Phase 4 (decision Q15).
        listViews: [
            {
                name: 'Licences_Expired',
                label: 'Licences Expired',
                columns: ['License_Number__c', 'License_Expiry__c', 'Status__c', 'Phone__c', 'Business_Unit__c'],
                filters: [{ field: 'License_Status__c', operation: 'equals', value: 'Expired' }]
            },
            {
                name: 'Licences_Expiring_Soon',
                label: 'Licences Expiring Soon',
                columns: ['License_Number__c', 'License_Expiry__c', 'Status__c', 'Phone__c', 'Business_Unit__c'],
                filters: [{ field: 'License_Status__c', operation: 'equals', value: 'Expiring Soon' }]
            }
        ]
    },
    Vehicle_Assignment__c: {
        tab: 'Custom76: Keys',
        listColumns: ['Vehicle__c', 'Driver__c', 'Shipment__c', 'Assignment_Start__c', 'Assignment_End__c', 'Status__c']
    },
    Vehicle_Maintenance__c: {
        tab: 'Custom19: Wrench',
        listColumns: ['Vehicle__c', 'Maintenance_Type__c', 'Scheduled_Date__c', 'Completion_Date__c', 'Status__c', 'Cost__c']
    },
    Warehouse__c: {
        tab: 'Custom32: Factory',
        listColumns: ['Warehouse_Code__c', 'Location__c', 'Status__c', 'Business_Unit__c', 'SKU_Count__c']
    },
    Inventory__c: {
        tab: 'Custom57: Building Block',
        listColumns: ['Warehouse__c', 'SKU__c', 'Product_Name__c', 'Available_Quantity__c', 'Reserved_Quantity__c', 'Reorder_Level__c']
    },
    Stock_Movement__c: {
        tab: 'Custom67: Gears',
        listColumns: ['Inventory__c', 'Movement_Type__c', 'Quantity__c', 'Movement_Date__c', 'Reference_Shipment__c']
    },
    Route__c: {
        tab: 'Custom78: Map',
        listColumns: ['Route_Code__c', 'Origin__c', 'Destination__c', 'Distance__c', 'Estimated_Transit_Hours__c', 'Status__c']
    },
    Route_Stop__c: { listColumns: ['Route__c', 'Sequence__c', 'Stop_Name__c', 'Stop_Type__c'] },
    Rate_Card__c: {
        tab: 'Custom45: Ticket',
        listColumns: ['Rate_Card_Code__c', 'Vehicle_Type__c', 'Base_Freight__c', 'Rate_Per_KG__c', 'Rate_Per_KM__c', 'Effective_From__c', 'Effective_To__c', 'Is_Active__c']
    },
    Freight_Charge__c: { listColumns: ['Shipment__c', 'Charge_Type__c', 'Description__c', 'Amount__c'] },
    Tracking_Event__c: {
        tab: 'Custom30: Radar dish',
        listColumns: ['Shipment__c', 'Event_Type__c', 'Location__c', 'Event_Timestamp__c', 'Source__c']
    },
    Delivery__c: {
        files: true,
        tab: 'Custom73: Highway Sign',
        listColumns: ['Shipment__c', 'Delivery_Status__c', 'Receiver_Name__c', 'Delivery_Date__c', 'Attempt_Number__c']
    },
    Proof_of_Delivery__c: {
        files: true,
        tab: 'Custom46: Stamp',
        listColumns: ['Delivery__c', 'Shipment__c', 'Receiver_Name__c', 'Received_Date__c']
    },
    Invoice__c: {
        files: true,
        tab: 'Custom23: Envelope',
        listColumns: ['Customer__c', 'Shipment__c', 'Invoice_Date__c', 'Due_Date__c', 'Total_Amount__c', 'Balance_Amount__c', 'Status__c']
    },
    Invoice_Line__c: { listColumns: ['Invoice__c', 'Charge_Type__c', 'Amount__c', 'Tax_Amount__c'] },
    Payment__c: {
        tab: 'Custom41: Cash',
        listColumns: ['Invoice__c', 'Payment_Reference__c', 'Payment_Date__c', 'Amount__c', 'Payment_Method__c', 'Status__c']
    },
    Return_Request__c: {
        files: true,
        tab: 'Custom64: Compass',
        listColumns: ['Original_Shipment__c', 'Customer__c', 'Return_Reason__c', 'Return_Type__c', 'Status__c']
    },
    Claim__c: {
        files: true,
        tab: 'Custom91: Shield',
        listColumns: ['Shipment__c', 'Claim_Type__c', 'Claim_Amount__c', 'Approved_Amount__c', 'Status__c']
    },
    Integration_Log__c: {
        tab: 'Custom63: Chip',
        listColumns: ['Integration_Name__c', 'Direction__c', 'Status__c', 'Status_Code__c', 'Error_Category__c', 'Log_Timestamp__c']
    }
};

/* ------------------------------------------------------------------ */
/* Phase 7: Lightning pages                                            */
/* ------------------------------------------------------------------ */

/** Standard record page components (no required properties). */
const HIGHLIGHTS = { name: 'force:highlightsPanel', identifier: 'force_highlightsPanel' };
const DETAIL = { name: 'force:detailPanel', identifier: 'force_detailPanel' };
const RELATED_LISTS = {
    name: 'force:relatedListContainer',
    identifier: 'force_relatedListContainer',
    properties: { relatedListComponentOverride: 'NONE', rowsToDisplay: '10', showActionBar: 'true' }
};

/**
 * App pages (template flexipage:defaultAppHomeTemplate, one region "main"), each with a Lightning page
 * tab in the eLogix ERP app. A permission set gets the tab when it can read `requires`. Components are
 * LWC bundle names; `properties` set their design attributes.
 */
export const APP_PAGES = [
    {
        api: 'eLogix_Shipment_Console',
        label: 'Shipment Console',
        description: 'eLogix shipment list and shipment booking.',
        motif: 'Custom98: Truck',
        requires: 'Shipment__c',
        components: ['shipmentManagement', { name: 'shipmentBooking', properties: { stayOnPage: 'true' } }]
    },
    {
        api: 'eLogix_Fleet_Console',
        label: 'Fleet Console',
        description: 'eLogix fleet board: vehicles and drivers.',
        motif: 'Custom73: Highway Sign',
        requires: 'Vehicle__c',
        components: ['fleetManagement']
    },
    {
        api: 'eLogix_Tracking_Console',
        label: 'Tracking Console',
        description: 'eLogix tracking console: shipments on the road, history and manual events.',
        motif: 'Custom30: Radar dish',
        requires: 'Tracking_Event__c',
        components: ['trackingConsole']
    }
];

/**
 * Record pages (template flexipage:recordHomeTemplateDesktop: header, main, sidebar), assigned as the
 * eLogix ERP app default for the object on desktop. The standard highlights panel keeps the Edit and
 * other record actions; related lists stay available.
 */
export const RECORD_PAGES = [
    {
        api: 'eLogix_Shipment_Record_Page',
        label: 'eLogix Shipment Record Page',
        description: 'Shipment details and status change, allocation, delivery and tracking history.',
        object: 'Shipment__c',
        regions: {
            header: [HIGHLIGHTS],
            main: ['shipmentDetails', 'vehicleAllocation', 'deliveryManagement', RELATED_LISTS],
            sidebar: ['shipmentTimeline']
        }
    },
    {
        api: 'eLogix_Quotation_Record_Page',
        label: 'eLogix Quotation Record Page',
        description: 'Quotation pricing, charge lines and lifecycle actions.',
        object: 'Quotation__c',
        regions: {
            header: [HIGHLIGHTS],
            main: ['quotationBuilder', RELATED_LISTS],
            sidebar: [DETAIL]
        }
    }
];

/**
 * Lightning app. Navigation follows CLAUDE.md section 8. The Executive Dashboard is a native
 * Salesforce dashboard (Phase 7), reached through the standard Dashboards tab.
 */
export const APPLICATION = {
    api: 'eLogix_ERP',
    label: 'eLogix ERP',
    description: 'eLogix ERP - logistics and supply chain management: shipments, fleet, warehousing, pricing, tracking, billing and returns.',
    headerColor: '#0B5CAB',
    tabs: [
        'standard-home',
        'standard-Dashboard',
        'eLogix_Shipment_Console',
        'eLogix_Fleet_Console',
        'eLogix_Tracking_Console',
        'standard-Account',
        'Shipment_Request__c',
        'Quotation__c',
        'Shipment__c',
        'Vehicle__c',
        'Driver__c',
        'Vehicle_Assignment__c',
        'Warehouse__c',
        'Inventory__c',
        'Route__c',
        'Rate_Card__c',
        'Tracking_Event__c',
        'Delivery__c',
        'Invoice__c',
        'Payment__c',
        'Return_Request__c',
        'Claim__c',
        'standard-report'
    ]
};
