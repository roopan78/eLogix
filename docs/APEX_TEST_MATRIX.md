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

## 5. Phase 3 scenarios (deploy `0Afg700000KRUWMCA5`: 136/136 tests, 57 for Phase 3)

| Scenario | Test(s) |
|---|---|
| Reference lane components and totals (9,745.00 / 1,169.40 / 10,914.40) | `FreightCalculationServiceTest.referenceLaneComponents`, `QuotationServiceTest.createsPricedDraftQuotationAndMovesRequestToQuoted` |
| Minimum freight uplift into base; fuel after uplift; insurance on declared value | `minimumFreightUpliftIsRecordedInBaseAndRaisesFuel`, `minimumBelowLineHaulChangesNothing`, `blankDeclaredValueAndPercentagesGiveZero` |
| HALF_UP rounding; percentages divided once | `componentsRoundHalfUpToTwoDecimals`, `percentagesAreDividedByOneHundredExactlyOnce` |
| Rate card eligibility, inclusive dates on the pickup date, specificity, priority, latest effective, ambiguity, not found | `ineligibleCardsAreIgnored`, `effectiveDatesAreInclusiveOnThePricingDate`, `specificityBeatsPriority`, `priorityThenLatestEffectiveFromBreakTies`, `equalTopCandidatesFailAsAmbiguous` |
| Configuration fails closed / drives values | `missingTaxSettingFailsClosed`, `thresholdComesFromConfiguration`, `recalculateRepricesDraftQuotationsOnly` |
| Taxable vs non-taxable lines; Apex mirror equals formulas | `totalsMirrorHonoursTaxableLinesAndNeverTaxesBelowZero`; live script check 6 |
| Threshold boundary (exactly 10% vs 10.01%, discount lines counted) | `discountThresholdBoundary`, `submitWithinThresholdApprovesAutomatically`, `submitAboveThresholdWaitsForApproval` |
| **Bulk**: pricing 200 → 1 SOQL / 0 DML; create 200 → 3 SOQL / 2 DML; convert 200 → 4 SOQL / 3 DML (includes the A3 request lock); no-change save 200 → 0 SOQL / 1 DML | `quotingTwoHundredRequestsUsesOneQuery`, `createFromTwoHundredRequestsIsBulkSafe`, `twoHundredQuotationsConvertInBulk`, `savesWithoutARelevantChangeCostNothing` |
| Per-record failures (request eligibility, inactive customer, missing route or vehicle type, no card, duplicates) | `requestProblemsAreReportedPerRecord`, `aQuotedRequestCannotBeQuotedAgain` |
| **Per-record compensation**: a request that cannot move fails only its quotation; a shipment whose request cannot move is removed | `aRequestThatCannotMoveFailsOnlyItsOwnQuotation`, `aFailedRequestUpdateRemovesOnlyItsOwnShipment` |
| Access: Operations / Customer Service cannot quote; another user's private request is not found; Sales cannot convert | `usersWithoutQuotationCreateAccessAreDenied`, `anotherUsersPrivateRequestIsNotFound`, `usersWhoCannotCreateShipmentsAreDenied` |
| Approval: manager stamp verified and time-stamped; permission required; no self-approval; only pending; rejection to Draft with reason | `managerApprovalWritesAVerifiedStamp`, `approvalNeedsThePermission`, `ownersCannotApproveTheirOwnQuotation`, `onlyPendingQuotationsCanBeDecided`, `rejectionReturnsToDraftWithTheReason` |
| **Direct DML bypass attempts** (two layers: FLS for Sales, trigger for an administrator): creation rules, transitions, stamp forgery/self-approval/backdate/clear, status-label approval, discount/charge lock, line insert/update/delete lock, approver-only rejection | `QuotationTriggerHandlerTest` (12 tests) |
| Acceptance moves the request to Approved; fails if the request is no longer Quoted | `aboveThresholdWithAValidStampCanBeSentAndAccepted`, `acceptanceFailsWhenTheRequestIsNoLongerQuoted` |
| Conversion: Quoted shipment with the Phase 2 Created event, freight = total, request Converted; once only (also within one call); accepted and valid only | `QuotationConversionTest` (7 tests) |
| Request sync refuses to run outside the trigger | `requestSyncOnlyRunsInsideTheQuotationTrigger` |
| **A1**: a quotation cannot be re-pointed to another request, in Draft or later, by Sales or an administrator | `QuotationTriggerHandlerTest.aQuotationCannotBeMovedToAnotherRequest`; live script check 6 |
| **A2**: an owner change in the same save cannot hide a self-approval (the owner change alone is allowed) | `QuotationTriggerHandlerTest.anOwnerChangeCannotHideASelfApproval` |
| **A3**: a request changed after acceptance (Cancelled) is re-read under a row lock, reported, and not overwritten; the other quotation converts | `QuotationConversionTest.aRequestChangedBeforeConversionIsNotOverwritten` |
| **A4**: the validity date is editable in Draft, locked in Pending Approval, Approved, Sent and Accepted, and editable again after a rejected approval returns the quotation to Draft; an accepted quotation cannot be back-dated to expire | `QuotationTriggerHandlerTest.validityIsLockedOnceTheQuotationLeavesDraft`, `QuotationConversionTest.onlyAcceptedValidQuotationsConvert` |

Coverage of Phase 3 classes: `QuotationDomain`, `QuotationTriggerHandler`, `RateCardSelector`, `FreightBreakdown` 100%; `FreightCalculationService` 99.3%; `QuotationService` 94.4%; `QuotationSelector`, `ShipmentRequestSelector` 90.9%; combined 96.9%. Org-wide 97.6%.

## 4. How to run

```bash
# All local tests with coverage (the org has no other Apex)
sf apex run test --test-level RunLocalTests --code-coverage --result-format human --wait 20 --target-org eLogixDev

# Post-deploy behaviour against live configuration (rolled back)
sf apex run --file scripts/apex/verify-phase2-apex.apex --target-org eLogixDev   # expect checks=12 failures=0
```
