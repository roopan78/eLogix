# eLogix ERP - Security Design

| | |
|---|---|
| Live in `eLogixDev` | 9 permission sets, 10 custom permissions, org-wide defaults on all 26 objects, field-level security on every non-required field |
| Source | `scripts/node/model/elogix-security.mjs` (matrix) and `elogix-config.mjs` (custom permissions) → generated into `force-app/main/default/permissionsets/` |
| Not yet deployed | Role hierarchy and sharing rules (Phase 9), Apex sharing enforcement (from Phase 2) |

## 1. Principles

1. **Least privilege per business role.** One permission set per role in CLAUDE.md section 12. Users are assigned the Standard User (or System Administrator) profile plus one or more eLogix permission sets. Profiles carry no eLogix access.
2. **Field-level security is derived, not hand-listed.** Every non-required field of a readable object is readable. It is editable only when the role can create or edit the object, the field is not a formula or roll-up, and it is not a protected field the role isn't entitled to. Required and master-detail fields are always visible to anyone with object access (platform rule).
3. **Sensitive operations need a custom permission**, checked in Apex with `FeatureManagement.checkPermission()` and in validation rules with `$Permission`.
4. **Private by default for commercial and financial data.** Requests, quotations, shipments, invoices, returns and claims are Private. Master data is Public Read Only. External sharing is Private everywhere until Experience Cloud is introduced.

## 2. Org-wide defaults

| Object | Internal | External | Why |
|---|---|---|---|
| Shipment Request, Quotation, Shipment, Invoice, Return Request, Claim | Private | Private | Commercial and financial data; visibility through ownership, roles (P9) and View All for managers. |
| Business Unit, Vehicle, Driver, Warehouse, Route, Rate Card | Public Read Only | Private | Reference data everyone needs to read; only owning roles edit. |
| Vehicle Assignment | Public Read/Write | Private | Fleet coordinators work a shared board. Object permissions still limit who can edit. |
| Integration Log | Public Read/Write | Private | Only the Administrator has object access. |
| Line items, events, movements, deliveries, payments | Controlled by Parent | Controlled by Parent | Master-detail. |

## 3. Permission set matrix

Letters: **C**reate, **R**ead, **E**dit, **D**elete, **V**iew All, **M**odify All. A dash means no access.

| Object | Admin | Logistics Mgr | Sales | Operations | Fleet | Warehouse | Finance | Customer Svc |
|---|---|---|---|---|---|---|---|---|
| Account | CREDVM | RV | CRE | R | R | R | RE | R |
| Contact | CREDVM | RV | CRED | R | - | - | R | CRE |
| Business Unit | CREDVM | RV | R | R | R | R | R | R |
| Shipment Request | CREDVM | CREV | CRE | RE | - | - | R | CRE |
| Quotation | CREDVM | CREV | CRE | R | - | - | R | R |
| Quotation Line | CREDVM | CREDV | CRED | R | - | - | R | R |
| Shipment | CREDVM | CREV | R | CRE | RV (P4, Q13) | R | R | R |
| Shipment Item | CREDVM | CREDV | R | CRED | R | R | R | R |
| Vehicle / Driver | CREDVM | RV | - | R | CREDV | - | - | - |
| Vehicle Assignment | CREDVM | CREV | - | R | CREV (P4: no Delete) | - | - | - |
| Vehicle Maintenance | CREDVM | RV | - | - | CREDV | - | - | - |
| Warehouse | CREDVM | RV | - | R | - | CREV | R | - |
| Inventory | CREDVM | RV | - | R | - | CREV | R | - |
| Stock Movement | CREDVM | RV | - | R | - | CRV | - | - |
| Route | CREDVM | CREV | R | R | R | R | R | R |
| Route Stop | CREDVM | CREDV | R | R | R | - | - | - |
| Rate Card | CREDVM | CREV | R | R | - | - | CREV | - |
| Freight Charge | CREDVM | CREDV | R | CRE | - | - | R | - |
| Tracking Event | CREDVM | CRV | R | CR | R | - | - | R |
| Delivery | CREDVM | CREV | - | CRE | R | - | R | R |
| Proof of Delivery | CREDVM | CREV | - | CRE | - | - | R | R |
| Invoice | CREDVM | RV | R | R | - | - | CREV | R |
| Invoice Line | CREDVM | RV | - | - | - | - | CREDV | R |
| Payment | CREDVM | RV | - | - | - | - | CREV | R |
| Return Request | CREDVM | CREV | R | RE | - | RE | R | CRE |
| Claim | CREDVM | CREV | - | R | - | - | RE | CRE |
| Integration Log | CREDVM | RV | - | - | - | - | - | - |

The generator enforces the platform's permission dependencies at build time. Every grant includes Read. Delete requires Edit. Modify All requires Edit, Delete and View All. A detail object needs Read on its master, and View All or Modify All on the detail needs the same on the master. Contact needs Account.

