# eLogix ERP - Apex Test Matrix

| | |
|---|---|
| Last run | 2026-11-19, deploy `0Afg700000KNnfeCAD` (`RunLocalTests`) on `eLogixDev` |
| Result | **77 of 77 passed**, 0 failures. Test run time is about 40 seconds. |
| Coverage | **97.5%** (621 of 637 lines) across 17 classes that contain code, plus the trigger |
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
| **Trigger re-entry**: roll-up recalculation fires the trigger with no queries and no events | `ShipmentTriggerHandlerTest.rollUpRecalculationReFiresTriggerWithoutEvents`, `handlerIgnoresSavesWithoutStatusChange` |
| **Trigger re-entry**: workflow-style re-fire does not duplicate; retry after rollback rewrites the same key | `ShipmentTriggerHandlerTest.reEntryWithTheSameVersionDoesNotDuplicateEvents` |
| **Rollback**: a failed tracking insert rolls back the status change (all-or-none and partial modes) | `ShipmentTriggerHandlerTest.trackingFailureRollsBackTheStatusChange` |
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
| `ShipmentTriggerHandlerTest` | 16 | End to end through DML as Operations Executive and Logistics Manager |
| `TrackingServiceTest` | 13 | Service with DML as four role users |
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
| `TrackingService` | 96.2% (203/211) | Rollback branch when the summary update throws (the savepoint path); two empty-input early returns |
| `TrackingEventRequest` | 92.9% | No-argument constructor |
| `ShipmentService` | 90.0% (45/50) | Catch branch for an exception from the user-mode update (the observed failure mode is a row error, which is covered) |
| `ShipmentSelector` | 83.3% (5/6) | Empty-input early return |

The summary-update rollback branch in `TrackingService.recordEvents` is not exercised yet. It **is reachable in production**: the system-mode summary update still runs the shipment's validation rules, so a shipment that currently breaks a rule fails the update and triggers the rollback. That happens with records loaded under `eLogix_Data_Migration` (validation bypass), and could happen with future record-triggered automation on `Shipment__c`.

It can be tested **without** a production failure switch:
1. A user holding Operations Executive and Data Migration creates a shipment whose expected delivery date is before its pickup date.
2. A Logistics Manager, who has View All but no bypass, records an event on that shipment.
3. Expected result: the event is rolled back and the request reports `OPERATION_FAILED`.

This test is proposed for the next deploy ([PHASE2_IMPLEMENTATION_REPORT.md](PHASE2_IMPLEMENTATION_REPORT.md) section 9). It was not added during the pre-commit review, because a new test cannot run without a deploy.

## 4. How to run

```bash
# All local tests with coverage (the org has no other Apex)
sf apex run test --test-level RunLocalTests --code-coverage --result-format human --wait 20 --target-org eLogixDev

# Post-deploy behaviour against live configuration (rolled back)
sf apex run --file scripts/apex/verify-phase2-apex.apex --target-org eLogixDev   # expect checks=12 failures=0
```
