# eLogix ERP - Tracking Implementation

| | |
|---|---|
| Status | Live since Phase 2 (deploy `0Afg700000KNnfeCAD`, 2026-11-19) |
| Contract | [APEX_ARCHITECTURE.md](APEX_ARCHITECTURE.md) sections 5.3, 6 and 6.1 |
| Source | `classes/tracking/TrackingService.cls`, `TrackingEventRequest.cls`; `classes/selectors/TrackingEventSelector.cls`, `ShipmentSelector.cls` |

`Tracking_Event__c` is the shipment's immutable history: a master-detail child, with the validation rule `TE_Events_Are_Immutable` blocking updates. Two kinds of event are written.

## 1. Status events (automatic)

`ShipmentTriggerHandler` calls `TrackingService.recordStatusEvents()` in after insert and after update. The method takes no arguments: it reads `Trigger.new` and `Trigger.oldMap` itself. It throws `AuthorizationException` (`STATUS_EVENTS_TRIGGER_ONLY`) anywhere except a `Shipment__c` after-save trigger, so no caller can supply fabricated records (follow-up F1).

1. Re-evaluate the policy from `Trigger.old` and `Trigger.new`. No state is handed over from the before-trigger.
2. For each allowed change, build an event:

   | Field | Value |
   |---|---|
   | `Event_Type__c` | From the transition row; `Exception` for an override with no row |
   | `From_Status__c` / `To_Status__c` | The actual change (blank from-status on creation) |
   | `Event_Timestamp__c` | Now |
   | `Source__c` | `Manual` when the request came from Lightning, Visualforce or a quick action (`Request.getQuiddity()`); otherwise `Apex Service` |
   | `Remarks__c` | Override note, then `Hold_Reason__c` or `Cancellation_Reason__c`, truncated to 255 characters |
   | `Event_Key__c` | `{shipmentId}:{FromCode}>{ToCode}:{version}` |

3. One query: which keys already exist (`TrackingEventSelector.selectExistingKeys`). Existing keys are skipped.
4. One insert (`allOrNone=false`, system mode). A failed row puts `addError(eLogix_Tracking_Event_Failed)` on its shipment, so **the status change and its history commit together or not at all**.

### Event key

- `FromCode` and `ToCode` are status names without spaces. `NEW` stands for creation.
- `version` is the old record's `SystemModstamp` in milliseconds (`CreatedDate` on insert).
- Example (illustrative Id): `a0Eg700000AbCdEFGH:Draft>Requested:1763538000123`. The maximum length is 66 characters, within `Event_Key__c` (80, unique, external ID).

| Situation | What happens | Verified by |
|---|---|---|
| Workflow or flow field update re-fires the trigger (`Trigger.old` is still the original) | Same key; the existing event is found and skipped | `reEntryWithTheSameVersionDoesNotDuplicateEvents`. Through the real trigger: the test stores the event the re-fire would compute, then saves the change. |
| Partial-success retry (the platform rolls back and re-runs triggers; statics survive) | Same key; the first attempt was rolled back, so the key is absent and the event is written again | The normal write path with a deterministic key: `allowedTransitionRecordsOneEvent`, `partialSuccessKeepsValidRowsAndRejectsInvalidOnes` |
| Two different transitions in one transaction | Different from/to codes, different keys | `consecutiveTransitionsInOneTransactionEachRecordAnEvent` |
| The same from → to pair twice in one transaction from the same version | One event (accepted edge case, decision D6) | Not reachable from the UI |

## 2. Operational events (API)

`TrackingService.recordEvents(List<TrackingEventRequest>)` returns a `ServiceResult`. It is used for GPS pings (Phase 6), the tracking console (Phase 7) and hub scans.

| Step | Rule |
|---|---|
| Access | The user needs create access on `Tracking_Event__c`, otherwise `AuthorizationException` (`ACCESS_DENIED`). Each shipment is read in user mode, `FOR UPDATE`. A shipment the user cannot see gets `SHIPMENT_NOT_FOUND`. |
| Validation | Shipment Id of the right type; event type is a valid picklist value; source (default `Apex Service`) is valid. Otherwise `REQUEST_INVALID`. |
| Status types refused | Event types named after a status, and `Created`, get `STATUS_EVENT_NOT_ALLOWED`. History cannot claim a status change that did not happen. |
| Idempotency | When `externalEventId` is set: `Event_Key__c = EXT:{SourceWithoutSpaces}:{externalEventId}`, or `EXT:` + SHA-256 hex when longer than 80 characters. Keys already stored, or repeated within the batch, are skipped and reported as success. |
| Insert | `allOrNone=false`. Validation-rule failures, such as a timestamp more than one hour in the future, are reported per request. |
| Summary | For each shipment, the newest event that is newer than `Latest_Tracking_Timestamp__c` updates that field and `Latest_Location__c`. An event without a location keeps the last known one. The update re-fires `ShipmentTrigger`, which costs nothing because no status changed. |
| Consistency | Event insert and summary update share a savepoint. If the summary update fails, the events are rolled back and the inserted requests are reported as `OPERATION_FAILED`. |

