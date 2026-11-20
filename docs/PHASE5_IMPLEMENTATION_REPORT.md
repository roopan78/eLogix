# eLogix ERP - Phase 5 Implementation Report (Dispatch and Delivery)

| | |
|---|---|
| Status | **Implemented and check-only verified. Not deployed, not committed.** |
| Baseline | HEAD `ee5d39f` (Phase 4). The org runs the Phase 4 deploy `0Afg700000KW3FNCA1`. |
| Check-only | **Current: `0Afg700000KXB1BCAX`**: Succeeded, 834/834 components, `RunLocalTests` **229/229**, coverage **95.34%**, no coverage warnings. Superseded: `0Afg700000KWxZJCA1` (225/225, before the event-key fix). |
| Design | [DELIVERY_IMPLEMENTATION.md](DELIVERY_IMPLEMENTATION.md) |

## 1. Delivered
- **Trip lifecycle from the shipment.**
  - Allocation revalidated at Dispatched.
  - Active at Dispatched, or at In Transit when reached from On Hold.
  - Completed at Delivered, Damaged, Lost, Return Initiated or Cancelled.
  - Active trips hold their truck and driver until Completed (D3).
  - Manual `activate` and `complete` are withdrawn.
- **Delivery attempts:**
  - numbered under the shipment lock, with a database-unique `Attempt_Key__c`;
  - one open and at most one Delivered attempt per shipment;
  - limit `Max_Delivery_Attempts` = 3 (D4);
  - transitions enforced; Delivered and Failed attempts are history.
- **Proof of delivery:**
  - sequence: attempt → proof → file upload → confirmation;
  - the proof is locked once its attempt closes; a single verification in the verifier's own name;
  - evidence files can't be deleted, unlinked or replaced, even by an administrator (D5).
- **Shipment delivery guard:** Out for Delivery, Delivered and Failed Delivery must match the latest attempt, on every path and under override.
- **Cancellation after dispatch (D2):** the open attempt is closed as Failed / Other and the trip is Completed. It is stateless, so safe against repeated execution.
- **`DeliveryService`:** `startAttempts`, `recordProofs`, `confirmDeliveries`, `recordFailures`, `verifyProofs`. Two-step operations use a batch-level savepoint with a bounded retry of the remaining records: no partial updates, and no savepoint, SOQL or DML per record.

## 2. Files
- **New Apex (24 files, with meta):**
  - `TriggerContext`, `DeliverySelector`;
  - `DeliveryDomain`, `ProofOfDeliveryDomain`, `ProofEvidenceProtection`, `ShipmentDeliveryGuard`, `DeliveryService`;
  - `ProofOfDeliveryRequest`, `DeliveryFailureRequest`;
  - three trigger handlers;
  - five triggers: Delivery, Proof of Delivery, ContentDocument, ContentDocumentLink, ContentVersion.
- **New tests:** `DeliveryServiceTest` (8), `DeliveryTriggerHandlerTest` (8), `ProofEvidenceProtectionTest` (3), `FleetLifecycleTest` (4), `DeliveryBulkTest` (1).
- **Changed Phase 4 code:** `FleetAllocationService`, `VehicleAssignmentDomain`, `FleetSelector`, `VehicleAvailabilityService`, `ShipmentAllocationGuard`.
- **Changed earlier-phase integration points:**
  - `ShipmentTriggerHandler`: three hook calls.
  - `ShipmentStatusPolicy.defaultGuards()`: one line.
- **Changed tests (test data only):**
  - Phase 2 `ShipmentTriggerHandlerTest.overrideCannotReopenFinalStatusesOrReverseDelivery`: builds a real delivery.
  - Phase 4 tests: drive the lifecycle through shipment statuses instead of manual `activate`/`complete`.
  - `TestDataFactory`: `deliveredShipment`, `attachEvidence`.
- **Metadata (generated):**
  - `Delivery__c.Attempt_Key__c` (unique, protected);
  - `Attempt_Number__c` and `Proof_of_Delivery__c.Shipment__c` are now protected;
  - settings `Max_Delivery_Attempts`, `POD_File_Required`;
  - six regenerated permission sets and the Delivery layout;
  - 29 new labels and 1 reworded (111 in total, no apostrophes).
