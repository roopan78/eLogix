# eLogix ERP - Phase 3 Implementation Report (Pricing and Quotation)

| | |
|---|---|
| Phase | 3: freight calculation, rate card selection, quotations, approval, conversion to shipment |
| Date | 2026-11-19 |
| Baseline | `feature/phase-2-apex-foundation` at `90751c6` |
| Outcome | **Deployed and verified, including follow-ups A1 to A3 (deploy `0Afg700000KRt9mCAD`) and A4 (deploy `0Afg700000KRUWMCA5`). Not committed** (awaiting your review). |

## 1. Process

| Step | Result |
|---|---|
| Discovery and plan | [PHASE3_PLAN.md](PHASE3_PLAN.md); your decisions Q1 to Q22 are recorded in its section 0 |
| Model change (Q14, Q18) through the generator, validated and deployed separately | Check-only `0Afg700000KOurxCAD` (55/55, 79/79 tests); **deploy `0Afg700000KOim0CAD`** (55/55, 79/79 tests). Phase 1 script 19/19 and Phase 2 script 12/12 afterwards. |
| Apex implementation | 10 production classes, 1 trigger, 27 labels, 4 test classes (53 tests), `TestDataFactory` builders |
| Check-only deploys | 5 runs. Runs 1 to 4 found only test defects (section 6); **run 5 `0Afg700000KREzSCAX`: 717/717, 132/132 tests** |
| Deploy | **`0Afg700000KRoekCAD`**: 717/717 components, 132/132 tests, coverage 97.2% (1,268/1,304), completed 2026-11-19 17:41 UTC |
| Verification | Phase 1 script 19/19, Phase 2 script 12/12, **Phase 3 script 18/18**; no rows left behind |

## 2. Files

### Created

| Path | Content |
|---|---|
| `classes/pricing/` | `FreightCalculationService`, `FreightRequest`, `FreightBreakdown` |
| `classes/crm/` | `QuotationService`, `QuotationDomain` |
| `classes/handlers/QuotationTriggerHandler` | Routes quotation trigger contexts |
| `classes/selectors/` | `RateCardSelector`, `ShipmentRequestSelector`, `QuotationSelector` |
| `triggers/QuotationTrigger` | Single quotation trigger |
| `classes/test/` | `FreightCalculationServiceTest` (17), `QuotationServiceTest` (17), `QuotationTriggerHandlerTest` (12), `QuotationConversionTest` (7) |
| `objects/Quotation__c/fields/Taxable_Line_Total__c` | Q14 roll-up (generated) |
| `objects/Quotation_Line__c/validationRules/QTL_Locked_Unless_Draft` | Q18 line lock (generated) |
| `scripts/apex/verify-phase3-pricing.apex` | 18 rolled-back checks against live configuration |
| `docs/PHASE3_PLAN.md`, `docs/PRICING_IMPLEMENTATION.md`, this report | Documentation |

### Modified

| Path | Change |
|---|---|
| `scripts/node/model/elogix-datamodel.mjs` | Q14: `Taxable_Line_Total__c` roll-up; `Tax_Amount__c` and `Total_Amount__c` formulas honour `Is_Taxable__c` and never tax below zero |
| `scripts/node/model/elogix-validation.mjs` | Q18: `QTL_Locked_Unless_Draft` |
| Generated metadata | `Tax_Amount__c` and `Total_Amount__c` formulas; Quotation layout (new field); read-only FLS for the new field in the 6 permission sets that can read quotations; `docs/generated/DATA_MODEL_CATALOGUE.md` |
| `labels/CustomLabels.labels-meta.xml` | 27 labels added; the 18 existing labels are unchanged |
| `classes/test/TestDataFactory.cls` | Route, rate card and request builders; `idsOf`; constants |
| `scripts/apex/verify-phase1-metadata.apex` | Its quotation check now follows the Phase 3 rules (request Submitted, rate card set). The checked totals are unchanged (10,500 / 1,260 / 11,760). |
| Docs | `PROJECT_STATUS`, `APEX_TEST_MATRIX`, `BUSINESS_RULES`, `API_SPECIFICATION`, `SOLUTION_ARCHITECTURE`, `DATA_MODEL`, `DEPLOYMENT_GUIDE`, `TEST_STRATEGY`, `DEMO_SCRIPT`, `AUTOMATION_DESIGN` |

