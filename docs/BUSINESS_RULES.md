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
| Shipment must have at least one item before confirmation | Apex policy | `ShipmentItemsRequiredGuard` (via `ShipmentStatusPolicy`) on the move to `Confirmed`, using roll-up `Item_Count__c`; applies under override too | Live, tested (P2) |
| Status must follow an allowed transition | Apex policy | `ShipmentStatusPolicy` reading `Shipment_Status_Transition__mdt` (46 records), enforced by `ShipmentTrigger` for every entry path; fails closed when configuration is missing | Live, tested (P2) |
| Delivered shipments cannot be dispatched again | Configuration | No `Delivered → Dispatched` transition exists (generator check); `ShipmentStatusPolicy` hard rule rejects any move from `Delivered` back to a pre-delivery status, even under override | Live, tested (P2) |
| Cancelled shipments cannot be processed further | Configuration | `Cancelled` and `Closed` have no outgoing transitions (generator check); `ShipmentStatusPolicy` hard rule rejects leaving them, even under override | Live, tested (P2) |
| Cancel after confirmation needs authority | Configuration + Apex | Transition records carry `Required_Permission__c = eLogix_Cancel_Confirmed_Shipment`; checked by `ShipmentStatusPolicy` | Live, tested (P2) |
| Hold and cancellation need a reason | Validation rule | `SHP_Hold_Reason_Required`, `SHP_Cancellation_Reason_Required` | Live |
| Every meaningful status change creates a Tracking Event | Apex | `TrackingService` called from the shipment trigger handler; event type from the transition record; deterministic `Event_Key__c` prevents duplicates; a failed event rolls back the status change | Live, tested (P2) |
| Tracking history is immutable | Validation rule | `TE_Events_Are_Immutable` | Live, verified |

## Freight rules

| Rule | Owner | Component | Status |
|---|---|---|---|
| Freight = base + weight × rate + distance × rate + fuel + insurance + additional − discount + tax | Apex | `FreightCalculationService` writes the components; quotation formulas total them (non-taxable lines excluded from tax, decision Q14) | Live, tested (P3) |
| No hardcoded pricing | Data | `Rate_Card__c` records; tax default in `eLogix_Setting__mdt.Default_Tax_Percent` | Live |
| Pricing is date-aware and uses the applicable rate card | Apex | `FreightCalculationService`: active, vehicle type, effective on the requested pickup date, business-unit/region specificity, lowest `Selection_Priority__c`, latest `Effective_From__c`; ties fail closed | Live, tested (P3) |
| Rates non-negative; percentages within 0-100; effective range valid | Validation rule | `RC_Rates_Non_Negative`, `RC_Percentages_In_Range`, `RC_Effective_Range_Valid` | Live, verified |
| Discount cannot exceed charges | Validation rule | `QT_Discount_Within_Charges` | Live |
| Discount above threshold needs approval | Apex (enforcement) + Flow (routing, P5) | `QuotationDomain`: above `Max_Discount_Percent_No_Approval` (10% of gross freight, header discount + discount lines), Approved/Sent/Accepted need a verified stamp from a non-owner holding `eLogix_Approve_Quotation`; `QuotationService.approve`/`reject` write it. The Quotation Approval Flow (P5) only routes. | Live, tested (P3) |
| Quotation status follows the approved transitions | Apex | `QuotationDomain`: Draft → Pending Approval/Approved; Pending Approval → Approved/Draft; Approved → Sent; Sent → Accepted/Rejected (terminal) | Live, tested (P3) |
| Discount, lines and validity date locked once a quotation leaves Draft (validity date: A4) | Apex + validation rule | `QuotationDomain` (discount, components, line roll-ups, including line deletes) and `QTL_Locked_Unless_Draft` (line insert/update) | Live, tested (P3) |
| Only Submitted / Under Review requests are quoted; request moves to Quoted, Approved (on acceptance), Converted (on conversion) | Apex | `QuotationDomain` (trigger) and `QuotationService.convertToShipment` | Live, tested (P3) |
| One shipment per accepted quotation | Apex | `QuotationService.convertToShipment`: quotation row lock + existing-shipment check; request row lock with its status re-read under the lock, so a changed request is never overwritten (A3) | Live, tested (P3) |
| A quotation stays linked to the request it was priced for | Apex | `QuotationDomain`: `Shipment_Request__c` cannot change after creation, in any status (A1) | Live, tested (P3) |
| Customer rejection of a quotation | None yet (known limitation A5) | The request stays at `Quoted`; re-quoting arrives with quotation revisions | Deferred |
| Expired quotations cannot be accepted | Validation rule | `QT_Cannot_Accept_Expired` | Live |
| Charge sign matches type (Discount negative, others positive) | Validation rule | `QTL_`, `FC_`, `INL_Amount_Sign_Matches_Type` | Live, verified |

