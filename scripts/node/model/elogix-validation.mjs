/**
 * eLogix ERP - declarative validation rules.
 *
 * Ownership rule (see docs/BUSINESS_RULES.md): a validation rule owns an invariant only when it
 * can be decided from the record being saved (plus parent lookups) without knowing the prior
 * state or querying siblings. Anything that depends on a transition, on other records or on
 * concurrency (status policy, fleet conflicts, stock reservation, duplicate invoices,
 * payment-vs-balance, paid-invoice immutability) is owned by Apex domain/policy classes.
 *
 * Every rule is wrapped by the writer with NOT($Permission.eLogix_Bypass_Validation_Rules) unless
 * marked `noBypass` - true invariants such as non-negative stock are never bypassable.
 *
 * Validation rule messages cannot reference Custom Labels; they are translated through the
 * Translation Workbench instead. Apex-owned messages use Custom Labels (CLAUDE.md rule 15).
 *
 * Percent fields evaluate as fractions inside formulas (12% -> 0.12), so "at most 100%" is
 * written `> 1`. The scaffolder rejects any percent field compared with or divided by 100.
 */

const rule = (name, field, formula, message, o = {}) => ({ name, field, formula, message, ...o });

/** Error when a charge sign disagrees with its type: Discount lines are negative, all others positive. */
const chargeSignRule = (prefix) =>
    rule(
        `${prefix}_Amount_Sign_Matches_Type`,
        'Amount__c',
        'OR(\n        Amount__c = 0,\n        AND(Amount__c < 0, NOT(ISPICKVAL(Charge_Type__c, "Discount"))),\n        AND(Amount__c > 0, ISPICKVAL(Charge_Type__c, "Discount"))\n    )',
        'Amount must be non-zero. Discount lines must be negative and all other charge types positive.'
    );

const differentEndpoints = (prefix) =>
    rule(
        `${prefix}_Origin_Differs_From_Destination`,
        'Destination__c',
        'TRIM(LOWER(Origin__c)) = TRIM(LOWER(Destination__c))',
        'Origin and destination must be different locations.'
    );

