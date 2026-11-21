# eLogix ERP - Security Design

|                       |                                                                                                                                                                            |
| --------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Live in `eLogixDev`   | 9 eLogix permission sets, custom permissions, private OWD on transactional objects, field-level security on non-required fields (Phase 1)                                  |
| Local Phase 9 source  | `scripts/node/model/elogix-security.mjs` and `scripts/node/lib/sharing-writer.mjs` generate seven roles and nine owner-based sharing rules under `force-app/main/default/` |
| Salesforce validation | Phase 9 role, sharing and permission changes are local and **not deployed or validated against Salesforce**.                                                               |

## 1. Principles

1. **Least privilege per business role.** One permission set per role in CLAUDE.md section 12. Users are assigned the Standard User (or System Administrator) profile plus one or more eLogix permission sets. Profiles carry no eLogix access.
2. **Field-level security is derived, not hand-listed.** Every non-required field of a readable object is readable. It is editable only when the role can create or edit the object, the field is not a formula or roll-up, and it is not a protected field the role isn't entitled to. Required and master-detail fields are always visible to anyone with object access (platform rule).
3. **Sensitive operations need a custom permission**, checked in Apex with `FeatureManagement.checkPermission()` and in validation rules with `$Permission`.
4. **Private by default for commercial and financial data.** Requests, quotations, shipments, invoices, returns and claims are Private. Master data is Public Read Only. External sharing is Private everywhere until Experience Cloud is introduced.
5. **Business Unit isolation is a known production security gap.** `Business_Unit__c` lookups describe ownership context only. OWD, roles, sharing rules, services and tests do not filter or enforce access by Business Unit. Users with object and record access can see records across units. Phase 9 does not add a BU-sharing mechanism.

## 2. Org-wide defaults

| Object                                                                | Internal             | External             | Why                                                                                                |
| --------------------------------------------------------------------- | -------------------- | -------------------- | -------------------------------------------------------------------------------------------------- |
| Shipment Request, Quotation, Shipment, Invoice, Return Request, Claim | Private              | Private              | Commercial and financial data; visibility through ownership, roles (P9) and View All for managers. |
| Business Unit, Vehicle, Driver, Warehouse, Route, Rate Card           | Public Read Only     | Private              | Reference data everyone needs to read; only owning roles edit.                                     |
| Vehicle Assignment                                                    | Public Read/Write    | Private              | Fleet coordinators work a shared board. Object permissions still limit who can edit.               |
| Integration Log                                                       | Public Read/Write    | Private              | Only the Administrator has object access.                                                          |
| Line items, events, movements, deliveries, payments                   | Controlled by Parent | Controlled by Parent | Master-detail.                                                                                     |

## 3. Permission set matrix

Letters: **C**reate, **R**ead, **E**dit, **D**elete, **V**iew All, **M**odify All. A dash means no access.

| Object              | Admin  | Logistics Mgr | Sales | Operations | Fleet                | Warehouse | Finance | Customer Svc |
| ------------------- | ------ | ------------- | ----- | ---------- | -------------------- | --------- | ------- | ------------ |
| Account             | CREDVM | RV            | CRE   | R          | R                    | R         | RE      | R            |
| Contact             | CREDVM | RV            | CRED  | R          | -                    | -         | R       | CRE          |
| Business Unit       | CREDVM | RV            | R     | R          | R                    | R         | R       | R            |
| Shipment Request    | CREDVM | CREV          | CRE   | RE         | -                    | -         | R       | CRE          |
| Quotation           | CREDVM | CREV          | CRE   | R          | -                    | -         | R       | R            |
| Quotation Line      | CREDVM | CREDV         | CRED  | R          | -                    | -         | R       | R            |
| Shipment            | CREDVM | CREV          | R     | CRE        | RV (P4, Q13)         | R         | R       | R            |
| Shipment Item       | CREDVM | CREDV         | R     | CRED       | R                    | R         | R       | R            |
| Vehicle / Driver    | CREDVM | RV            | -     | R          | CREDV                | -         | -       | -            |
| Vehicle Assignment  | CREDVM | CREV          | -     | R          | CREV (P4: no Delete) | -         | -       | -            |
| Vehicle Maintenance | CREDVM | RV            | -     | -          | CREDV                | -         | -       | -            |
| Warehouse           | CREDVM | RV            | -     | R          | -                    | CREV      | R       | -            |
| Inventory           | CREDVM | RV            | -     | R          | -                    | CREV      | R       | -            |
| Stock Movement      | CREDVM | RV            | -     | R          | -                    | CRV       | -       | -            |
| Route               | CREDVM | CREV          | R     | R          | R                    | R         | R       | R            |
| Route Stop          | CREDVM | CREDV         | R     | R          | R                    | -         | -       | -            |
| Rate Card           | CREDVM | CREV          | R     | R          | -                    | -         | CREV    | -            |
| Freight Charge      | CREDVM | CREDV         | R     | CRE        | -                    | -         | R       | -            |
| Tracking Event      | CREDVM | CRV           | R     | CR         | R                    | -         | -       | R            |
| Delivery            | CREDVM | CREV          | -     | CRE        | R                    | -         | R       | R            |
| Proof of Delivery   | CREDVM | CREV          | -     | CRE        | -                    | -         | R       | R            |
| Invoice             | CREDVM | RV            | R     | R          | -                    | -         | CREV    | R            |
| Invoice Line        | CREDVM | RV            | -     | -          | -                    | -         | CREDV   | R            |
| Payment             | CREDVM | RV            | -     | -          | -                    | -         | CREV    | R            |
| Return Request      | CREDVM | CREV          | R     | RE         | -                    | RE        | R       | CRE          |
| Claim               | CREDVM | CREV          | -     | R          | -                    | -         | RE      | CRE          |
| Integration Log     | CREDVM | RV            | -     | -          | -                    | -         | -       | -            |

