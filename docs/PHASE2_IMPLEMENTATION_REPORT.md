# eLogix ERP - Phase 2 Implementation Report

| | |
|---|---|
| Phase | 2: Apex foundation, shipment status policy, tracking, shipment trigger |
| Date | 2026-11-19 |
| Target org | `eLogixDev` (Developer Edition, source API 67.0) |
| Outcome | **Deployed and verified.** Not committed (awaiting review). |

## 1. Process followed

| Stage | What happened |
|---|---|
| A. Discovery | Done by the orchestrator without subagents, at your request. Read-only queries against the org: no Apex, triggers or labels; 46 active transitions, 3 of them permission-gated; license availability. Findings are in [APEX_ARCHITECTURE.md](APEX_ARCHITECTURE.md) section 1. |
| B. Contract | [APEX_ARCHITECTURE.md](APEX_ARCHITECTURE.md). You approved all seven decisions (D1 to D7) as recommended. |
| C/D. Implementation | Single pass by the orchestrator (decision D7): 20 production classes, 1 trigger, 18 labels, 13 test classes. |
| E. Quality review | Self-review against the contract and the CLAUDE.md principles. Coverage review found one untested business path (On Hold reason mapping); a test was added before the real deploy. |
| F. Deployment | Model validator, then two check-only deploys, then one real deploy. Detail in section 3. |

## 2. Files

### Created

| Path | Content |
|---|---|
| `force-app/main/default/classes/base/` | `TriggerHandler`, `ELogixException`, `ValidationException`, `ConfigurationException`, `AuthorizationException`, `ServiceResult` |
| `force-app/main/default/classes/common/` | `Logger`, `ExceptionHandler`, `PermissionService`, `SettingsService` |
| `force-app/main/default/classes/shipment/` | `ShipmentStatusPolicy`, `ShipmentStatusGuard`, `ShipmentItemsRequiredGuard`, `ShipmentDomain`, `ShipmentService` |
| `force-app/main/default/classes/tracking/` | `TrackingService`, `TrackingEventRequest` |
| `force-app/main/default/classes/selectors/` | `ShipmentSelector`, `TrackingEventSelector` |
| `force-app/main/default/classes/handlers/` | `ShipmentTriggerHandler` |
| `force-app/main/default/classes/test/` | `TestDataFactory` and 12 test classes ([APEX_TEST_MATRIX.md](APEX_TEST_MATRIX.md)) |
| `force-app/main/default/triggers/` | `ShipmentTrigger` (before and after insert and update) |
| `force-app/main/default/labels/CustomLabels.labels-meta.xml` | 18 labels (hand-maintained) |
| `scripts/apex/verify-phase2-apex.apex` | Post-deploy behaviour check, 12 checks, rolled back |
| `docs/APEX_ARCHITECTURE.md` | Architecture contract, now marked approved and implemented, with a deviations section |
| `docs/APEX_FRAMEWORK.md`, `docs/SHIPMENT_POLICY_IMPLEMENTATION.md`, `docs/TRACKING_IMPLEMENTATION.md`, `docs/APEX_TEST_MATRIX.md`, this report | Phase 2 documentation |

Each `.cls` and `.trigger` file has a `-meta.xml` with API version 67.0.

### Changed

| Path | Change |
|---|---|
| `PROJECT_STATUS.md` | Phase 2 report and status |
| `docs/SOLUTION_ARCHITECTURE.md` | Status, Apex structure as built, Phase 2 marked done |
| `docs/SHIPMENT_LIFECYCLE.md` | Enforcement is live; override limits (D1, D2); guard phases |
| `docs/BUSINESS_RULES.md` | Shipment rules owned by Apex are now "Live, tested (P2)" |
| `docs/TEST_STRATEGY.md` | Phase 2 results section |
| `docs/DEPLOYMENT_GUIDE.md` | Phase 2 deploy history, test level, labels ownership, verification script |

### Not changed

No Phase 1 metadata was touched. Objects, fields, validation rules, CMDT, permission sets, layouts and the app are as committed. The model validator confirms the generator would write the same set, and `git status` shows no changes under `objects/`, `permissionsets/`, `customMetadata/` or `layouts/`.

## 3. Deployment results

| Step | ID | Result |
|---|---|---|
| `npm run metadata:validate` | n/a | Model validation passed |
| Check-only deploy, `RunLocalTests` | `0Afg700000KO3IzCAL` | Succeeded: 674/674 components, 76/76 tests, coverage 97.2% |
| Check-only deploy after adding one test | `0Afg700000KM5omCAD` | Succeeded: 674/674 components, 77/77 tests, coverage 97.5% |
| **Deploy, `RunLocalTests`** | **`0Afg700000KNnfeCAD`** | **Succeeded: 674/674 components, 77/77 tests, coverage 97.5% (621/637), completed 2026-11-19 09:49 UTC** |

