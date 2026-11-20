# eLogix ERP - Phase 4 Implementation Report (Fleet Allocation)

| | |
|---|---|
| Status | **Implemented with the six approved audit fixes and check-only verified. Not deployed, not committed.** Waiting for review. |
| Baseline | Branch `feature/phase-2-apex-foundation`, HEAD `d205c9d` (Phase 3). Org `eLogixDev` still runs the Phase 3 deploy `0Afg700000KRUWMCA5`. |
| Check-only | **Current: `0Afg700000KW0hJCAT`**: Succeeded, 779/779 components, `RunLocalTests` **201/201 passed**, coverage **96.4%** (section 8). Superseded: `0Afg700000KVnYnCAL` (190/190, audit fixes), `0Afg700000KSngbCAD` (173/173, first implementation). |
| Decisions | [PHASE4_PLAN.md](PHASE4_PLAN.md) section 0 |
| Design | [FLEET_IMPLEMENTATION.md](FLEET_IMPLEMENTATION.md) |

## 1. Files

**New Apex (8 classes and 1 trigger):**
- `fleet/`: `AllocationRequest`, `AssignmentWindow`, `FleetAllocationService`, `ShipmentAllocationGuard`, `VehicleAssignmentDomain`, `VehicleAvailabilityService`.
- `selectors/FleetSelector`.
- `handlers/VehicleAssignmentTriggerHandler`.
- `triggers/VehicleAssignmentTrigger`.

**New tests:** `FleetAllocationServiceTest` (16), `VehicleAvailabilityServiceTest` (13), `VehicleAssignmentTriggerHandlerTest` (8).

**Changed Apex (authorised):**
- `ShipmentStatusPolicy.defaultGuards()`: one line adding the guard.
- `ShipmentTriggerHandler`: two calls, in before-update and after-update.
- `TestDataFactory`: fleet builders.
- `ShipmentStatusTransitionConfigTest`: regression adjustment, section 4.

**Metadata:**
- 27 `eLogix_Fleet_*` labels.
- Formulas: `Vehicle__c.Document_Status__c` and `Driver__c.License_Status__c` (new); `Is_Allocatable__c` on both objects and `Vehicle__c.Is_Documents_Valid__c` (redefined).
- Five list views (new); both All list views and both layouts (updated).
- Setting `eLogix_Setting.Document_Expiry_Warning_Days` = 30.
- Permission sets (regenerated): Fleet Manager gains Shipment Read + View All; Administrator, Logistics Manager and Operations get FLS for the new formulas.

**Generator:**
- `scaffold-metadata.mjs`: validates `$CustomMetadata` formula references and extra list views.
- `metadata-writer.mjs`: writes filtered list views.
- Model files: `datamodel`, `config`, `security`, `experience`.

**Scripts and docs:**
- `scripts/apex/verify-phase4-fleet.apex` (15 checks).
- New: `FLEET_IMPLEMENTATION.md`, this report.
- Updated: `PHASE4_PLAN.md` (section 0), `BUSINESS_RULES`, `SHIPMENT_LIFECYCLE`, `SECURITY_DESIGN`, `AUTOMATION_DESIGN`, `API_SPECIFICATION`, `DATA_MODEL`, `APEX_TEST_MATRIX`, `TEST_STRATEGY`, `DEPLOYMENT_GUIDE`, `SOLUTION_ARCHITECTURE`, `DEMO_SCRIPT`, generated catalogue.

## 2. Verification

| Check | Result |
|---|---|
| `npm run metadata:validate` | Passed |
| `git diff --check`, BOM scan | Clean |
| Check-only deploy, `RunLocalTests` | 173/173 passed (136 Phase 2/3 + 37 Phase 4), 0 coverage warnings |
| Phase 4 coverage | `VehicleAvailabilityService`, `AssignmentWindow`, `ShipmentAllocationGuard`, handler, trigger 100%; `VehicleAssignmentDomain` 97.3%; `FleetAllocationService` 95.3%; `AllocationRequest` 88.9%; `FleetSelector` 87.4% |
| Bulk 200 allocate | 10 SOQL, 2 DML (asserted) |
| Phase 1, 2, 3 verification scripts (org on Phase 3 code) | 19/19, 12/12, 19/19 |
| Phase 4 verification script | **Not run.** It needs the Phase 4 classes in the org; run it after deployment (expect `checks=15 failures=0`). |

Check-only iterations:
1. Compile error. Apex is case-insensitive, so a local variable `fleet` shadowed the `FLEET` user constant in two tests. The locals were renamed.
2. 171/173 passed:
   - A test helper queried inside a loop (test-only defect, fixed).
   - **A real defect:** the quoted-vehicle-type rule was skipped for a Fleet Manager (section 3).
