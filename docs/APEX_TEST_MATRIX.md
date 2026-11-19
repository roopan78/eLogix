# eLogix ERP - Apex Test Matrix

| | |
|---|---|
| Last run | 2026-11-19, deploy `0Afg700000KOZcDCAX` (Phase 2 follow-up F1 to F3, `RunLocalTests`) on `eLogixDev`. Previous: `0Afg700000KNnfeCAD` (77 tests, 97.5%). |
| Result | **79 of 79 passed**, 0 failures. Test run time is about 38 seconds. |
| Coverage | **98.5%** (637 of 647 lines) across 17 classes that contain code, plus the trigger |
| Standards | [TEST_STRATEGY.md](TEST_STRATEGY.md) section 2 |

## 1. Scenarios required by CLAUDE.md and the Phase 2 instructions

| Scenario | Test(s) |
|---|---|
| Successful shipment creation records history | `ShipmentTriggerHandlerTest.insertRecordsCreatedEventWithDeterministicKey` |
| Invalid shipment creation (non-initial status) | `ShipmentTriggerHandlerTest.insertWithNonInitialStatusIsRejected`, `ShipmentStatusPolicyTest.creationAllowedOnlyForInitialStatuses` |
| Invalid status transition rejected, with no event | `ShipmentTriggerHandlerTest.invalidTransitionIsRejectedWithoutEvent`, `ShipmentStatusPolicyTest.unlistedTransitionRejected` |
| All 46 deployed transitions are valid | `ShipmentStatusTransitionConfigTest.everyActiveRowUsesValidValues`, `ShipmentStatusPolicyTest.deployedConfigurationLoadsWithoutErrors` |
| Main lifecycle Draft → Closed allowed by deployed configuration | `ShipmentStatusTransitionConfigTest.deployedLifecycleBehavesAsDocumented` |
| Every status reachable; every open status has an exit | `ShipmentStatusTransitionConfigTest.everyStatusIsReachableAndEveryOpenStatusHasAnExit` |
| Closed/Cancelled cannot be reopened; delivery cannot be reversed, **even under override** | `ShipmentStatusPolicyTest.hardRulesCannotBeOverriddenEvenWhenConfigured`, `ShipmentTriggerHandlerTest.overrideCannotReopenFinalStatusesOrReverseDelivery`, `ShipmentStatusTransitionConfigTest.noActiveRowBreaksAHardRule` |
| Missing configuration fails closed | `ShipmentStatusPolicyTest.missingConfigurationFailsClosedForEveryone` |
| Invalid or ambiguous configuration blocks only its pair | `ShipmentStatusPolicyTest.invalidConfigurationBlocksItsTransitionEvenUnderOverride` |
| Inactive transition rejected | `ShipmentStatusPolicyTest.inactiveTransitionRejected` |
| Shipment needs an item before confirmation | `ShipmentTriggerHandlerTest.confirmationRequiresAnItem`, `ShipmentItemsRequiredGuardTest.*`, `ShipmentStatusPolicyTest.itemGuardAppliesEvenUnderOverride` |
| Permission-gated cancel: Operations Executive rejected, Logistics Manager allowed | `ShipmentTriggerHandlerTest.cancellingAfterConfirmationNeedsPermission`, `ShipmentStatusPolicyTest.permissionGatedTransitionNeedsThePermission` |
| Override recorded as an `Exception` event with remarks | `ShipmentTriggerHandlerTest.overrideRecordsAnExceptionEvent`, `ShipmentStatusPolicyTest.overrideAllows*`, `overrideKeepsConfiguredEventTypeWhenARowExists` |
| Tracking event creation (type, from/to, source, key, remarks) | `ShipmentTriggerHandlerTest.allowedTransitionRecordsOneEvent`, `holdReasonIsCopiedToTheEvent`, `consecutiveTransitionsInOneTransactionEachRecordAnEvent` |
| **Bulk: 200-row insert and update**, 1 query and 2 DML each | `ShipmentTriggerHandlerTest.bulkInsertAndUpdateUseOneQueryAndOneInsertEach` |
| Bulk policy evaluation keeps order and indexes | `ShipmentStatusPolicyTest.bulkEvaluationPreservesOrderAndIndexes` |
| **Partial success**: 100 valid and 100 invalid rows in one `allOrNone=false` update | `ShipmentTriggerHandlerTest.partialSuccessKeepsValidRowsAndRejectsInvalidOnes` |
| **Trigger re-entry**: roll-up recalculation fires the trigger with no queries and no events; a 200-row save without a status change costs 0 queries and only its own DML | `ShipmentTriggerHandlerTest.rollUpRecalculationReFiresTriggerWithoutEvents`, `savesWithoutStatusChangeCostNothing` |
| **Trigger re-entry**: a workflow-style re-fire that computes an already-stored key writes nothing and does not block the save (driven through the real trigger) | `ShipmentTriggerHandlerTest.reEntryWithTheSameVersionDoesNotDuplicateEvents` |
| **F1: status history only from the shipment trigger**: direct calls and fabricated records sent through the handler test constructor are refused (`STATUS_EVENTS_TRIGGER_ONLY`) and write nothing | `ShipmentTriggerHandlerTest.statusEventsCannotBeRecordedOutsideTheShipmentTrigger` |
| **Rollback**: a failed tracking insert rolls back the status change (all-or-none and partial modes) | `ShipmentTriggerHandlerTest.trackingFailureRollsBackTheStatusChange` |
| **F2: summary-update rollback**, reached with real data and no failure switch: a shipment loaded under the validation bypass fails the summary update, so the events of the whole call are rolled back and reported as `OPERATION_FAILED` (current batch-wide behaviour; Phase 6 item in TRACKING_IMPLEMENTATION section 5) | `TrackingServiceTest.summaryFailureRollsBackTheEventsOfTheWholeBatch` |
| Operational events: insert, summary, idempotent replay, batch duplicates, out-of-order events | `TrackingServiceTest.recordsLocationEventAndUpdatesTrackingSummary`, `replayedExternalEventIsIdempotent`, `duplicateWithinOneBatchIsRecordedOnce`, `olderEventDoesNotOverwriteTheLatestLocation`, `newestEventInABatchWinsAndKeepsLastKnownLocation` |
| Status-type and malformed operational events refused per request | `TrackingServiceTest.statusAndInvalidEventsAreRejectedPerRequest` |
| Access: no create permission, invisible shipment, View All manager | `TrackingServiceTest.userWithoutCreateAccessIsDenied`, `shipmentTheUserCannotSeeIsReportedAsNotFound`, `managerWithViewAllCanRecordOnAnotherUsersShipment` |
| Per-request validation failure inside a batch | `TrackingServiceTest.futureTimestampFailsOnlyThatRequest` |
| Bulk operational events: 100 requests, 2 queries | `TrackingServiceTest.bulkEventsUseTwoQueries` |
| Service: per-request results, reason fields, user without edit access | `ShipmentServiceTest.*` (7 tests) |
| Framework: dispatch, results, settings, permissions, logging, error mapping | `TriggerHandlerTest`, `ServiceResultTest`, `SettingsServiceTest`, `PermissionServiceTest`, `LoggerTest`, `ExceptionHandlerTest` |

