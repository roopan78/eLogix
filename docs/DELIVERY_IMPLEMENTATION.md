# eLogix ERP - Dispatch and Delivery (Phase 5)

| | |
|---|---|
| Status | Implemented, with the tracking event-key fix; check-only verified on `eLogixDev` (validation `0Afg700000KXB1BCAX`, see [PHASE5_IMPLEMENTATION_REPORT.md](PHASE5_IMPLEMENTATION_REPORT.md)). **Not yet deployed.** |
| Decisions | D1 to D5, approved 2026-11-20 (section 7) |
| Related | [FLEET_IMPLEMENTATION.md](FLEET_IMPLEMENTATION.md) · [SHIPMENT_LIFECYCLE.md](SHIPMENT_LIFECYCLE.md) · [SECURITY_DESIGN.md](SECURITY_DESIGN.md) · [API_SPECIFICATION.md](API_SPECIFICATION.md) |

## 1. Flow

```
Ready for Dispatch ─▶ Dispatched ─▶ In Transit ─▶ Out for Delivery ─▶ Delivered
   (revalidated)      (revalidated;    (revalidated)   (attempt N open)   (attempt Delivered,
                       trip Active)                                         POD + file; trip Completed)
                                                        │
                                                        └▶ Failed Delivery ─▶ Out for Delivery (attempt N+1)
                                                           (attempt Failed,     … up to Max_Delivery_Attempts
                                                            trip stays Active)  then On Hold / Return Initiated
```

1. **Dispatch.**
   - The allocation guard revalidates the assignment at Dispatched as well as at Ready for Dispatch and In Transit.
   - The shipment trigger then makes the Planned assignment **Active**.
   - The configured On Hold → In Transit route also activates it.
2. **Start an attempt** (`DeliveryService.startAttempts`).
   - The Delivery trigger numbers the attempt and sets `Attempt_Key__c` (`<shipmentId>:<n>`, unique in the database), under a lock on the shipment.
   - The shipment moves to Out for Delivery.
3. **Record the proof** (`recordProofs`). This creates `Proof_of_Delivery__c` with the receiver and the time received, on the open attempt.
4. **Upload evidence.** Salesforce Files are linked to the proof record.
5. **Confirm** (`confirmDeliveries`).
   - The attempt becomes Delivered, with the receiver and time copied from the proof.
   - The shipment becomes Delivered, with `Actual_Delivery_Date__c` set from the proof.
   - The shipment trigger **completes** the trip.
6. **Failure** (`recordFailures`).
   - The attempt becomes Failed, with its reason; the shipment becomes Failed Delivery.
   - The trip stays Active, because the goods are still on the truck.
   - A retry is a new attempt on the same assignment.

## 2. Rules and where they live

| Rule | Owner |
|---|---|
| One open attempt and at most one Delivered attempt per shipment; attempts only from In Transit, Delayed or Failed Delivery; at most `Max_Delivery_Attempts` (D4); numbering and key set by the system under the shipment lock | `DeliveryDomain` (Delivery trigger) |
| Attempt transitions: Scheduled → Out for Delivery or Failed; Out for Delivery → Delivered or Failed. Delivered and Failed are history. Partially Delivered, Rescheduled and Returned are not supported in Phase 5. | `DeliveryDomain` |
| Delivered needs: the shipment Out for Delivery; a proof with the receiver and time; at least one file when `POD_File_Required` (D5) | `DeliveryDomain` |
| Failed needs: the shipment Out for Delivery, or Cancelled (D2 closure); a reason (validation rule) | `DeliveryDomain` |
| Shipment Out for Delivery, Delivered or Failed Delivery must match its latest attempt, on every path and under override | `ShipmentDeliveryGuard` |
| One proof per attempt, only while the attempt is open; locked once the attempt closes, except for a single verification stamp in the verifier's own name | `ProofOfDeliveryDomain` |
| Evidence files cannot be deleted, unlinked or replaced, even by an administrator; other files are untouched | `ProofEvidenceProtection` (ContentDocument, ContentDocumentLink, ContentVersion triggers) |
| Attempts and proofs cannot be deleted; a shipment with a proof cannot be deleted | Delivery and POD triggers; `DeliveryService.rejectDeletionWithProofOfDelivery` |
| Trip lifecycle: Active at Dispatched or In Transit; Completed at Delivered, Damaged, Lost, Return Initiated or Cancelled. Allowed without `eLogix_Allocate_Fleet` only because the stored shipment status justifies it. | `FleetAllocationService.advanceAssignmentLifecycle`, `VehicleAssignmentDomain.isAutomaticLifecycle` |
| An Active trip holds its truck and driver until Completed (D3) | `FleetSelector`, `VehicleAvailabilityService` |
| Cancellation after dispatch: open attempt closed as Failed, reason Other; trip Completed (D2) | `DeliveryService.closeAttemptsOfCancelledShipments`, `advanceAssignmentLifecycle` |

