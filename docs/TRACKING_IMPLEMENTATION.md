# eLogix ERP - Tracking Implementation

| | |
|---|---|
| Status | Live since Phase 2 (deploy `0Afg700000KNnfeCAD`, 2026-11-19) |
| Contract | [APEX_ARCHITECTURE.md](APEX_ARCHITECTURE.md) sections 5.3, 6 and 6.1 |
| Source | `classes/tracking/TrackingService.cls`, `TrackingEventRequest.cls`; `classes/selectors/TrackingEventSelector.cls`, `ShipmentSelector.cls` |

`Tracking_Event__c` is the shipment's immutable history: a master-detail child, with the validation rule `TE_Events_Are_Immutable` blocking updates. Two kinds of event are written.

## 1. Status events (automatic)

`ShipmentTriggerHandler` calls `TrackingService.recordStatusEvents(newList, oldMap)` in after insert and after update.

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
| Workflow or flow field update re-fires the trigger (`Trigger.old` is still the original) | Same key; the existing event is found and skipped | `reEntryWithTheSameVersionDoesNotDuplicateEvents` |
| Partial-success retry (the platform rolls back and re-runs triggers; statics survive) | Same key; the first attempt was rolled back, so the event is written again | Same test (delete, then replay) |
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
