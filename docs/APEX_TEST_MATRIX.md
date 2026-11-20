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

## 6. Phase 4 scenarios (check-only validation `0Afg700000KSngbCAD`: 173/173 tests, 37 for Phase 4; not yet deployed)

| Scenario | Test(s) |
|---|---|
| Valid allocation: Planned, window derived from the shipment in org time (Q3), business unit stamped, shipment mirrored (Q18) | `FleetAllocationServiceTest.allocatesAndMirrorsTheShipment`, `VehicleAvailabilityServiceTest.windowsUseOrgTimeBoundaries` |
| Capacity; inactive vehicle and driver; Under Maintenance; On Leave | `VehicleAvailabilityServiceTest` status, capacity and business-unit tests; `FleetAllocationServiceTest.ruleViolationsAreReportedPerRecord` |
| Expired insurance, registration and licence through the window end; fitness checked only when filled in (Q4) | `VehicleAvailabilityServiceTest` document tests; `ruleViolationsAreReportedPerRecord` |
| Maintenance: In Progress blocks whatever its dates; Scheduled blocks when its dates overlap; Scheduled with no completion date occupies only its scheduled day (Q5) | `VehicleAvailabilityServiceTest` maintenance tests |
| Vehicle and driver overlaps, stored and within one call; a non-overlapping later booking is allowed; back-to-back days do not overlap (Q1) | `aDoubleBookedDriverIsRejectedButALaterBookingIsAllowed`, `doubleBookingWithinOneCallIsRejected`, `VehicleAvailabilityServiceTest` overlap tests |
| Quoted vehicle type, including when the Fleet Manager cannot read the quotation (sharing regression) (Q7) | `FleetAllocationServiceTest.theQuotedVehicleTypeIsEnforced` |
| Business-unit mismatch (Q8) | `crossBusinessUnitAllocationIsRejected` |
| Allocation only while Confirmed or On Hold; reallocation in place; a failed reallocation keeps the previous one (Q9) | `onlyConfirmedOrOnHoldShipmentsCanBeAllocated`, `reallocationChangesTheAssignmentInPlace` |
| Release frees the vehicle and clears the shipment | `releaseFreesTheVehicleAndClearsTheShipment` |
| Ready for Dispatch guard, valid and invalid (Q10); the guard is in the default set | `readyForDispatchNeedsAVerifiedAllocation`, `ShipmentStatusTransitionConfigTest.deployedLifecycleBehavesAsDocumented` |
| Cancellation auto-release, once, with no recursion and without the fleet permission (Q11) | `cancellingAShipmentReleasesItsAssignmentOnce` |
| Lifecycle Planned → Active → Completed; history kept after completion (Q12, Q18) | `lifecycleKeepsHistoryAfterCompletion` |
| An old assignment never clears a newer reference (Q18) | `VehicleAssignmentTriggerHandlerTest.anOldAssignmentNeverClearsANewerReference` |
| **Direct DML and bypass attempts**: same rules without the service; permission required; release exemption not borrowable; transitions, terminal locks, Active freeze; mirror fields not writable by the Fleet Manager; trigger-only entry points refuse other callers | `VehicleAssignmentTriggerHandlerTest` (8 tests), `usersWithoutTheFleetPermissionAreDenied`, `invalidAndInvisibleRequestsAreReportedPerRecord` |
| **Bulk 200**: 10 SOQL, 2 DML; remarks-only save of 20: 0 SOQL, 1 DML | `twoHundredAllocationsInOneCall`, `aRemarksOnlySaveCostsNothing` |
| Lock timeout becomes retryable `FLEET_BUSY`, nothing saved (Q16) | `aLockTimeoutBecomesARetryableError` |

### Audit fixes (check-only validation `0Afg700000KVnYnCAL`: 190/190 tests, 54 for Phase 4)

