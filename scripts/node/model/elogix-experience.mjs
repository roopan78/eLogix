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
        listColumns: ['Vehicle_Number__c', 'Vehicle_Type__c', 'Capacity__c', 'Status__c', 'Business_Unit__c', 'Insurance_Expiry__c']
    },
    Driver__c: {
        tab: 'Custom15: People',
        listColumns: ['License_Number__c', 'License_Expiry__c', 'Phone__c', 'Status__c', 'Business_Unit__c']
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