export const VALIDATION_RULES = {
    Account: [
        rule(
            'ACC_Customer_Mandatory_Info',
            'Customer_Code__c',
            'AND(\n        NOT(ISBLANK(Customer_Code__c)),\n        OR(ISBLANK(BillingStreet), ISBLANK(BillingCity), ISBLANK(BillingPostalCode), ISBLANK(Phone))\n    )',
            'A logistics customer (an account with a Customer Code) must have a billing street, city, postal code and phone number.'
        ),
        rule(
            'ACC_Credit_Values_Non_Negative',
            'Credit_Limit__c',
            'OR(Credit_Limit__c < 0, Credit_Terms_Days__c < 0)',
            'Credit limit and credit terms cannot be negative.'
        )
    ],

    Shipment_Request__c: [
        rule(
            'SR_Customer_Must_Be_Active',
            'Customer__c',
            'AND(\n        OR(ISNEW(), ISCHANGED(Customer__c)),\n        NOT(Customer__r.Is_Active_Customer__c)\n    )',
            'Inactive customers cannot raise new shipment requests. Reactivate the customer first.'
        ),
        rule(
            'SR_Weight_Must_Be_Positive',
            'Total_Weight__c',
            'OR(\n        AND(NOT(ISBLANK(Total_Weight__c)), Total_Weight__c <= 0),\n        AND(\n            ISBLANK(Total_Weight__c),\n            NOT(ISPICKVAL(Status__c, "Draft")),\n            NOT(ISPICKVAL(Status__c, "Rejected")),\n            NOT(ISPICKVAL(Status__c, "Cancelled"))\n        )\n    )',
            'Total weight must be greater than zero, and is mandatory once the request leaves Draft.'
        ),
        rule(
            'SR_Pickup_Date_Not_In_Past',
            'Requested_Pickup_Date__c',
            'AND(\n        OR(ISNEW(), ISCHANGED(Requested_Pickup_Date__c)),\n        Requested_Pickup_Date__c < TODAY()\n    )',
            'Requested pickup date cannot be in the past.'
        ),
        rule(
            'SR_Delivery_After_Pickup',
            'Expected_Delivery_Date__c',
            'AND(\n        NOT(ISBLANK(Expected_Delivery_Date__c)),\n        Expected_Delivery_Date__c <= Requested_Pickup_Date__c\n    )',
            'Expected delivery date must be after the requested pickup date.'
        ),
        differentEndpoints('SR'),
        rule(
            'SR_Rejection_Reason_Required',
            'Rejection_Reason__c',
            'AND(ISPICKVAL(Status__c, "Rejected"), ISBLANK(Rejection_Reason__c))',
            'Enter a rejection reason before rejecting the request.'
        )
    ],

    Quotation__c: [
        rule(
            'QT_Charges_Non_Negative',
            'Base_Freight__c',
            'OR(\n        Base_Freight__c < 0, Weight_Charge__c < 0, Distance_Charge__c < 0,\n        Fuel_Surcharge__c < 0, Insurance_Charge__c < 0, Discount__c < 0\n    )',
            'Freight components and discount cannot be negative.'
        ),
        rule(
            'QT_Discount_Within_Charges',
            'Discount__c',
            'BLANKVALUE(Discount__c, 0) > (\n        BLANKVALUE(Base_Freight__c, 0) + BLANKVALUE(Weight_Charge__c, 0) + BLANKVALUE(Distance_Charge__c, 0)\n        + BLANKVALUE(Fuel_Surcharge__c, 0) + BLANKVALUE(Insurance_Charge__c, 0) + BLANKVALUE(Line_Total__c, 0)\n    )',
            'Discount cannot exceed the total of all freight charges.'
        ),
        rule(
            'QT_Tax_Percent_In_Range',
            'Tax_Percent__c',
            'OR(Tax_Percent__c < 0, Tax_Percent__c > 1)',
            'Tax percent must be between 0 and 100.'
        ),
        rule(
            'QT_Valid_Until_Required_When_Sent',
            'Valid_Until__c',
            'AND(\n        OR(ISPICKVAL(Status__c, "Sent"), ISPICKVAL(Status__c, "Accepted")),\n        ISBLANK(Valid_Until__c)\n    )',
            'Set a Valid Until date before sending the quotation to the customer.'
        ),
        rule(
            'QT_Cannot_Accept_Expired',
            'Status__c',
            'AND(\n        ISCHANGED(Status__c),\n        ISPICKVAL(Status__c, "Accepted"),\n        NOT(ISBLANK(Valid_Until__c)),\n        Valid_Until__c < TODAY()\n    )',
            'This quotation has expired and cannot be accepted. Issue a revised quotation.'
        )
    ],

    Quotation_Line__c: [
        chargeSignRule('QTL'),
        rule('QTL_Quantity_Positive', 'Quantity__c', 'AND(NOT(ISBLANK(Quantity__c)), Quantity__c <= 0)', 'Quantity must be greater than zero.'),
        // Phase 3 (decision Q18): lines are locked once the quotation leaves Draft. Deletes are locked by
        // QuotationDomain, because the Line_Total__c roll-up re-saves the parent quotation.
        rule(
            'QTL_Locked_Unless_Draft',
            null,
            'NOT(ISPICKVAL(Quotation__r.Status__c, "Draft"))',
            'Quotation lines can only be added or changed while the quotation is in Draft.'
        )
    ],

    Shipment__c: [
        rule('SHP_Weight_Must_Be_Positive', 'Weight__c', 'Weight__c <= 0', 'Shipment weight must be greater than zero.'),
        rule('SHP_Distance_Must_Be_Positive', 'Distance__c', 'Distance__c <= 0', 'Shipment distance must be greater than zero.'),
        rule(
            'SHP_Delivery_After_Pickup',
            'Expected_Delivery_Date__c',
            'AND(\n        NOT(ISBLANK(Pickup_Date__c)),\n        NOT(ISBLANK(Expected_Delivery_Date__c)),\n        Expected_Delivery_Date__c <= Pickup_Date__c\n    )',
            'Expected delivery date must be after the pickup date.'
        ),
        rule(
            'SHP_Actual_Delivery_After_Pickup',
            'Actual_Delivery_Date__c',
            'AND(\n        NOT(ISBLANK(Pickup_Date__c)),\n        NOT(ISBLANK(Actual_Delivery_Date__c)),\n        Actual_Delivery_Date__c < Pickup_Date__c\n    )',
            'Actual delivery date cannot be before the pickup date.'
        ),
        rule(
            'SHP_Delivered_Requires_Delivery_Date',
            'Actual_Delivery_Date__c',
            'AND(ISPICKVAL(Status__c, "Delivered"), ISBLANK(Actual_Delivery_Date__c))',
            'A delivered shipment must have an actual delivery date.'
        ),
        differentEndpoints('SHP'),
        rule(
            'SHP_Hold_Reason_Required',
            'Hold_Reason__c',
            'AND(ISPICKVAL(Status__c, "On Hold"), ISBLANK(Hold_Reason__c))',
            'Enter a hold reason before placing the shipment on hold.'
        ),
        rule(
            'SHP_Cancellation_Reason_Required',
            'Cancellation_Reason__c',
            'AND(ISPICKVAL(Status__c, "Cancelled"), ISBLANK(Cancellation_Reason__c))',
            'Enter a cancellation reason before cancelling the shipment.'
        )
    ],

    Shipment_Item__c: [
        rule('SHI_Quantity_Positive', 'Quantity__c', 'Quantity__c <= 0', 'Item quantity must be greater than zero.'),
        rule('SHI_Weight_Positive', 'Weight__c', 'AND(NOT(ISBLANK(Weight__c)), Weight__c <= 0)', 'Item weight must be greater than zero when entered.'),
        rule('SHI_Declared_Value_Non_Negative', 'Declared_Value__c', 'Declared_Value__c < 0', 'Declared value cannot be negative.')
    ],

    Vehicle__c: [
        rule('VEH_Capacity_Positive', 'Capacity__c', 'Capacity__c <= 0', 'Vehicle capacity must be greater than zero.'),
        rule('VEH_Odometer_Non_Negative', 'Current_Odometer__c', 'Current_Odometer__c < 0', 'Odometer reading cannot be negative.')
    ],

    Vehicle_Assignment__c: [
        rule(
            'VA_End_After_Start',
            'Assignment_End__c',
            'AND(NOT(ISBLANK(Assignment_End__c)), Assignment_End__c <= Assignment_Start__c)',
            'Assignment end must be after assignment start.'
        ),
        rule(
            'VA_End_Required_When_Completed',
            'Assignment_End__c',
            'AND(ISPICKVAL(Status__c, "Completed"), ISBLANK(Assignment_End__c))',
            'A completed assignment must have an end date and time.'
        )
    ],

    Vehicle_Maintenance__c: [
        rule(
            'VM_Completion_Date_Required',
            'Completion_Date__c',
            'AND(ISPICKVAL(Status__c, "Completed"), ISBLANK(Completion_Date__c))',
            'Enter the completion date before marking maintenance as completed.'
        ),
        rule('VM_Completion_Not_In_Future', 'Completion_Date__c', 'Completion_Date__c > TODAY()', 'Completion date cannot be in the future.'),
        rule('VM_Cost_Non_Negative', 'Cost__c', 'Cost__c < 0', 'Maintenance cost cannot be negative.')
    ],

    Warehouse__c: [
        rule('WH_Capacity_Positive', 'Capacity__c', 'AND(NOT(ISBLANK(Capacity__c)), Capacity__c <= 0)', 'Warehouse capacity must be greater than zero when entered.')
    ],

    Inventory__c: [
        rule(
            'STK_Quantities_Not_Negative',
            'Available_Quantity__c',
            'OR(BLANKVALUE(Available_Quantity__c, 0) < 0, BLANKVALUE(Reserved_Quantity__c, 0) < 0)',
            'Stock cannot become negative.',
            { noBypass: true }
        ),
        rule(
            'STK_Reserved_Within_Available',
            'Reserved_Quantity__c',
            'BLANKVALUE(Reserved_Quantity__c, 0) > BLANKVALUE(Available_Quantity__c, 0)',
            'Reserved quantity cannot exceed available quantity.',
            { noBypass: true }
        ),
        rule('STK_Reorder_Level_Non_Negative', 'Reorder_Level__c', 'Reorder_Level__c < 0', 'Reorder level cannot be negative.')
    ],

    Stock_Movement__c: [
        rule(
            'SM_Quantity_Sign_Valid',
            'Quantity__c',
            'OR(\n        Quantity__c = 0,\n        AND(Quantity__c < 0, NOT(ISPICKVAL(Movement_Type__c, "Adjustment")))\n    )',
            'Quantity must be non-zero. Only Adjustment movements may be negative; every other movement type implies its direction.'
        ),
        rule(
            'SM_Movements_Are_Immutable',
            null,
            'NOT(ISNEW())',
            'Stock movements are an audit trail and cannot be changed. Post a correcting movement instead.'
        )
    ],

    Route__c: [
        rule('RT_Distance_Positive', 'Distance__c', 'Distance__c <= 0', 'Route distance must be greater than zero.'),
        rule(
            'RT_Transit_Hours_Positive',
            'Estimated_Transit_Hours__c',
            'AND(NOT(ISBLANK(Estimated_Transit_Hours__c)), Estimated_Transit_Hours__c <= 0)',
            'Estimated transit hours must be greater than zero when entered.'
        ),
        differentEndpoints('RT'),
        rule('RT_Toll_Non_Negative', 'Toll_Charges__c', 'Toll_Charges__c < 0', 'Toll charges cannot be negative.')
    ],

    Route_Stop__c: [
        rule('RS_Sequence_Positive', 'Sequence__c', 'Sequence__c <= 0', 'Stop sequence must be greater than zero.'),
        rule('RS_Distance_Non_Negative', 'Distance_From_Origin__c', 'Distance_From_Origin__c < 0', 'Distance from origin cannot be negative.')
    ],

    Rate_Card__c: [
        rule(
            'RC_Effective_Range_Valid',
            'Effective_To__c',
            'AND(NOT(ISBLANK(Effective_To__c)), Effective_To__c < Effective_From__c)',
            'Effective To date cannot be before Effective From date.'
        ),
        rule(
            'RC_Rates_Non_Negative',
            'Base_Freight__c',
            'OR(Base_Freight__c < 0, Rate_Per_KG__c < 0, Rate_Per_KM__c < 0, Minimum_Freight__c < 0)',
            'Freight rates cannot be negative.'
        ),
        rule(
            'RC_Percentages_In_Range',
            'Fuel_Surcharge_Percent__c',
            'OR(\n        Fuel_Surcharge_Percent__c < 0, Fuel_Surcharge_Percent__c > 1,\n        Insurance_Percent__c < 0, Insurance_Percent__c > 1\n    )',
            'Fuel surcharge and insurance percentages must be between 0 and 100.'
        )
    ],

    Freight_Charge__c: [chargeSignRule('FC')],

    Tracking_Event__c: [
        rule(
            'TE_Events_Are_Immutable',
            null,
            'NOT(ISNEW())',
            'Tracking events are shipment history and cannot be changed. Record a new event instead.'
        ),
        rule(
            'TE_Timestamp_Not_In_Future',
            'Event_Timestamp__c',
            'Event_Timestamp__c > NOW() + (1/24)',
            'Event timestamp cannot be more than one hour in the future.'
        ),
        rule(
            'TE_Coordinates_Valid',
            'Latitude__c',
            'OR(ABS(BLANKVALUE(Latitude__c, 0)) > 90, ABS(BLANKVALUE(Longitude__c, 0)) > 180)',
            'Latitude must be between -90 and 90 and longitude between -180 and 180.'
        )
    ],

    Delivery__c: [
        rule(
            'DEL_Failure_Reason_Required',
            'Failure_Reason__c',
            'AND(ISPICKVAL(Delivery_Status__c, "Failed"), ISBLANK(TEXT(Failure_Reason__c)))',
            'Select a failure reason for a failed delivery attempt.'
        ),
        rule(
            'DEL_Delivered_Requires_Receiver',
            'Receiver_Name__c',
            'AND(\n        OR(ISPICKVAL(Delivery_Status__c, "Delivered"), ISPICKVAL(Delivery_Status__c, "Partially Delivered")),\n        OR(ISBLANK(Receiver_Name__c), ISBLANK(Delivery_Date__c))\n    )',
            'A completed delivery must record the receiver name and delivery date.'
        ),
        rule('DEL_Attempt_Number_Positive', 'Attempt_Number__c', 'Attempt_Number__c < 1', 'Attempt number must be 1 or greater.')
    ],

    Proof_of_Delivery__c: [
        rule(
            'POD_Exception_Notes_Required',
            'Exception_Notes__c',
            'AND(Has_Exception__c, ISBLANK(Exception_Notes__c))',
            'Describe the exception when a proof of delivery is flagged with an exception.'
        )
    ],

    Invoice__c: [
        rule(
            'INVC_Due_Date_After_Invoice_Date',
            'Due_Date__c',
            'AND(NOT(ISBLANK(Due_Date__c)), Due_Date__c < Invoice_Date__c)',
            'Due date cannot be before the invoice date.'
        ),
        rule('INVC_Payment_Terms_Non_Negative', 'Payment_Terms_Days__c', 'Payment_Terms_Days__c < 0', 'Payment terms cannot be negative.')
    ],

    Invoice_Line__c: [
        chargeSignRule('INL'),
        rule(
            'INL_Tax_Values_Valid',
            'Tax_Amount__c',
            'OR(Tax_Amount__c < 0, Tax_Percent__c < 0, Tax_Percent__c > 1)',
            'Tax amount cannot be negative and tax percent must be between 0 and 100.'
        ),
        rule('INL_Quantity_Positive', 'Quantity__c', 'AND(NOT(ISBLANK(Quantity__c)), Quantity__c <= 0)', 'Quantity must be greater than zero.')
    ],

    Payment__c: [
        rule('PAY_Amount_Positive', 'Amount__c', 'Amount__c <= 0', 'Payment amount must be greater than zero.'),
        rule('PAY_Date_Not_In_Future', 'Payment_Date__c', 'Payment_Date__c > TODAY()', 'Payment date cannot be in the future.')
    ],

    Return_Request__c: [
        rule(
            'RET_Pickup_Date_Not_In_Past',
            'Requested_Pickup_Date__c',
            'AND(\n        OR(ISNEW(), ISCHANGED(Requested_Pickup_Date__c)),\n        Requested_Pickup_Date__c < TODAY()\n    )',
            'Requested pickup date cannot be in the past.'
        ),
        rule(
            'RET_Rejection_Reason_Required',
            'Rejection_Reason__c',
            'AND(ISPICKVAL(Status__c, "Rejected"), ISBLANK(Rejection_Reason__c))',
            'Enter a rejection reason before rejecting the return.'
        ),
        rule(
            'RET_Approval_Before_Pickup',
            'Status__c',
            'AND(\n        OR(\n            ISPICKVAL(Status__c, "Pickup Scheduled"), ISPICKVAL(Status__c, "In Transit"),\n            ISPICKVAL(Status__c, "Received"), ISPICKVAL(Status__c, "Under Inspection"),\n            ISPICKVAL(Status__c, "Inspection Passed"), ISPICKVAL(Status__c, "Inspection Failed"),\n            ISPICKVAL(Status__c, "Restocked")\n        ),\n        ISBLANK(Approval_Date__c)\n    )',
            'A return must be approved before pickup can be scheduled.'
        ),
        rule(
            'RET_Inspection_Before_Resolution',
            'Inspection_Notes__c',
            'AND(\n        OR(ISPICKVAL(Status__c, "Inspection Passed"), ISPICKVAL(Status__c, "Inspection Failed"), ISPICKVAL(Status__c, "Restocked")),\n        OR(ISBLANK(Inspection_Completed_Date__c), ISBLANK(Inspection_Notes__c))\n    )',
            'Complete the inspection (completion date and notes) before resolving the return.'
        )
    ],

    Claim__c: [
        rule('CLM_Amount_Positive', 'Claim_Amount__c', 'Claim_Amount__c <= 0', 'Claim amount must be greater than zero.'),
        rule(
            'CLM_Approved_Within_Claimed',
            'Approved_Amount__c',
            'OR(Approved_Amount__c < 0, Approved_Amount__c > Claim_Amount__c)',
            'Approved amount must be between zero and the claimed amount.'
        ),
        rule(
            'CLM_Settlement_Details_Required',
            'Status__c',
            'AND(\n        ISPICKVAL(Status__c, "Settled"),\n        OR(ISBLANK(Settlement_Date__c), ISBLANK(Approved_Amount__c), ISPICKVAL(Resolution__c, "Pending"))\n    )',
            'A settled claim must have an approved amount, a settlement date and a resolution.'
        )
    ]
};
