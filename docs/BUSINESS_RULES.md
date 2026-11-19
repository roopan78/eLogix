# eLogix ERP - Business Rules and Ownership

CLAUDE.md section 10 requires that no rule be implemented in two mechanisms, and that each rule's owner be documented. This file is that register.

## Ownership model

| Mechanism | Owns a rule when... | Why |
|---|---|---|
| **Field definition** (required, unique, restricted picklist) | The rule is "this value must exist / be unique / be one of these". | Enforced by the database on every channel at no cost. |
| **Validation rule** | The rule is an invariant of one record and its parent lookups, and can be judged without knowing the prior state or querying sibling records. | Declarative, applies to UI, API, data loads and Apex alike. Bypassable through `eLogix_Bypass_Validation_Rules` unless marked otherwise. |
| **Apex domain / policy** | The rule depends on a transition (old to new value), on other records, on concurrency or on a custom permission check with field-level nuance. | Needs `Trigger.old`, SOQL, row locks or bulk-safe aggregation. Messages come from Custom Labels. |
| **Flow** | The rule is orchestration that a business admin should be able to tune: approvals, notifications, scheduled SLA checks. | Admin-maintainable. Flows call Apex invocables instead of duplicating logic. |

Status legend: **Live** = deployed and verified in `eLogixDev`. **Planned (Pn)** = scheduled for that phase.

## Customer rules

| Rule | Owner | Component | Status |
|---|---|---|---|
| Inactive customers cannot create new shipment requests | Validation rule | `Shipment_Request__c.SR_Customer_Must_Be_Active` (on create or customer change) | Live, verified |
| Mandatory customer information must be present | Validation rule | `Account.ACC_Customer_Mandatory_Info`: an account with a Customer Code needs billing street, city, postal code and phone | Live, verified |
| Credit limit and terms cannot be negative | Validation rule | `Account.ACC_Credit_Values_Non_Negative` | Live |
| Customer credit terms must be respected | Apex | `InvoiceService`: due date = invoice date + `Account.Credit_Terms_Days__c`, else `Default_Credit_Terms_Days` setting | Planned (P5) |
| Credit terms editable only by Finance | Security | FLS: protected field, editable by Finance Executive and Administrator | Live |

## Shipment rules

| Rule | Owner | Component | Status |
|---|---|---|---|
| Weight must be greater than zero | Validation rule | `SHP_Weight_Must_Be_Positive`; request-level `SR_Weight_Must_Be_Positive` (mandatory once the request leaves Draft) | Live, verified |
| Distance must be greater than zero | Validation rule | `SHP_Distance_Must_Be_Positive`, `RT_Distance_Positive` | Live |
| Pickup date must be valid | Validation rule | `SR_Pickup_Date_Not_In_Past` and `RET_Pickup_Date_Not_In_Past` (on create or change). Shipment pickup dates may be historical. | Live |
| Expected delivery date must be after pickup | Validation rule | `SR_Delivery_After_Pickup`, `SHP_Delivery_After_Pickup` (strictly after, as specified) | Live, verified |
| Actual delivery cannot precede pickup; delivered shipments need a delivery date | Validation rule | `SHP_Actual_Delivery_After_Pickup`, `SHP_Delivered_Requires_Delivery_Date` | Live |
| Origin and destination must differ | Validation rule | `SR_`, `SHP_`, `RT_Origin_Differs_From_Destination` | Live |
| Shipment must have at least one item before confirmation | Apex policy | `ShipmentStatusPolicy` guard on the move to `Confirmed`, using roll-up `Item_Count__c` | Planned (P2) |
| Status must follow an allowed transition | Apex policy | `ShipmentStatusPolicy` reading `Shipment_Status_Transition__mdt` (46 records live) | Metadata live; policy planned (P2) |
| Delivered shipments cannot be dispatched again | Configuration | No `Delivered → Dispatched` transition exists; the generator refuses to emit one | Live (data); enforced in P2 |
| Cancelled shipments cannot be processed further | Configuration | `Cancelled` and `Closed` have no outgoing transitions (generator check) | Live (data); enforced in P2 |
| Cancel after confirmation needs authority | Configuration + Apex | Transition records carry `Required_Permission__c = eLogix_Cancel_Confirmed_Shipment` | Live (data); enforced in P2 |
| Hold and cancellation need a reason | Validation rule | `SHP_Hold_Reason_Required`, `SHP_Cancellation_Reason_Required` | Live |
| Every meaningful status change creates a Tracking Event | Apex | `TrackingService` called from the shipment trigger handler; event type from the transition record | Planned (P2) |
| Tracking history is immutable | Validation rule | `TE_Events_Are_Immutable` | Live, verified |

## Freight rules