Cost for a 100-request batch: 2 queries (shipments, existing keys). Measured in `bulkEventsUseTwoQueries`.

## 3. Access model

Several fields are protected, meaning read-only for every role:
- on `Tracking_Event__c`: `Event_Key__c`, `From_Status__c`, `To_Status__c`;
- on `Shipment__c`: `Latest_Location__c`, `Latest_Tracking_Timestamp__c`.

`TrackingService.Writer` therefore writes in system mode, without sharing, after the authorization steps above. The justification is in [APEX_ARCHITECTURE.md](APEX_ARCHITECTURE.md) section 6.1. In effect, a Logistics Manager with View All can record events on shipments owned by Operations users, while a Sales Executive, who has read-only tracking access, cannot record any. Both cases are covered by tests.

## 4. Storage note

With 5 MB of data storage, only allowed status changes and explicit operational events create rows. Roll-up recalculations, no-change saves and replays create none.

## 5. Phase 6 robustness items (follow-up F5, reviewed 2026-11-19)

`recordEvents` is correct today, and its rollback branch is covered by `TrackingServiceTest.summaryFailureRollsBackTheEventsOfTheWholeBatch`. Two behaviours would hurt a high-volume GPS feed. Phase 6, which builds the GPS integration, must resolve both before `recordEvents` is connected to live pings.

### 5.1 Batch-wide rollback

| | |
|---|---|
| Today | Events are inserted with partial success. All shipment summaries are then updated in **one all-or-nothing statement**. If any one shipment fails that update (a validation rule on legacy data loaded under `eLogix_Data_Migration`, or a future Flow on `Shipment__c`), the savepoint rolls back **every** event in the call, and every inserted request is reported as `OPERATION_FAILED`. |
| Why it matters | One bad shipment blocks the whole batch, so the pings for every other vehicle in it are lost until a retry. |
| Planned resolution (Phase 6) | Keep per-shipment consistency without batch-wide coupling: (1) insert events with partial success, as today; (2) build summaries only from the events that succeeded; (3) update summaries with **partial success**; (4) for each shipment whose summary update failed, delete the events just inserted for it, in system mode, in the same transaction, and report only those requests with the update's error code and message. Deleting a just-inserted event is allowed: `TE_Events_Are_Immutable` blocks updates only. (5) Keep the savepoint, but only for unexpected exceptions. |
| Acceptance | A test with one invalid and one valid shipment in the same call: the valid shipment's event and summary are kept, and only the invalid shipment's request fails. `summaryFailureRollsBackTheEventsOfTheWholeBatch` is rewritten deliberately at that point. |

### 5.2 Record-lock contention

| | |
|---|---|
| Today | `ShipmentSelector.selectTrackingSummaryForUpdate` locks the shipments with `FOR UPDATE`, so the newer-than comparison is correct. If another transaction holds the lock for about 10 seconds (concurrent pings for the same vehicle, or a long user save), the query throws `QueryException` (`UNABLE_TO_LOCK_ROW`). It escapes `recordEvents` uncaught instead of becoming a per-request result. |
| Why it matters | Bursty GPS traffic for one shipment can fail a whole call with an unhandled exception and no retry semantics. |
| Planned resolution (Phase 6) | (1) Inbound pings go through the asynchronous path described in [INTEGRATION_DESIGN.md](INTEGRATION_DESIGN.md) section 3, never synchronously from the caller. (2) Pings are grouped per shipment and ordered by timestamp before `recordEvents` is called, so one transaction takes each lock once. (3) `recordEvents` catches the lock exception and reports every affected request with a retryable code (`RECORD_LOCKED`) instead of throwing. (4) The integration layer retries retryable codes with backoff and records attempts in `Integration_Log__c` (`Retry_Count__c`; status `Retrying`, then `Dead Letter`). Idempotent `Event_Key__c` values make the retries safe. |
| Acceptance | A test that holds the shipment lock is not feasible in Apex, so the catch is unit-tested by injecting a selector that throws. The retry and dead-letter path is covered by Phase 6 integration tests. |

No code changed for F5. These are design commitments for Phase 6, tracked in [PROJECT_STATUS.md](../PROJECT_STATUS.md).