**`eLogix_GPS_Integration`** (Phase 6) is for the GPS provider's API-only integration user, and has no app.

- Object access: Shipment `RV`, Vehicle `R`, Vehicle Assignment `R`, Tracking Event `CR`, Integration Log `CRE`.
- Apex class access: `GpsPingResource`.
- Custom permission: `eLogix_Ingest_GPS`.
- View All on Shipment is required because GPS updates the tracking summary of any shipment on an Active trip. Event and summary writes stay in `TrackingService`'s narrow system-mode writer. The integration user cannot edit shipments.

No role except the Administrator can delete transactional records. Tracking events and stock movements are create-only for everyone else, which keeps them as an audit trail.

## 4. Custom permissions

| Custom permission | Held by | Gates |
|---|---|---|
| `eLogix_Override_Shipment_Status` | Admin, Logistics Mgr | Bypassing `ShipmentStatusPolicy` (still writes tracking history) |
| `eLogix_Cancel_Confirmed_Shipment` | Admin, Logistics Mgr | Confirmed / Ready for Dispatch / On Hold → Cancelled (declared on the transition records) |
| `eLogix_Approve_Quotation` | Admin, Logistics Mgr | Approving quotations above the discount threshold |
| `eLogix_Correct_Dispatched_Allocation` | Admin, Logistics Mgr | Correct the allocation of a shipment that has reached dispatch: shipment On Hold, new reason, full revalidation, tracking event (P4 round 3). Needs `eLogix_Allocate_Fleet` too. |
| `eLogix_Allocate_Fleet` | Admin, Logistics Mgr, Fleet | The trigger enforces it on every `Vehicle_Assignment__c` insert and update, on all paths (P4). The only exemption is the automatic release of a Planned assignment whose shipment is already Cancelled; it is recognised from the stored record state. |
| `eLogix_Adjust_Inventory` | Admin, Warehouse | Manual `Adjustment` / `Damage Write Off` movements |
| `eLogix_Approve_Return` | Admin, Logistics Mgr | `ReturnService` approve/reject (stamps `Approval_Date__c`) |
| `eLogix_Settle_Claim` | Admin, Logistics Mgr, Finance | Claim approval and settlement |
| `eLogix_Record_Advance_Payment` | Admin, Finance | Overpayment, only when setting `Allow_Advance_Payments` is true |
| `eLogix_Modify_Paid_Invoice` | Admin | Editing a Paid invoice |
| `eLogix_Ingest_GPS` | Admin, **`eLogix_GPS_Integration`** | Submitting GPS pings (REST endpoint and `GpsIngestionJob.submit`) |
| `eLogix_Bypass_Validation_Rules` | **`eLogix_Data_Migration` only** | Bypassable validation rules during seeding or migration. Assign temporarily; never part of Admin. |

## <a id="protected-fields"></a>5. Protected fields

These fields hold system-derived values. FLS makes them read-only for every role except those listed. Their owning service writes them.

| Field(s) | Editable by (besides Admin) | Written by |
|---|---|---|
| `Account.Credit_Limit__c`, `Credit_Terms_Days__c` | Finance | Users (Finance) |
| `Quotation__c` pricing components, `Rate_Card__c`, `Tax_Percent__c`, `Version__c`, `Approved_By__c`, `Approval_Date__c` | - | `FreightCalculationService`, quotation approval |
| `Delivery__c.Attempt_Number__c`, `Attempt_Key__c`; `Proof_of_Delivery__c.Shipment__c` | - | The Delivery and POD triggers (Phase 5) |
| `Vehicle_Assignment__c.Correction_Reason__c` | Logistics Mgr | Users holding `eLogix_Correct_Dispatched_Allocation`; the trigger accepts a change only as a valid correction |
| `Shipment__c.Freight_Amount__c`, `Vehicle__c`, `Driver__c`, `Latest_Location__c`, `Latest_Tracking_Timestamp__c` | - | `ShipmentService` and `TrackingService`. `Vehicle__c` and `Driver__c` are written only by the `Vehicle_Assignment__c` trigger mirror (`VehicleAssignmentDomain.MirrorWriter`, P4). |
| `Inventory__c.Available_Quantity__c`, `Reserved_Quantity__c`, `Inventory_Key__c` | - | `InventoryService` (only through stock movements) |
| `Stock_Movement__c.Quantity_Before__c`, `Quantity_After__c`, `Movement_Key__c`, `Performed_By__c` | - | `InventoryService` |
| `Tracking_Event__c.Event_Key__c`, `From_Status__c`, `To_Status__c` | - | `TrackingService` |
| `Invoice__c.Invoice_Key__c`; `Payment__c.Gateway_Transaction_Id__c`, `Idempotency_Key__c` | - | `InvoiceService`, `PaymentService` |
| `Return_Request__c.Approved_By__c`, `Approval_Date__c` | - | `ReturnService` (after `eLogix_Approve_Return`) |
| `Freight_Charge__c.Approved_By__c` | - | Charge approval |
| `Claim__c.Approved_Amount__c`, `Settlement_Date__c` | Finance, Logistics Mgr | Users holding `eLogix_Settle_Claim` |
| `Proof_of_Delivery__c.Verified_By__c` | Logistics Mgr | Users |