### Not changed

No Phase 2 production class was modified; the Phase 2 tests pass unchanged. The only Phase 1 metadata changes are the two you approved (Q14 and Q18), made through the generator.

## 3. Test results

132/132 tests pass (79 from Phase 2 + 53 from Phase 3).

| Class | Coverage |
|---|---|
| `QuotationDomain`, `QuotationTriggerHandler`, `QuotationTrigger`, `RateCardSelector`, `ShipmentRequestSelector`, `FreightBreakdown` | 100% |
| `FreightCalculationService` | 99.3% |
| `QuotationService` | 92.2% |
| `QuotationSelector` | 90.9% |
| **Phase 3 classes combined** | **96.0% (631/657)** |
| Org-wide | 97.2% |

Scenario list: [APEX_TEST_MATRIX.md](APEX_TEST_MATRIX.md) section 5.

## 4. Acceptance criteria (PHASE3_PLAN section 7)

| # | Criterion | Status | Evidence |
|---|---|---|---|
| 1 | Reference lane equals the hand calculation; formula total equals the breakdown | Met | `referenceLaneComponents`, `createsPricedDraftQuotation...`, live script checks 3 to 6 |
| 2 | Deterministic selection; ambiguity and absence fail closed | Met | `specificityBeatsPriority`, `priorityThenLatest...`, `equalTopCandidatesFailAsAmbiguous`, `ineligibleCardsAreIgnored` |
| 3 | No hardcoded pricing | Met | Settings and cards drive every value; `thresholdComesFromConfiguration`, `missingTaxSettingFailsClosed`, `recalculateRepricesDraftQuotationsOnly` |
| 4 | Above the threshold, no Sent or Accepted without a stamp, on any path | Met | `aboveThresholdCannotBeApproved...`, `theStampCannotBeFabricated` (two layers), live script |
| 5 | Only non-owner approvers approve | Met | `managerApprovalWritesAVerifiedStamp`, `ownersCannotApprove...`, `approvalNeedsThePermission` |
| 6 | Bulk 200: 3 SOQL create, 1 SOQL pricing; none in loops | Met (measured) | Create 3 SOQL / 2 DML; pricing 1 SOQL / 0 DML; conversion 3 SOQL / 3 DML; no-change save 0 SOQL / 1 DML |
| 7 | Per-record failures never roll back others | Met | `aRequestThatCannotMoveFailsOnlyItsOwnQuotation`, `aFailedRequestUpdateRemovesOnlyItsOwnShipment`, `requestProblemsAreReportedPerRecord` |
| 8 | All tests pass; at least 85% on new classes; Phase 1 and 2 scripts pass | Met | 132/132; 96.0%; 19/19 and 12/12 |
| 9 | Phase 1 metadata unchanged except the approved Q14/Q18 changes | Met | `git diff` limited to the generated Q14/Q18 files |

## 5. Security review

| Area | Result |
|---|---|
| Protected fields | Price components, `Rate_Card__c`, `Tax_Percent__c` and the approval stamp are written only by `QuotationService` in system mode, after describe and permission checks and a user-mode read. Shipment `Freight_Amount__c` is written the same way on conversion. |
| Approval stamp | Verified by the trigger, not trusted. Tests prove that a Sales user is blocked by FLS, and that an administrator-level user with field access is blocked by the trigger: wrong approver, no transition, self-approval, backdating, clearing. |
| Discount bypass | Header discount, components, lines (insert, update, delete) and status label changes are all covered on direct DML. |
| `without sharing` | Two private inner writers, a documented deviation from the plan's "none" ([PHASE3_PLAN.md](PHASE3_PLAN.md) section 0.1, item 2; [PRICING_IMPLEMENTATION.md](PRICING_IMPLEMENTATION.md) section 5). The trigger-side writer uses the Phase 2 F1 pattern: it reads `Trigger.new` itself and refuses other callers (tested). |
| External surface | None added: no `@AuraEnabled`, REST, invocable or `global` members. |
| Logging | Ids, codes and counts only. |