The generator enforces the platform's permission dependencies at build time. Every grant includes Read. Delete requires Edit. Modify All requires Edit, Delete and View All. A detail object needs Read on its master, and View All or Modify All on the detail needs the same on the master. Contact needs Account.

**Phase 8 analytics.** The eLogix Reports folder is shared View with all internal users. Reports run as the viewer (CRUD, FLS, sharing). Dashboards run as one fixed administrator and show org-wide totals; the dashboard folder is restricted to Logistics Manager. Details: [ANALYTICS_IMPLEMENTATION.md](ANALYTICS_IMPLEMENTATION.md) section 5.

**Phase 7 UI controllers.** Each role permission set gets Apex class access to a screen controller when it can read the screen's object (generated from `CONTROLLER_ACCESS`: Shipment, Quotation, Vehicle Assignment, Delivery, Tracking Event), and the Shipment, Fleet and Tracking Console tabs on the same basis. The controllers are thin, `with sharing`, read in user mode and delegate every write to the services, so the UI adds no access path. Details: [LWC_IMPLEMENTATION.md](LWC_IMPLEMENTATION.md) section 4.

**`eLogix_GPS_Integration`** (Phase 6) is for the GPS provider's API-only integration user, and has no app.

- Object access: Shipment `RV`, Vehicle `R`, Vehicle Assignment `R`, Tracking Event `CR`, Integration Log `CRE`.
- Apex class access: `GpsPingResource`.
- Custom permission: `eLogix_Ingest_GPS`.
- View All on Shipment is required because GPS updates the tracking summary of any shipment on an Active trip. Event and summary writes stay in `TrackingService`'s narrow system-mode writer. The integration user cannot edit shipments.

No role except the Administrator can delete transactional records. Tracking events and stock movements are create-only for everyone else, which keeps them as an audit trail.

## 4. Custom permissions

| Custom permission                      | Held by                             | Gates                                                                                                                                                                                                                                                  |
| -------------------------------------- | ----------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `eLogix_Override_Shipment_Status`      | Admin, Logistics Mgr                | Bypassing `ShipmentStatusPolicy` (still writes tracking history)                                                                                                                                                                                       |
| `eLogix_Cancel_Confirmed_Shipment`     | Admin, Logistics Mgr                | Confirmed / Ready for Dispatch / On Hold → Cancelled (declared on the transition records)                                                                                                                                                              |
| `eLogix_Approve_Quotation`             | Admin, Logistics Mgr                | Approving quotations above the discount threshold                                                                                                                                                                                                      |
| `eLogix_Correct_Dispatched_Allocation` | Admin, Logistics Mgr                | Correct the allocation of a shipment that has reached dispatch: shipment On Hold, new reason, full revalidation, tracking event (P4 round 3). Needs `eLogix_Allocate_Fleet` too.                                                                       |
| `eLogix_Allocate_Fleet`                | Admin, Logistics Mgr, Fleet         | The trigger enforces it on every `Vehicle_Assignment__c` insert and update, on all paths (P4). The only exemption is the automatic release of a Planned assignment whose shipment is already Cancelled; it is recognised from the stored record state. |
| `eLogix_Adjust_Inventory`              | Admin, Warehouse                    | Manual `Adjustment` / `Damage Write Off` movements                                                                                                                                                                                                     |
| `eLogix_Approve_Return`                | Admin, Logistics Mgr                | `ReturnService` approve/reject (stamps `Approval_Date__c`)                                                                                                                                                                                             |
| `eLogix_Settle_Claim`                  | Admin, Logistics Mgr, Finance       | Claim approval and settlement                                                                                                                                                                                                                          |
| `eLogix_Record_Advance_Payment`        | Admin, Finance                      | Overpayment, only when setting `Allow_Advance_Payments` is true                                                                                                                                                                                        |
| `eLogix_Modify_Paid_Invoice`           | Admin                               | Editing a Paid invoice                                                                                                                                                                                                                                 |
| `eLogix_Ingest_GPS`                    | Admin, **`eLogix_GPS_Integration`** | Submitting GPS pings (REST endpoint and `GpsIngestionJob.submit`)                                                                                                                                                                                      |
| `eLogix_Bypass_Validation_Rules`       | **`eLogix_Data_Migration` only**    | Bypassable validation rules during seeding or migration. Assign temporarily; never part of Admin.                                                                                                                                                      |