There were no deployment or compile errors at any step.

## 4. Verification results

| Check | Result |
|---|---|
| Org inventory (Tooling API) | 33 Apex classes, `ShipmentTrigger` active, 18 custom labels |
| `verify-phase2-apex.apex` (live config, as admin, rolled back) | **12/12 pass**: 46 active transitions; override permission present; Created event on insert; keyed Requested event; cancellation reason in remarks; override cannot reopen Cancelled; override writes an Exception event; override cannot reverse Delivered; item guard applies under override; roll-up re-fire writes no event; operational event updates the summary; no rows left |
| `verify-phase1-metadata.apex` (Phase 1 regression) | **19/19 pass** with the trigger active; currency INR, time zone Asia/Kolkata |
| Data left behind | 0 shipments in the org after both scripts |

## 5. Completion criteria

| Criterion | Status | Evidence |
|---|---|---|
| Framework compiles | Met | Deploy `0Afg700000KNnfeCAD` |
| Policy reads the deployed CMDT | Met | `ShipmentStatusTransitionConfigTest` (4 tests), smoke check 1 |
| Tracking works | Met | 13 `TrackingServiceTest` tests plus the trigger tests; smoke checks |
| Trigger works | Met | 16 `ShipmentTriggerHandlerTest` tests |
| All tests pass | Met | 77/77 |
| Bulk tested | Met | 200-row insert and update (1 query and 2 DML each); 200-row partial success; 100 operational events (2 queries) |
| Invalid transitions rejected | Met | Policy unit tests, trigger tests, smoke |
| Transaction integrity verified | Met | `trackingFailureRollsBackTheStatusChange` (all-or-none and partial), re-entry test |
| Security reviewed | Met, with notes | Section 6 |
| Phase 1 not broken | Met | Phase 1 script 19/19 |
| Docs updated | Met | Section 2 |
| Deployment verified | Met | Sections 3 and 4 |

## 6. Security review

| Area | Result |
|---|---|
| Sharing declarations | Rule classes are `with sharing`; utilities and selectors are `inherited sharing`. Two private inner classes are `without sharing`, each justified in [APEX_ARCHITECTURE.md](APEX_ARCHITECTURE.md) section 6.1 and covered by tests. |
| CRUD/FLS | User-initiated reads and writes use user mode: `ShipmentSelector` (`WITH USER_MODE`) and `ShipmentService` (`AccessLevel.USER_MODE`). `recordEvents` checks create access on `Tracking_Event__c`. System mode is used only to write protected fields, after authorization. |
| Custom permissions | Checked through `PermissionService` (no static caching). Proven with real assignments for Operations Executive, Logistics Manager and Sales Executive. |
| Validation rules | Never bypassed by code. Override users still hit validation rules (for example, Delivered needs `Actual_Delivery_Date__c`). |
| Logging | No field values or payloads; exceptions are logged by type, code and stack trace only. |
| Hardcoded IDs | None. Users and permission sets are looked up by name in tests. |
| Bypass switches | None. There is no trigger bypass and no "skip policy" flag. |

## 7. Known issues and limitations

1. **Code comment in `ShipmentService.changeStatus`: corrected locally during the pre-commit review, not yet deployed.** The comment above the catch block had said user-mode DML *throws* when access is missing. In `userWithoutEditAccessCannotChangeStatus`, a Sales Executive without edit access got a row error instead, and the catch branch was never reached. The comment now describes that behaviour and calls the catch defensive. Only the comment changed; the org copy differs from the repository by those comment lines until the next deploy.
2. `TrackingService.recordEvents`: the rollback branch for a failed summary update is not exercised by a test. It is reachable in production and can be tested without a failure switch; see section 9 and [APEX_TEST_MATRIX.md](APEX_TEST_MATRIX.md) section 3.
3. Ready for Dispatch and Dispatched guards are deferred to Phases 4 and 5 (decision D3). Until then, Confirmed → Ready for Dispatch needs no allocation.
4. Logging goes to the debug log only (decision D4).
5. Prettier with `prettier-plugin-apex` was not run (`node_modules` is not installed). The code follows the repo's `.prettierrc` style by hand, so the pre-commit hook may reformat it once dependencies are installed. Two docs were reformatted on disk during the session, likely by an editor formatter; the content was kept.
6. Automated users (integration user, Automated Process) hold no custom permissions. A future integration that needs gated transitions must be given the permission set explicitly.