## 6. Apex security model (applies from Phase 2)

- All services and controllers are declared `with sharing`. Selectors query `WITH USER_MODE`, so CRUD, FLS and sharing apply to what a user can read.
- User-supplied input is written with `Database.insert/update(records, AccessLevel.USER_MODE)` or after `Security.stripInaccessible(AccessType.UPDATABLE, ...)`.
- **Protected fields** are written in system mode by their owning service. This happens only after the service has checked object access and the relevant custom permission. Each such write is a named, reviewed code path (for example `InventoryService.applyMovement`). It is not a general escape hatch.
- Custom permission checks go through one `PermissionService` so tests can assert them and messages come from Custom Labels.
- No hardcoded record IDs, profile names or user names in Apex.
- **Integrity reads ignore sharing on purpose (Phase 4).** `WITH SYSTEM_MODE` skips CRUD and FLS but still applies the sharing of the calling class. Fleet conflict, maintenance, lock and quoted-vehicle-type reads must see every record, whoever owns it. They therefore run in the private `without sharing` `FleetSelector.EnforcementReader`. Their results go only to the rule evaluator. Violation messages name only the shipment, vehicle and driver the caller supplied. Without this, a Fleet Manager (no Quotation access) would bypass the quoted-type rule silently; this was found during the Phase 4 check-only run.
- **Enforcement reads are trigger-only (Phase 4 audit fix 5).** Each public `FleetSelector` method that reaches the `without sharing` reader checks the executing trigger object and operation, and throws `AuthorizationException` (`FLEET_ENFORCEMENT_TRIGGER_ONLY`) otherwise. No controller, REST resource, invocable action or Flow can read through it.
- **Assignments are never deleted (Phase 4 audit fix 1).** The `Vehicle_Assignment__c` trigger refuses every delete and undelete, for every user including the Administrator, so a restored row can never skip the rules and history is kept. Profile-level Delete or Modify All does not override this.
- **Phase 5 delivery paths.** `DeliverySelector` enforcement reads (attempt numbering under the shipment lock, proof and evidence checks, file protection) are without sharing and limited to their trigger contexts (`DELIVERY_ENFORCEMENT_TRIGGER_ONLY`). The trip lifecycle (`FleetAllocationService.advanceAssignmentLifecycle`) and the closure of attempts on cancellation (`DeliveryService.closeAttemptsOfCancelledShipments`) run in system mode from the shipment after-update trigger only; each change is accepted by its own trigger only because the stored shipment status justifies it. Proof of delivery evidence (Salesforce Files linked to a proof) cannot be deleted, unlinked or replaced by any user through the `ContentDocument`, `ContentDocumentLink` and `ContentVersion` triggers; other files are untouched. Attempts, proofs, and shipments with proofs cannot be deleted. Proof verification is limited by field access to the Logistics Manager and recorded once, in the verifier's own name.
- **Trigger-only system paths (Phase 4).** The shipment mirror (`VehicleAssignmentDomain.syncShipments`) and the cancellation release (`FleetAllocationService.clearCancelledShipmentAllocations`, `releaseCancelledShipmentAssignments`) take no arguments. They read `Trigger.new` and `Trigger.oldMap` and refuse any other caller with an `AuthorizationException`. This is the same pattern as Phase 2 F1. There is no caller-controlled bypass flag.

## 7. Planned (Phase 9): roles and sharing

Role hierarchy: Logistics Manager at the top, with Sales Executive, Operations Executive, Fleet Manager, Warehouse Manager, Finance Executive and Customer Service Executive below. Planned sharing rules:

| Object | Rule |
|---|---|
| Shipment | Read/Write to Operations Executive role; Read to Fleet, Warehouse, Finance, Customer Service roles |
| Shipment Request, Quotation | Read to Operations and Customer Service roles |
| Invoice | Read/Write to Finance role; Read to Customer Service role |
| Return Request, Claim | Read/Write to Customer Service, Warehouse (returns) and Finance (claims) roles |

Until then, the demo user (System Administrator plus `eLogix_Administrator`) sees all data. Role-based demos use managers, whose permission sets include View All.

## 8. Verification performed (Phase 1)

- All 9 permission sets deployed. `eLogix_Administrator` is assigned to the org admin user.
- The rolled-back smoke test (`scripts/apex/verify-phase1-metadata.apex`) ran as that user without the bypass permission. Validation rules fired as expected, which confirms the bypass is not part of the Admin set.
- Not yet verified: login-as tests for each role. These need named test users and are scheduled with the Phase 9 security validation.