| Rule | Owner | Component | Status |
|---|---|---|---|
| Freight = base + weight × rate + distance × rate + fuel + insurance + additional − discount + tax | Apex | `FreightCalculationService` writes components; quotation formulas total them | Formulas live and verified; service planned (P3) |
| No hardcoded pricing | Data | `Rate_Card__c` records; tax default in `eLogix_Setting__mdt.Default_Tax_Percent` | Live |
| Pricing is date-aware and uses the applicable rate card | Apex | Rate card selection: vehicle type, active, effective dates, lowest `Selection_Priority__c` | Planned (P3) |
| Rates non-negative; percentages within 0-100; effective range valid | Validation rule | `RC_Rates_Non_Negative`, `RC_Percentages_In_Range`, `RC_Effective_Range_Valid` | Live, verified |
| Discount cannot exceed charges | Validation rule | `QT_Discount_Within_Charges` | Live |
| Discount above threshold needs approval | Flow + custom permission | Quotation Approval Flow using `Max_Discount_Percent_No_Approval` (10%); approvers hold `eLogix_Approve_Quotation` | Planned (P5) |
| Expired quotations cannot be accepted | Validation rule | `QT_Cannot_Accept_Expired` | Live |
| Charge sign matches type (Discount negative, others positive) | Validation rule | `QTL_`, `FC_`, `INL_Amount_Sign_Matches_Type` | Live, verified |

## Fleet rules

| Rule | Owner | Component | Status |
|---|---|---|---|
| Vehicle must be active and not under maintenance | Apex | `FleetAllocationService` (pre-filter `Is_Allocatable__c`, `Open_Maintenance_Count__c = 0`; re-check under lock) | Formulas live; service planned (P4) |
| Sufficient carrying capacity | Apex | `Capacity__c ≥ Shipment.Weight__c` | Planned (P4) |
| Driver active with valid licence | Apex | `Driver__c.Is_Allocatable__c` re-checked under lock | Planned (P4) |
| Insurance and registration valid | Apex | `Vehicle__c.Is_Documents_Valid__c` | Planned (P4) |
| No conflicting active assignments | Apex | `VehicleAvailabilityService`: overlap check on open assignments, with `FOR UPDATE` on vehicle and driver rows | Planned (P4) |
| Assignment end after start | Validation rule | `VA_End_After_Start`, `VA_End_Required_When_Completed` | Live |
| Capacity positive | Validation rule | `VEH_Capacity_Positive` | Live |

## Warehouse rules

| Rule | Owner | Component | Status |
|---|---|---|---|
| Stock cannot become negative | Validation rule (not bypassable) | `STK_Quantities_Not_Negative` | Live |
| Reserved stock cannot exceed available | Validation rule (not bypassable) | `STK_Reserved_Within_Available` | Live, verified |
| Stock changes only through movements, with an audit trail | Security + Apex | Quantity fields are protected (read-only for every role); `InventoryService` posts a `Stock_Movement__c` and applies it under lock; movements are immutable (`SM_Movements_Are_Immutable`) | Security and immutability live; service planned (P5) |
| Dispatch must validate required inventory | Apex policy | Guard on `Ready for Dispatch → Dispatched` | Planned (P5) |
| Returns inspected before restocking | Validation rule + Apex | `RET_Inspection_Before_Resolution`; `ReturnService` posts `Return Restock` only after `Inspection Passed` | Rule live; service planned (P6) |

## Invoice and payment rules

| Rule | Owner | Component | Status |
|---|---|---|---|
| No second invoice for the same shipment and billing milestone | Database | Unique `Invoice_Key__c` = shipment + milestone | Live, verified |
| Invoice total matches its lines | Data model | Roll-up subtotal and tax; formula total | Live, verified |
| Payments cannot exceed the outstanding balance unless advance payments are configured | Apex | `PaymentService`: setting `Allow_Advance_Payments` **and** permission `eLogix_Record_Advance_Payment` | Planned (P5) |
| Paid invoices cannot be arbitrarily modified | Apex domain | `InvoiceDomain` compares changed fields when prior status is Paid; requires `eLogix_Modify_Paid_Invoice`. Not a validation rule, because roll-up recalculation from payments would trip it. | Planned (P5) |
| Payment amount positive, not post-dated | Validation rule | `PAY_Amount_Positive`, `PAY_Date_Not_In_Future` | Live |
| Due date not before invoice date | Validation rule | `INVC_Due_Date_After_Invoice_Date` | Live |

## Return and claim rules

| Rule | Owner | Component | Status |
|---|---|---|---|
| Return must reference an original shipment | Field | `Original_Shipment__c` required lookup | Live |
| Return reason mandatory | Field | `Return_Reason__c` required picklist | Live |
| Approval required before pickup scheduling | Validation rule | `RET_Approval_Before_Pickup` (any post-approval status needs `Approval_Date__c`, which only `ReturnService` can write) | Live, verified |
| Inspection complete before resolution | Validation rule | `RET_Inspection_Before_Resolution` | Live |
| Claim approved amount within claimed amount; settlement details required | Validation rule | `CLM_Approved_Within_Claimed`, `CLM_Settlement_Details_Required` | Live |