3. Fixed: the test's precondition query is not allowed for a user without Quotation access, so it now asserts `isAccessible()` is false.
4. Passed.

## 3. Security review

- **Defect found and fixed.** `WITH SYSTEM_MODE` skips CRUD and FLS but still applies the calling class's sharing. The enforcement reads ran with the Fleet Manager's sharing, and the Fleet Manager has no Quotation access. So `Quotation__r` came back null and Q7 was silently skipped. The same gap could also have hidden a conflicting record. All enforcement reads now run in a private `without sharing` `FleetSelector.EnforcementReader`. Their results feed only the rule evaluator, and messages name only what the caller supplied. A regression test proves the precondition (quotation not readable) and the rejection.
- **Single enforcement point.** Every insert and update of `Vehicle_Assignment__c` goes through the trigger rules and needs `eLogix_Allocate_Fleet`. The one exemption (Q11 automatic release) is derived from the stored shipment status and an exact Planned → Cancelled change with nothing else changed. There is no caller flag. A test proves the exemption cannot be borrowed.
- **Narrow system mode:**
  - Shipment mirror: private `MirrorWriter`, assignment trigger only.
  - Cancellation release: shipment trigger only.
  - Both refuse other callers with an `AuthorizationException`, and both are tested.
- **User mode for user intent.** Service reads and writes run in user mode. A Fleet Manager cannot write the protected `Vehicle__c` / `Driver__c` on Shipment directly (tested).
- **Permissions.** The Fleet Manager gains read-only View All on Shipment only. No View All Data, Modify All Data, edit or delete was added. Phase 2 and 3 security is unchanged.

## 4. Phase 1 to 3 regression

- All 136 Phase 2 and 3 tests pass alongside Phase 4.
- One Phase 2 test changed: `ShipmentStatusTransitionConfigTest.deployedLifecycleBehavesAsDocumented` walks Draft → Closed with in-memory records, which cannot satisfy the new Ready for Dispatch guard. It now uses the item guard only and additionally asserts the default guard set includes `ShipmentAllocationGuard`.
- Because the guard also applies under override (Phase 2 rule D2), administrators can no longer move a shipment to Ready for Dispatch without an allocation. That is intended.

## 5. Remaining risks and limitations

See [FLEET_IMPLEMENTATION.md](FLEET_IMPLEMENTATION.md) section 8:
1. Maintenance created over existing bookings (Q17, deferred).
2. Shipment date changes do not move an existing window.
3. Active assignments are not auto-released. Phase 4 never activates; Phase 5 must handle cancellation from Ready for Dispatch.
4. Lock order differs between the service path and the direct DML path.
5. Real concurrency is not reproducible in tests.
6. Rate card region default (Phase 3 note).

**Deployment note.** The redefined `Is_Allocatable__c` formulas change the values that list views and reports show for existing vehicles and drivers. Status no longer needs to be "Available". The allocation rules themselves do not read these formulas.

## 6. Next steps (on approval)

1. Deploy: `sf project deploy start --source-dir force-app --target-org eLogixDev --test-level RunLocalTests`. Alternatively, quick-deploy the validated ID `0Afg700000KSngbCAD`, if it is still eligible.
2. Run the four verification scripts.
3. Commit Phase 4 only.

## 7. Audit fixes (approved 2026-11-20)

| # | Fix | Where |
|---|---|---|
| 1 | Delete and undelete of `Vehicle_Assignment__c` are refused for every user, including the Administrator. The Fleet Manager loses Delete (generator). | Trigger events `before delete` and `after undelete`; `VehicleAssignmentDomain.rejectDeletion` / `rejectRestore`; `elogix-security.mjs` |
| 2 | No reallocation or release once the shipment has ever reached dispatch, decided from `Tracking_Event__c` history. Applies to the service and to direct DML; cancellation is unaffected. | `VehicleAssignmentDomain.validateChanges`; `FleetSelector.shipmentsWithHistoryBeyond` |
| 3 | Ready for Dispatch re-runs every allocation rule against current data, excluding the assignment itself, and refuses a stale window. Validation only. Reallocation renews the window. | `VehicleAssignmentDomain.checkDispatchReadiness`; `ShipmentAllocationGuard`; `FleetAllocationService.reallocate` |
| 4 | Every lock point turns a timeout into `FLEET_BUSY` with the busy text; no raw database text; no retries. | `FleetAllocationService`, `VehicleAssignmentDomain` |
| 5 | The sharing-ignoring reads refuse to run outside their trigger object and operation. | `FleetSelector.requireContext` |
| 6 | The Q5 wording is corrected (behaviour unchanged). | `PHASE4_PLAN.md`, `FLEET_IMPLEMENTATION.md`, `APEX_TEST_MATRIX.md` |