## 6. Issues found and fixed during check-only deploys (tests only)

1. **FLS is enforced on DML in this org's test context.** Tests that wrote protected fields as a Sales user were stopped by FLS before reaching the trigger. They now prove both layers: Sales is refused, and an `eLogix_Administrator` user with field access is refused by the trigger with the exact labels.
2. **New rate cards default to Region = South** (the value-set default). The bulk pricing test now uses region South. The behaviour is documented as a configuration note; see section 7.
3. **The org's standard duplicate rules** blocked a second look-alike test account. The test now uses a distinct customer.
4. `Assert` methods reject a null message; a test now passes a non-null one.
5. Small coverage tests were added for empty-input selector paths and the handler test seam.

No production code defects were found by the test runs.

## 7. Known issues and limitations

1. **Region default on rate cards.** `Rate_Card__c.Region__c` defaults to South, so cards are South-specific unless cleared. Option for Phase 9 or a small model change: give `Rate_Card__c.Region__c` an object-local picklist without a default.
2. **Narrow `without sharing` writers** (approval, request status, conversion compensation) are needed until Phase 9 roles give managers edit access through the hierarchy. They should be revisited then.
3. **Conversion requires shipment create access plus visibility of the quotation.** In Phase 3 that means Logistics Manager or Administrator. Operations cannot see Sales-owned quotations until Phase 9 sharing, and Sales has read-only shipment access.
4. **Rejection reason** is appended to `Notes__c`. There is no separate rejection field (none exists in the model).
5. **The message for a request-update failure on conversion** is the request's validation-rule text, reported against the quotation.
6. Revisions (`Version__c`, `Superseded`) and scheduled expiry are deferred, as decided.
7. Prettier has still not been run (dependencies not installed), as in Phase 2.
8. **A5, customer rejection (known limitation):** When the customer rejects a quotation (Sent → Rejected), its shipment request stays at `Quoted`. Re-quoting is deferred (decisions Q3, Q21), so that request has no further path in Phase 3. This is accepted as a known limitation, to be addressed when quotation revisions are implemented. No revision logic and no request-status change were added.

## 8. Next phase (not started)

Per the phase plan: Phase 4 (fleet allocation), or Phase 5 (inventory, delivery, invoicing, and the Flows, including the Quotation Approval Flow, which will call `QuotationService.approve` and `reject`). Nothing starts without your approval.

## 9. Pre-commit security audit follow-up (A1 to A3)

The read-only audit after the deploy found one medium and two low issues. All three are fixed, tested and deployed.

| # | Finding | Fix | Test |
|---|---|---|---|
| A1 (medium) | `Quotation__c.Shipment_Request__c` is a required lookup, so permission sets cannot restrict it, and the lock only applied after Draft. A Draft quotation could be re-pointed to another request: the price was calculated for one request but attached to another, and their statuses diverged. | `QuotationDomain`: the request link cannot change after creation, in any status, for any user. New label `eLogix_Quotation_Request_Immutable`. | `aQuotationCannotBeMovedToAnotherRequest` (Sales in Draft and after Draft; administrator); live script check 6 |
| A2 (low) | The self-approval check compared the approver against the new owner only, so changing the owner and approving in one save could get around it. Only a user with field access to the stamp (an administrator) could try. | The stamp is valid only if the approver owns the quotation neither before nor after the save. The existing permission, transition and running-user checks are unchanged. | `anOwnerChangeCannotHideASelfApproval`: the combined save is rejected with the stamp message and nothing changes; the owner change on its own still succeeds, which shows the rejection came from the stamp rule |
| A3 (low) | Conversion took the request status from the unlocked quotation read, so a concurrent change (for example Cancelled) could be overwritten with Converted. | `ShipmentRequestSelector.selectStatusForUpdate` (user mode, `FOR UPDATE`) locks the requests after the quotations, the same lock order as the quotation trigger. The status is re-read under the lock and must still be Approved. No new `without sharing` code. | `aRequestChangedBeforeConversionIsNotOverwritten` (per-record: the other quotation converts). A true concurrent race cannot be produced in a single-threaded Apex test; the test proves the decision uses the locked, current status. |