Every test that depends on permissions runs as a role user with real permission-set assignments (`System.runAs`). The deploying admin holds every eLogix custom permission, so pure policy tests force permissions through `PermissionService.testOverrides`. No test uses `SeeAllData`.

## 2. Test classes

| Class | Tests | Kind |
|---|---|---|
| `ShipmentStatusPolicyTest` | 18 | Pure unit tests (injected rows, in-memory records, no DML) |
| `ShipmentTriggerHandlerTest` | 17 | End to end through DML as Operations Executive and Logistics Manager |
| `TrackingServiceTest` | 14 | Service with DML as five role users, including a Data Migration user who creates legacy-style invalid data |
| `ShipmentServiceTest` | 7 | Service with user-mode DML |
| `ShipmentStatusTransitionConfigTest` | 4 | Deployed CMDT integrity (fails the deploy if configuration breaks a rule) |
| `SettingsServiceTest` | 4 | Deployed settings and failure modes |
| `ShipmentItemsRequiredGuardTest`, `PermissionServiceTest`, `ExceptionHandlerTest` | 3 each | Unit |
| `TriggerHandlerTest`, `ServiceResultTest`, `LoggerTest` | 2 each | Unit |
| `TestDataFactory` | n/a | Shared builders and role users |

## 3. Coverage by class

| Class | Coverage | Lines not covered |
|---|---|---|
| `ELogixException`, `ExceptionHandler`, `Logger`, `PermissionService`, `ServiceResult`, `SettingsService`, `ShipmentDomain`, `ShipmentItemsRequiredGuard`, `ShipmentTrigger`, `ShipmentTriggerHandler`, `TrackingEventSelector`, `TriggerHandler` | 100% | none |
| `ShipmentStatusPolicy` | 99.5% (186/187) | `continue` for a guard returning a null map |
| `TrackingService` | 99.1% (219/221) | Two empty-input early returns |
| `TrackingEventRequest` | 92.9% | No-argument constructor |
| `ShipmentService` | 90.0% (45/50) | Defensive catch for an exception from the user-mode update. Access failures arrive as row errors, which are covered. |
| `ShipmentSelector` | 83.3% (5/6) | Empty-input early return |

The summary-update rollback branch in `TrackingService.recordEvents` is covered (follow-up F2) through a supported production path: data loaded under `eLogix_Data_Migration` that breaks `SHP_Delivery_After_Pickup`. No production failure switch was added.

## 4. How to run

```bash
# All local tests with coverage (the org has no other Apex)
sf apex run test --test-level RunLocalTests --code-coverage --result-format human --wait 20 --target-org eLogixDev

# Post-deploy behaviour against live configuration (rolled back)
sf apex run --file scripts/apex/verify-phase2-apex.apex --target-org eLogixDev   # expect checks=12 failures=0
```