**Files in this round:**
- **Production:** `FleetSelector`, `VehicleAssignmentDomain`, `FleetAllocationService`, `ShipmentAllocationGuard`, `VehicleAssignmentTriggerHandler`, `VehicleAssignmentTrigger`.
- **Metadata:** 4 labels (`eLogix_Fleet_Allocation_Invalid`, `Delete_Not_Allowed`, `Locked_After_Dispatch`, `Window_Changed`); the Fleet Manager permission set (generated).
- **Tests:** `FleetDispatchRulesTest` and `FleetLockingTest` (new); `VehicleAssignmentTriggerHandlerTest` (+3).
- **Script:** `verify-phase4-fleet.apex` (now 18 checks).
- **Docs:** see the list in section 1.

No Phase 1 to 3 production code changed in this round.

**Verification:**
- **Tests:** 190/190 passed (54 for Phase 4).
- **Coverage:** 96.6% org-wide, no warnings.
- **Local checks:** model validation passed; generator output identical to `force-app` and the catalogue (regenerated in a scratch copy); `git diff --check` and the BOM scan are clean.
- **Verification scripts:** Phase 1 19/19, Phase 2 12/12, Phase 3 19/19, run against the org, which still has the Phase 3 code.
- **Phase 4 script:** not run; it needs the Phase 4 code deployed.

New and updated limitations are in [FLEET_IMPLEMENTATION.md](FLEET_IMPLEMENTATION.md) section 8. Notably, a shipment whose allocation becomes invalid after it first reached dispatch can only be cancelled. That follows from fixes 2 and 3 together.

## 8. Workflow fixes, round 3 (approved 2026-11-20)

| # | Issue | Implementation |
|---|---|---|
| 1 | Controlled recovery for dispatched shipments | New custom permission `eLogix_Correct_Dispatched_Allocation` (Administrator, Logistics Manager). New protected field `Vehicle_Assignment__c.Correction_Reason__c` (editable by Administrator and Logistics Manager). The trigger accepts a new reason only with the permission, while the shipment is On Hold, on a Planned assignment that stays Planned. The correction is always fully revalidated, and the trigger writes an `Exception` tracking event through `TrackingService.recordEvents`; if the event fails, the correction fails. `FleetAllocationService.correctDispatchedAllocation`. |
| 2 | Valid allocation required before In Transit | `ShipmentAllocationGuard` targets In Transit as well as Ready for Dispatch, with the same revalidation, from any source status. No transition rule changed. |
| 3 | No orphaned open assignments | `ShipmentTrigger` gains `before delete`, and `ShipmentTriggerHandler.beforeDelete` calls the trigger-only `FleetAllocationService.rejectDeletionWithOpenAssignments`. Completed and Cancelled history keeps the existing retention behaviour. |

**Phase 1 to 3 production components changed in this round:**
- `ShipmentTrigger`: adds the `before delete` event.
- `ShipmentTriggerHandler`: a `beforeDelete` method with one call.

Both are needed for issue 3. Nothing else from Phases 1 to 3 changed. `TrackingService` is reused unchanged.

**Files in this round:**
- **Production:** `VehicleAssignmentDomain`, `FleetAllocationService`, `FleetSelector`, `ShipmentAllocationGuard`, `AllocationRequest`, `VehicleAssignmentTriggerHandler`, `ShipmentTriggerHandler`, `ShipmentTrigger`.
- **Metadata (generated):** the custom permission, the field, the Vehicle Assignment layout, and the Administrator, Logistics Manager, Fleet Manager and Operations permission sets.
- **Labels:** 5 new, 2 reworded.
- **Tests:** `FleetCorrectionTest` (new); `FleetDispatchRulesTest` and `VehicleAssignmentTriggerHandlerTest` (extended).
- **Script:** `verify-phase4-fleet.apex`, now 20 checks.
- **Docs:** fleet, business rules, lifecycle, security, API, test matrix, test strategy, deployment guide.

**Verification:**
- **Tests:** 201/201 passed (65 for Phase 4).
- **Coverage:** 96.4% org-wide, no warnings.
- **Generator:** output identical to `force-app` and the catalogue.
- **Local checks:** model validation passed; `git diff --check` and the BOM scan are clean.
- **Verification scripts:** Phase 1 19/19, Phase 2 12/12, Phase 3 19/19, run against the org on the Phase 3 code.
- **Phase 4 script:** pending deployment.