## Fleet rules

The `Vehicle_Assignment__c` trigger enforces all fleet rules on every entry path, under row locks: `VehicleAssignmentDomain` calls `VehicleAvailabilityService`. Details are in [FLEET_IMPLEMENTATION.md](FLEET_IMPLEMENTATION.md). "Built (P4)" means implemented and check-only verified, but not yet deployed.

| Rule | Owner | Component | Status |
|---|---|---|---|
| Allocation needs `eLogix_Allocate_Fleet`, except the automatic release when a shipment is cancelled | Apex | `VehicleAssignmentDomain` | Built (P4) |
| Vehicle not Inactive or Under Maintenance; no In Progress maintenance; no Scheduled maintenance overlapping the window | Apex | `VehicleAvailabilityService` (Q2, Q5) | Built (P4) |
| Enough carrying capacity; no load sharing | Apex | `Capacity__c ≥ Shipment.Weight__c` (Q6) | Built (P4) |
| Driver not Inactive or On Leave; licence valid through the window end | Apex | `VehicleAvailabilityService` (Q2, Q4) | Built (P4) |
| Registration and insurance valid through the window end. Fitness is checked too when filled in; a blank fitness date means "not applicable", by design | Apex | `VehicleAvailabilityService` (Q4) | Built (P4) |
| A quoted shipment needs the rate card's vehicle type | Apex | `VehicleAvailabilityService` (Q7) | Built (P4) |
| Shipment, vehicle and driver in the same business unit | Apex | `VehicleAvailabilityService` (Q8) | Built (P4) |
| No overlapping open assignment for a vehicle or driver, whether stored or in the same batch | Apex | `VehicleAvailabilityService` with `FOR UPDATE` on vehicles, then drivers (Q1) | Built (P4) |
| One open assignment per shipment. Allocate while Confirmed or On Hold. No reallocation or release once the shipment has ever reached Ready for Dispatch, decided from its tracking history (returning to On Hold does not reset it) | Apex | `VehicleAssignmentDomain` (Q9, audit fix 2) | Built (P4) |
| Assignment lifecycle: Planned → Active → Completed, or Planned → Cancelled. The shipment link never changes; an Active assignment is frozen | Apex | `VehicleAssignmentDomain` (Q12) | Built (P4) |
| Ready for Dispatch **and In Transit** need an allocation that matches the shipment and still passes every rule against current data (weight, business unit, dates, vehicle and driver status, documents, maintenance, quoted type, overlaps excluding itself) | Apex guard | `ShipmentAllocationGuard` → `VehicleAssignmentDomain.checkDispatchReadiness` (Q10, audit fix 3) | Built (P4) |
| A dispatched allocation can be corrected only while the shipment is On Hold, by a user with `eLogix_Correct_Dispatched_Allocation`, with a new reason; always revalidated and written to tracking history | Apex | `VehicleAssignmentDomain` (round 3) | Built (P4) |
| A shipment with a Planned or Active assignment cannot be deleted | Apex | `FleetAllocationService.rejectDeletionWithOpenAssignments` (round 3) | Built (P4) |
| Assignments cannot be deleted or restored; cancellation is the only release, and history is kept | Apex | `VehicleAssignmentDomain` before delete and after undelete (audit fix 1) | Built (P4) |
| Cancelling a shipment releases its Planned assignment | Apex | Shipment-trigger hooks in `FleetAllocationService` (Q11) | Built (P4) |
| The shipment's `Vehicle__c` and `Driver__c` mirror the open assignment | Apex | `VehicleAssignmentDomain.syncShipments` (Q18) | Built (P4) |
| Expired and expiring documents are visible | Formula | `Document_Status__c`, `License_Status__c` and list views; window set by `Document_Expiry_Warning_Days` (Q15) | Built (P4) |
| Maintenance created over existing bookings | Apex guard | Not checked when the maintenance is saved (Q17). Caught when the shipment moves to Ready for Dispatch (audit fix 3). | Partly built |
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