| Scenario | Test(s) |
|---|---|
| Delete refused for the Fleet Manager (no Delete permission) and for the Administrator (trigger); the booking still blocks an overlapping allocation | `VehicleAssignmentTriggerHandlerTest.deletionIsRefusedForEveryoneAndKeepsTheBooking` |
| Completed history cannot be deleted | `completedHistoryCannotBeDeleted` |
| Undelete and delete are routed to a refusal (a real undelete cannot be produced, because nothing can be deleted) | `deleteAndRestoreAreRoutedToARefusal` |
| Ready for Dispatch → On Hold (and back to Confirmed): reallocation, release and direct DML refused | `FleetDispatchRulesTest.readyForDispatchThenOnHoldKeepsTheAllocation` |
| Dispatched / In Transit → On Hold, including the On Hold → In Transit shortcut: refused | `dispatchedOrInTransitThenOnHoldKeepsTheAllocation` |
| On Hold before dispatch: reallocation and release allowed | `onHoldBeforeDispatchStillAllowsChanges` |
| Cancellation still releases after dispatch | `cancellationStillReleasesAfterDispatch` |
| Ready for Dispatch revalidation, 10 shipments in one partial-success save: unchanged passes; weight, business unit, vehicle capacity, vehicle status, insurance, licence, driver status, maintenance and date changes each refused; nothing written | `readyForDispatchRevalidatesAgainstCurrentData` |
| Revalidation excludes the assignment itself and a non-overlapping booking of the same pair | `aValidAllocationIsNotRejectedByItself` |
| A stale window is refused; reallocating the same pair renews it | `reallocatingRenewsAStaleWindow` |
| The guard fails closed outside the shipment trigger | `theGuardFailsClosedOutsideTheShipmentTrigger` |
| Lock timeouts at the service, mirror, cancellation and guard lock points become `FLEET_BUSY` with no raw text and nothing written; retry succeeds | `FleetLockingTest` (5 tests) |
| All nine enforcement reads refuse callers outside their trigger | `FleetLockingTest.enforcementReadsRefuseCallsOutsideTheirTrigger` |

### Round 3 (check-only validation `0Afg700000KW0hJCAT`: 201/201 tests, 65 for Phase 4)

| Scenario | Test(s) |
|---|---|
| A Logistics Manager corrects an On Hold dispatched allocation; mirror updated; one Exception event naming the assignment, old and new vehicle, driver and the reason, created by the manager; Ready for Dispatch then passes | `FleetCorrectionTest.aManagerCorrectsAnOnHoldDispatchedAllocationWithHistory` |
| Fleet Manager refused (service and direct DML); blank and repeated reasons refused; a reason-less change stays locked; a release is never a correction | `correctionNeedsThePermissionAReasonAndANewReason` |
| No correction at Ready for Dispatch, Dispatched, In Transit, Delayed, Failed Delivery, or Confirmed after dispatch | `correctionIsOnlyAllowedOnHold` |
| A correction is revalidated in full (expired insurance refused) and renews a stale window | `aCorrectionIsRevalidatedInFullAndCanRenewTheWindow` |
| A correction that cannot be recorded is not saved | `aCorrectionThatCannotBeRecordedIsNotSaved` |
| A first allocation cannot carry a correction reason; the history writer is trigger-only | `aFirstAllocationCannotCarryACorrectionReason`, `correctionHistoryOnlyRunsInItsTrigger` |
| On Hold → In Transit: no assignment refused, valid accepted, invalid (inactive vehicle) refused, mismatched refused | `FleetDispatchRulesTest.onHoldToInTransitNeedsAValidMatchingAllocation` |
| Dispatched → In Transit is revalidated (driver On Leave refused, then accepted) | `dispatchedToInTransitIsRevalidatedToo` |
| Shipments with a Planned or Active assignment cannot be deleted; after cancellation the shipment deletes and the Cancelled history stays; the check is trigger-only | `VehicleAssignmentTriggerHandlerTest.aShipmentWithAnOpenAssignmentCannotBeDeleted`, `theDeletionCheckOnlyRunsInItsTrigger` |
| Ready for Dispatch behaviour unchanged | All earlier Ready for Dispatch tests pass unchanged |