## <a id="protected-fields"></a>5. Protected fields

These fields hold system-derived values. FLS makes them read-only for every role except those listed. Their owning service writes them.

| Field(s)                                                                                                                | Editable by (besides Admin) | Written by                                                                                                                                                                         |
| ----------------------------------------------------------------------------------------------------------------------- | --------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `Account.Credit_Limit__c`, `Credit_Terms_Days__c`                                                                       | Finance                     | Users (Finance)                                                                                                                                                                    |
| `Quotation__c` pricing components, `Rate_Card__c`, `Tax_Percent__c`, `Version__c`, `Approved_By__c`, `Approval_Date__c` | -                           | `FreightCalculationService`, quotation approval                                                                                                                                    |
| `Delivery__c.Attempt_Number__c`, `Attempt_Key__c`; `Proof_of_Delivery__c.Shipment__c`                                   | -                           | The Delivery and POD triggers (Phase 5)                                                                                                                                            |
| `Vehicle_Assignment__c.Correction_Reason__c`                                                                            | Logistics Mgr               | Users holding `eLogix_Correct_Dispatched_Allocation`; the trigger accepts a change only as a valid correction                                                                      |
| `Shipment__c.Freight_Amount__c`, `Vehicle__c`, `Driver__c`, `Latest_Location__c`, `Latest_Tracking_Timestamp__c`        | -                           | `ShipmentService` and `TrackingService`. `Vehicle__c` and `Driver__c` are written only by the `Vehicle_Assignment__c` trigger mirror (`VehicleAssignmentDomain.MirrorWriter`, P4). |
| `Inventory__c.Available_Quantity__c`, `Reserved_Quantity__c`, `Inventory_Key__c`                                        | -                           | `InventoryService` (only through stock movements)                                                                                                                                  |
| `Stock_Movement__c.Quantity_Before__c`, `Quantity_After__c`, `Movement_Key__c`, `Performed_By__c`                       | -                           | `InventoryService`                                                                                                                                                                 |
| `Tracking_Event__c.Event_Key__c`, `From_Status__c`, `To_Status__c`                                                      | -                           | `TrackingService`                                                                                                                                                                  |
| `Invoice__c.Invoice_Key__c`; `Payment__c.Gateway_Transaction_Id__c`, `Idempotency_Key__c`                               | -                           | `InvoiceService`, `PaymentService`                                                                                                                                                 |
| `Return_Request__c.Approved_By__c`, `Approval_Date__c`                                                                  | -                           | `ReturnService` (after `eLogix_Approve_Return`)                                                                                                                                    |
| `Freight_Charge__c.Approved_By__c`                                                                                      | -                           | Charge approval                                                                                                                                                                    |
| `Claim__c.Approved_Amount__c`, `Settlement_Date__c`                                                                     | Finance, Logistics Mgr      | Users holding `eLogix_Settle_Claim`                                                                                                                                                |
| `Proof_of_Delivery__c.Verified_By__c`                                                                                   | Logistics Mgr               | Users                                                                                                                                                                              |

## 6. Apex security model (applies from Phase 2)