## 8. Next phase (not started)

Phase 3: `FreightCalculationService`, rate card selection and the quotation service. It is the first consumer of `SettingsService` (`Default_Tax_Percent`, `Quotation_Validity_Days`, `Max_Discount_Percent_No_Approval`). It does not start until you approve.

## 9. Pre-commit review findings (2026-11-19)

Review scope: the full working-tree diff, the two `without sharing` classes, the documentation formatting changes and the untested branch.

### 9.1 Security

| # | Finding | Severity | Status |
|---|---|---|---|
| S1 | **`TrackingService.Writer` (`without sharing`, system mode)** writes only (a) tracking events built by the service itself and (b) `Latest_Location__c` / `Latest_Tracking_Timestamp__c` on shipments. It never writes `Status__c` or any other shipment field. A summary update still fires `ShipmentTrigger`, so the lifecycle policy and validation rules still run. It is reachable only from `recordStatusEvents`, called by the trigger after a permitted shipment save, and from `recordEvents`, after the create-access check on `Tracking_Event__c` and a user-mode read of every shipment. | n/a | Intended. Deviation from the approved contract, documented in APEX_ARCHITECTURE section 6.1 |
| S2 | **`TrackingEventSelector.KeyLookup` (`without sharing`)** returns only key strings for keys the caller supplies. Without it, a duplicate on an event the user cannot see would surface as a DUPLICATE_VALUE insert error, and that message contains the other record's Id. Seeing all keys therefore exposes less than the alternative. Residual effect: a caller replaying an external id that already exists on another shipment learns that the event exists, and their request is skipped. External ids are scoped per source system (`EXT:{source}:{id}`), so collisions mean the same provider message. | Low | Accepted |
| S3 | **`recordStatusEvents` is `public` and trusts its inputs.** Apex code calling it with fabricated old and new records could write status history for a shipment that never changed, without sharing. There is no external entry point today: no `@AuraEnabled` method, REST resource, invocable method or `global` member exists. Only users who can author Apex can reach it, and they already have system-level reach. | Medium (latent) | **Open.** Recommended fix before Phase 6 or 7: make the method accept calls only in the shipment trigger context. One option is to move status-event creation behind a guard on `Trigger.isExecuting` and `Trigger.new`, and rework `reEntryWithTheSameVersionDoesNotDuplicateEvents` to drive it through the handler. This needs a code change and a deploy, so it waits for your approval. |
| S4 | `recordEvents` locks shipments with `FOR UPDATE`. Under heavy concurrent pings on one shipment, a lock wait timeout surfaces as an uncaught `QueryException` from `recordEvents` and is not converted into a per-request result. | Low | Open; revisit with the GPS integration (Phase 6) |
| S5 | No hardcoded record Ids, usernames, credentials or tokens in any changed file. Test users use `example.com` emails and random usernames. | n/a | Verified by scan |

### 9.2 Robustness risk found during review

- `recordEvents` updates every shipment summary in one all-or-nothing statement. If a single shipment in the batch fails its validation rules, the events for **every** shipment in that batch are rolled back and reported as `OPERATION_FAILED`.
- This is consistent (nothing is half-written), but one bad record blocks a whole GPS batch.
- Recommended for Phase 6: update summaries with partial success, and drop only the events of shipments whose summary failed.

### 9.3 Rollback branch reachability

The branch is reachable through supported paths: validation rules run on the system-mode summary update. It is testable without a failure switch (see APEX_TEST_MATRIX section 3). Proposed test for the next deploy: `TrackingServiceTest.summaryFailureRollsBackEvents`.

### 9.4 Documentation formatting

- `APEX_ARCHITECTURE.md` and `TRACKING_IMPLEMENTATION.md` were reformatted on disk by an editor while the session was running; this mostly re-padded tables.
- Both files are new and untracked, so git has no earlier version to diff against. Instead, all six new docs were compared, line by line with whitespace ignored, against the content written in this session.
- Result: no lines added, none lost. The only content difference is the intended "illustrative Id" wording.

### 9.5 Validation after the comment correction

- `npm run metadata:validate`: passed, and wrote nothing.
- `sf apex run test --test-level RunLocalTests` (test run `707g700001C32Pi`): 77 of 77 test methods passed. The CLI reports 81 because it also counts the 4 `@TestSetup` methods. Org-wide coverage is 97%.
- These tests ran against the deployed code. The local change is comment-only, so behaviour is identical.