- **Scripts:**
  - `verify-phase5-delivery.apex` (11 checks), `verify-phase5-retries.apex` (7), `verify-phase5-cancellation.apex` (3). The original single script exceeded the 100-query limit for anonymous Apex after deployment (a full lifecycle for four shipments in one transaction); it was split, keeping every check, plus one "no rows left behind" check per script.
  - `verify-phase2-apex.apex`: check 8 now verifies that the override cannot reach Delivered without a confirmed delivery. The delivery-reversal check moved to the Phase 5 script.

## 3. Verification

| Check | Result |
|---|---|
| Check-only, all local tests | 225/225 (24 new) |
| Phase 5 coverage | 100%: `ShipmentDeliveryGuard`, `ProofEvidenceProtection`, handlers, triggers. 90.7% to 94.4%: `DeliveryDomain` 92.0%, `DeliveryService` 91.0%, `DeliverySelector` 90.9%, `ProofOfDeliveryDomain` 91.2%, `FleetAllocationService` 94.0%, `VehicleAssignmentDomain` 94.4%, `FleetSelector` 90.8% |
| Bulk 200 | Start, proof and confirmation of 200 shipments in single calls, each within the asserted bound of 15 SOQL and 10 DML |
| Model validation, generator consistency, `git diff --check` | Pass |
| Scripts against the org (Phase 4 code) | Phase 1 19/19, Phase 3 19/19, Phase 4 20/20. Phase 2 11/12: the changed check 8 needs Phase 5 deployed. Phase 5: pending deployment. |

Check-only iterations:
1. `0Afg700000KW9W6CAL`, 222/225:
   - a test expected a second same-user verification to fail (it is a harmless no-op);
   - a less specific refusal message (the open-attempt check now runs before the status check);
   - the event-key issue in section 4.
2. `0Afg700000KWK1hCAH`, 224/225: the same event-key issue.
3. `0Afg700000KWxZJCA1`, 225/225.

## 4. Event key fix (approved 2026-11-20)

Problem: the Phase 2 status-event key was `{shipmentId}:{From}>{To}:{previous SystemModstamp}`. `SystemModstamp` is stored to the second, so the same transition repeated within one second produced the same key, and the later event was skipped as a duplicate (accepted earlier as Phase 2 decision D6).

**Fix, the smallest change to `TrackingService`:**
- **Key:** `{save identity}:{sequence}`. The sequence is the event's position in the shipment's status history.
- **Rule:** with T status events stored, a save writes `identity:(T+1)`. If `identity:T` already exists, this is a re-fired trigger for the same save, whose first run's event is necessarily the latest, so nothing is written.
- **A later save of the same transition** comes after at least one other transition, so its key differs.
- **Queries:** `TrackingEventSelector.countStatusEvents` (one aggregate query) plus the existing `selectExistingKeys` lookup on the two candidate keys. That is two queries per batch, one more than before.
- **Concurrency:** sequences are taken while the save holds the shipment's row lock. The unique index on `Event_Key__c` remains the backstop.
- **Unchanged:** the existing duplicate prevention, the Phase 2 architecture, and every stored key. Legacy keys are not rewritten and count in the history.

**Tests:**
- `TrackingEventSequenceTest` (4 tests): rapid repeats in one transaction; 50 shipments in bulk with contiguous per-shipment sequences; a re-fire of a save whose identity already occurred in the same second; legacy keys kept.
- `DeliveryServiceTest` asserts again all six retry events, alternating, with increasing sequences.
- Updated expectations, not meaning:
  - the two key-format assertions and the re-entry test in `ShipmentTriggerHandlerTest`;
  - the status-change query counts: 1 → 2 in `ShipmentTriggerHandlerTest` and 4 → 5 in the Phase 3 `QuotationConversionTest` bulk test.

**Validation attempts:**
- `0Afg700000KX6nuCAD` (226/229): my first sequence formula, "other events + 1", gave unique keys but not history positions. It was replaced by the position rule.
- `0Afg700000KX9FVCA1` (228/229): a test assertion counted a legitimate earlier event with the same identity.
- `0Afg700000KXB1BCAX`: 229/229.

## 5. Remaining limitations
See [DELIVERY_IMPLEMENTATION.md](DELIVERY_IMPLEMENTATION.md) section 6:
- partial deliveries, reschedules and returns are refused (returns: Phase 6);
- Active assignment correction is deferred;
- stock, invoicing and payments are in Phase 5B;
- the D2 history is the Cancelled status event plus the attempt and trip records, not a separate tracking event;
- Setup truncation bypasses triggers.