- All services and controllers are declared `with sharing`. Selectors query `WITH USER_MODE`, so CRUD, FLS and sharing apply to what a user can read.
- User-supplied input is written with `Database.insert/update(records, AccessLevel.USER_MODE)` or after `Security.stripInaccessible(AccessType.UPDATABLE, ...)`.
- **Protected fields** are written in system mode by their owning service. This happens only after the service has checked object access and the relevant custom permission. Each such write is a named, reviewed code path (for example `InventoryService.applyMovement`). It is not a general escape hatch.
- **System-mode business writers still honor sharing.** The protected quotation approval writer and quotation-driven request status writer are explicitly `with sharing`; hierarchy access supports the Logistics Manager's subordinate-owned records. Trigger-only integrity readers and writers remain private and narrowly guarded.
- Custom permission checks go through one `PermissionService` so tests can assert them and messages come from Custom Labels.
- No hardcoded record IDs, profile names or user names in Apex.
- **Integrity reads ignore sharing on purpose (Phase 4).** `WITH SYSTEM_MODE` skips CRUD and FLS but still applies the sharing of the calling class. Fleet conflict, maintenance, lock and quoted-vehicle-type reads must see every record, whoever owns it. They therefore run in the private `without sharing` `FleetSelector.EnforcementReader`. Their results go only to the rule evaluator. Violation messages name only the shipment, vehicle and driver the caller supplied. Without this, a Fleet Manager (no Quotation access) would bypass the quoted-type rule silently; this was found during the Phase 4 check-only run.
- **Enforcement reads are trigger-only (Phase 4 audit fix 5).** Each public `FleetSelector` method that reaches the `without sharing` reader checks the executing trigger object and operation, and throws `AuthorizationException` (`FLEET_ENFORCEMENT_TRIGGER_ONLY`) otherwise. No controller, REST resource, invocable action or Flow can read through it.
- **Assignments are never deleted (Phase 4 audit fix 1).** The `Vehicle_Assignment__c` trigger refuses every delete and undelete, for every user including the Administrator, so a restored row can never skip the rules and history is kept. Profile-level Delete or Modify All does not override this.
- **Phase 5 delivery paths.** `DeliverySelector` enforcement reads (attempt numbering under the shipment lock, proof and evidence checks, file protection) are without sharing and limited to their trigger contexts (`DELIVERY_ENFORCEMENT_TRIGGER_ONLY`). The trip lifecycle (`FleetAllocationService.advanceAssignmentLifecycle`) and the closure of attempts on cancellation (`DeliveryService.closeAttemptsOfCancelledShipments`) run in system mode from the shipment after-update trigger only; each change is accepted by its own trigger only because the stored shipment status justifies it. Proof of delivery evidence (Salesforce Files linked to a proof) cannot be deleted, unlinked or replaced by any user through the `ContentDocument`, `ContentDocumentLink` and `ContentVersion` triggers; other files are untouched. Attempts, proofs, and shipments with proofs cannot be deleted. Proof verification is limited by field access to the Logistics Manager and recorded once, in the verifier's own name.
- **Trigger-only system paths (Phase 4).** The shipment mirror (`VehicleAssignmentDomain.syncShipments`) and the cancellation release (`FleetAllocationService.clearCancelledShipmentAllocations`, `releaseCancelledShipmentAssignments`) take no arguments. They read `Trigger.new` and `Trigger.oldMap` and refuse any other caller with an `AuthorizationException`. This is the same pattern as Phase 2 F1. There is no caller-controlled bypass flag.

## 7. Phase 9 local role and sharing design

The hierarchy has Logistics Manager at the top. Sales Executive, Operations Executive, Fleet Manager, Warehouse Manager, Finance Executive and Customer Service Executive report directly to that role. Role hierarchy grants access to subordinate-owned records; permission sets still control object and field access. The Administrator keeps access through `eLogix_Administrator` and has no eLogix role.

The role metadata uses `Edit` for Case and Opportunity to meet this target org's Public Read/Write defaults. Contact remains at `None`. These levels do not exceed the corresponding org-wide defaults.

Implemented owner-based rules (only these three objects are in Phase 9):

| Object                      | Rule                                                                                       |
| --------------------------- | ------------------------------------------------------------------------------------------ |
| Shipment                    | Read/Write to Operations Executive; Read to Fleet, Warehouse, Finance and Customer Service |
| Shipment Request, Quotation | Read to Operations Executive and Customer Service                                          |

Invoice, Return Request and Claim sharing rules are future work. Their Private OWD currently limits access to owners and hierarchy access, subject to object permissions. The same applies to any other private object without a listed rule.

The model files and generated metadata are not deployed. After manual deployment and sharing recalculation, run the Apex `RoleSharingAccessTest` tests to confirm sales-owned requests and quotations reach Operations and Customer Service and that Operations-owned shipments reach Finance as read-only. These checks rely on actual Salesforce roles and sharing metadata.

## 8. Known production security limitations

- **No Business Unit isolation:** see Principle 5. This is an accepted production gap and must be addressed by a separately approved design before using BU as a confidentiality boundary.
- **Future sharing work:** Invoice, Return Request and Claim rules have not been implemented.
- **Org-specific verification remains:** role hierarchy, sharing-rule recalculation, dashboard folder membership, user licenses and login-as behavior must be validated in the target org by the project owner.
- **Role hierarchy does not grant object permission:** users still need their eLogix permission set. Administrator is not assigned an eLogix role; its access is through `eLogix_Administrator`.

## 9. Verification performed and remaining

- All 9 permission sets deployed. `eLogix_Administrator` is assigned to the org admin user.
- The rolled-back smoke test (`scripts/apex/verify-phase1-metadata.apex`) ran as that user without the bypass permission. Validation rules fired as expected, which confirms the bypass is not part of the Admin set.
- Phase 9 is not deployed or org-validated. `RoleSharingAccessTest` is a deploy-time regression for sharing behavior; named login-as checks remain a manual target-org task.