Coverage after round 3:
- 100%: `VehicleAvailabilityService`, `AssignmentWindow`, both trigger handlers and both triggers.
- 90.0% to 97.1%: `ShipmentAllocationGuard` 97.1%, `FleetAllocationService` 95.0%, `VehicleAssignmentDomain` 93.9%, `FleetSelector` 90.7%, `AllocationRequest` 90.0%.
- Org-wide 96.4% (2,335 lines).

Coverage after the fixes:
- 100%: `VehicleAvailabilityService`, `AssignmentWindow`, the handler and the trigger.
- 89.9% to 97.1%: `ShipmentAllocationGuard` 97.1%, `VehicleAssignmentDomain` 95.5%, `FleetAllocationService` 94.5%, `FleetSelector` 89.9%.
- 88.9%: `AllocationRequest`.
- Org-wide 96.6% (2,220 lines).

Coverage of Phase 4 classes before the fixes:
- 100%: `VehicleAvailabilityService`, `AssignmentWindow`, `ShipmentAllocationGuard`, `VehicleAssignmentTriggerHandler`, `VehicleAssignmentTrigger`.
- `VehicleAssignmentDomain` 97.3%; `FleetAllocationService` 95.3%; `AllocationRequest` 88.9%; `FleetSelector` 87.4%.
- Org-wide 97.1% (2,005 lines).

## 7. Phase 5 scenarios (check-only validation `0Afg700000KXB1BCAX`: 229/229 tests, 28 new)

| Scenario | Test(s) |
|---|---|
| Attempt, proof, file, confirmation; trip Active then Completed; repeat confirmation refused with no event | `DeliveryServiceTest.aDeliveryWithProofAndEvidenceCompletesTheTrip` |
| Three failures on one trip, fourth attempt refused (D4); attempts numbered and keyed; no duplicate events; On Hold afterwards | `failedAttemptsRetryOnTheSameTripUpToTheLimit` |
| Proof and evidence required; nothing half-saved; second-step failure rolled back for that record only | `confirmationNeedsAProofAndEvidenceAndIsAllOrNothing`, `aFailureInTheShipmentStepLeavesNoPartialUpdate` |
| Duplicate requests, open attempt and proof already recorded | `duplicateRequestsAreRefused` |
| Access; verification once, by the manager | `accessIsEnforced`, `aManagerVerifiesADeliveredProofOnce` |
| Cancellation after dispatch (D2) | `cancellationAfterDispatchClosesTheAttemptAndCompletesTheTrip` |
| Direct DML: numbering, keys, status and transition rules, Delivered checks, history lock, two-layer field protection | `DeliveryTriggerHandlerTest` (8) |
| Shipment guards on direct DML and under override; guard fails closed outside the trigger | `shipmentDeliveryStatusesFollowTheAttempts`, `theDeliveryGuardFailsClosedOutsideTheShipmentTrigger` |
| Evidence files: no delete, unlink or new version, even for an administrator; unrelated files untouched | `ProofEvidenceProtectionTest` (3) |
| Revalidation at Dispatched; On Hold → In Transit activation; Damaged and Lost completion; Active trip holds its truck (D3); lock timeouts | `FleetLifecycleTest` (4) |
| 200 shipments started, proved and confirmed in single calls | `DeliveryBulkTest` |
| Event-key fix: the same transition repeated within one second gets its own event; positions contiguous per shipment; 50 shipments in bulk; re-fire of a save with an identity seen earlier in the same second writes nothing; legacy keys kept | `TrackingEventSequenceTest` (4); `DeliveryServiceTest.failedAttemptsRetryOnTheSameTripUpToTheLimit` (six events, alternating) |

## 4. How to run

```bash
# All local tests with coverage (the org has no other Apex)
sf apex run test --test-level RunLocalTests --code-coverage --result-format human --wait 20 --target-org eLogixDev

# Post-deploy behaviour against live configuration (rolled back)
sf apex run --file scripts/apex/verify-phase2-apex.apex --target-org eLogixDev   # expect checks=12 failures=0
```