## 3. Consistency and bulk

Each two-step operation (attempt, then shipment) works on the whole batch at once:
- One savepoint per round, never one per record.
- A record that fails its first step changed nothing.
- If any record fails its second step, the round is rolled back and retried without the failed records.
- At most three rounds, each with a fixed number of DML statements.
- No partial Delivery, POD or Shipment update survives.

Lock order: the shipment first, then its attempts and the assignment. This is the same order as cancellation.

`DeliveryBulkTest` runs 200 shipments through start, proof and confirmation in single calls. Its asserted bounds per call are at most 15 SOQL and 10 DML; the measured values are in the implementation report.

## 4. Security

| Path | Mode | Justification |
|---|---|---|
| Service reads and writes | User mode | CRUD, FLS and sharing of the caller. Operations dispatch and deliver; the Logistics Manager verifies (field access). |
| Enforcement reads | System mode, private `without sharing` reader in `DeliverySelector`, trigger contexts only (`DELIVERY_ENFORCEMENT_TRIGGER_ONLY`) | Numbering, the one-open and one-delivered rules, proof and file checks, and file protection must see every record |
| Attempt closure on cancellation; trip activation and completion | System mode, shipment after-update only | The user moving the shipment has no fleet permission. Each change is accepted only because the stored shipment status justifies it; there is no caller flag. |
| `Delivery__c.Attempt_Number__c`, `Attempt_Key__c`, `Proof_of_Delivery__c.Shipment__c` | Protected fields | Set by the triggers, never by users |

## 5. Tracking history

- Every shipment status change is recorded by `TrackingService`. The event key carries a per-shipment sequence (added in Phase 5), so each retry's Out for Delivery and Failed Delivery events are recorded, distinct and ordered, even within one second.
- A D2 cancellation is recorded as the Cancelled status event, with its reason. The consequences are recorded on their own records:
  - the attempt: Failed, reason Other, note "Closed automatically because the shipment was cancelled after dispatch";
  - the assignment: Completed, with its end.
- No separate operational event is written. Writing one from inside the shipment's own trigger would make the shipment update its own tracking summary, which the platform forbids, or would require changing `TrackingService`.

## 6. Limitations

1. **Partial deliveries, reschedules and returns** (attempt statuses Partially Delivered, Rescheduled, Returned) are refused. Returns belong to Phase 6.
2. **Active assignment correction** (for example a breakdown mid-trip) is not supported. It was deferred in Phase 4.
3. **Stock checks at dispatch, invoicing, payments and their Flows** belong to Phase 5B (D1). The Delivery Completion Flow of the original automation design is dropped, because `DeliveryService` owns that rule.
4. **Truncating** a custom object in Setup bypasses triggers. This is an accepted administrative restriction.
5. **Deleting a shipment without proofs** (Administrator only) still cascades its attempts.
6. **The "fleet busy" and "delivery busy" messages** are detected by status code for DML, and by the English platform text for a query lock timeout.

## 7. Decisions (approved 2026-11-20)

| # | Decision |
|---|---|
| D1 | Inventory, invoicing, payments and their Flows move to Phase 5B |
| D2 | Cancellation after dispatch keeps the existing path (On Hold → Cancelled with `eLogix_Cancel_Confirmed_Shipment`). It completes the Active trip, closes the open attempt as Failed / Other, and is safe against repeated execution. |
| D3 | Active trips block their vehicle and driver until Completed; no stale-window check for Active trips |
| D4 | `Max_Delivery_Attempts` = 3, enforced server-side under the shipment lock |
| D5 | `POD_File_Required` = true. Files linked to proofs cannot be deleted or unlinked by anyone; unrelated files are untouched. |