### 9.1 Results

| Step | ID | Result |
|---|---|---|
| `git diff --check`, model validator | n/a | Clean; passed |
| Check-only + `RunLocalTests` | `0Afg700000KQcR8CAL` | Succeeded: 718/718, 135/135 tests |
| **Deploy + `RunLocalTests`** | **`0Afg700000KRt9mCAD`** | **Succeeded: 718/718, 135/135 tests, coverage 97.6% (1,287/1,318); Phase 3 classes 96.9%** |
| Verification scripts | n/a | Phase 1 **19/19**, Phase 2 **12/12**, Phase 3 **19/19** (A1 check added); no rows left behind |
| Org vs repository | n/a | All 48 Apex classes and triggers identical |

Bulk conversion of 200 now costs 4 SOQL (one more for the request lock) and 3 DML.

### 9.2 Updated audit position

- **A1 to A3:** closed.
- **A4 (`Valid_Until__c` still editable after Draft):** open, for your decision.
- **A5 (a request whose quotation the customer rejected stays at Quoted):** open, until revisions are introduced.
- **Two-step administrator path:** with Modify All, an administrator can still transfer a quotation away and approve it in a later, separate save. That is within administrator authority and is not a self-approval in the same save.
- **Temporary writers:** the narrow `without sharing` writers are unchanged and remain to be revisited with Phase 9 roles.

## 10. Follow-up A4 and A5 (approved 2026-11-19)

| # | Change | Test |
|---|---|---|
| A4 | `Valid_Until__c` was added to the fields `QuotationDomain` locks once a quotation leaves Draft. It is editable in Draft, locked in Pending Approval, Approved, Sent and Accepted, and editable again when a rejected approval returns the quotation to Draft. Creation still sets today + `Quotation_Validity_Days`. The lock label now reads "...its charges, discount, lines and validity date cannot be changed." | `validityIsLockedOnceTheQuotationLeavesDraft` (all five statuses and the return to Draft). `onlyAcceptedValidQuotationsConvert` was reworked: it used to back-date an accepted quotation to simulate expiry, which A4 now forbids, and it now asserts that the back-dating is refused. The expiry branch of `convertToShipment` guards real elapsed time, which a single Apex test cannot produce. |
| A5 | No change, as decided. Documented as a known limitation (section 7, item 8). | n/a |

| Step | ID | Result |
|---|---|---|
| Model validator, `git diff --check` | n/a | Passed; clean |
| Check-only + `RunLocalTests` | `0Afg700000KRMCFCA5` | Succeeded: 718/718, 136/136 tests |
| **Deploy + `RunLocalTests`** | **`0Afg700000KRUWMCA5`** | **Succeeded: 718/718, 136/136 tests, coverage 97.6% (1,287/1,318); Phase 3 classes 96.9% (650/671)** |
| Verification scripts | n/a | Phase 1 **19/19**, Phase 2 **12/12**, Phase 3 **19/19**; no rows left behind |
| Org vs repository | n/a | All 48 Apex classes and triggers identical |

The audit position is now: A1 to A4 closed; A5 accepted as a known limitation.
