# eLogix ERP - Test Strategy

## 1. Levels

| Level | Tool | Scope | From phase |
|---|---|---|---|
| Model validation | `npm run metadata:validate` | Static checks before any deploy: field references in formulas and rules, picklist values in `ISPICKVAL`, `$Permission` names, relationship names, permission-set dependencies, transition integrity (terminal statuses, no re-dispatch), percent-field misuse | 1 |
| Check-only deploy | `sf project deploy start --dry-run` | Full platform compile and validation without saving | 1 |
| Metadata behaviour | `scripts/apex/verify-phase1-metadata.apex` | Roll-ups, formulas, validation rules, unique keys and custom metadata exercised in the org; everything rolled back | 1 |
| Apex unit tests | `sf apex run test` | Every service, policy and handler; positive, negative, bulk (200 records), permission and rollback scenarios | 2 |
| LWC Jest | `npm run test:unit` | Reusable components and key interactions (requires `npm install`) | 7 |
| End-to-end | Scripted demo run | Request → quote → shipment → allocate → dispatch → deliver → invoice → pay → return | 9 |

## 2. Apex test standards (from Phase 2)

- No `SeeAllData=true`. A `TestDataFactory` builds valid graphs using business keys.
- Tests assign the eLogix permission set of the persona under test (`System.runAs`) to prove CRUD, FLS and custom permissions, not just logic.
- Every rule in [BUSINESS_RULES.md](BUSINESS_RULES.md) owned by Apex has at least one passing and one failing test.
- Bulk tests use 200 records per transaction and assert governor usage stays bounded.
- Coverage target is at least 85% of implemented functionality, and tests must assert outcomes, not just execute lines.

## 2a. Phase 2 results (2026-11-19, `eLogixDev`)

- **Apex tests:** 77 of 77 passed in deploy `0Afg700000KNnfeCAD` (`RunLocalTests`). Code coverage is 97.5% (621 of 637 lines). The scenario-by-scenario list is in [APEX_TEST_MATRIX.md](APEX_TEST_MATRIX.md).
- **Post-deploy behaviour:** `scripts/apex/verify-phase2-apex.apex` passed 12 of 12 checks against live configuration as the admin user, including override and hard rules. Everything was rolled back.
- **Phase 1 regression:** `verify-phase1-metadata.apex` passed 19 of 19 checks with the shipment trigger active.

- **Follow-up F1 to F3 (deploy `0Afg700000KOZcDCAX`):** 79 of 79 tests passed; coverage 98.5%. Both verification scripts passed again: 12/12 and 19/19.

## 2b. Phase 3 results (2026-11-19, `eLogixDev`)

- **Apex tests:** 132 of 132 passed in deploy `0Afg700000KRoekCAD` (79 from Phase 2, 53 from Phase 3). Phase 3 classes have 96.0% coverage; the org has 97.2%. Scenarios are in [APEX_TEST_MATRIX.md](APEX_TEST_MATRIX.md) section 5.
- **Two-layer security tests:** in this org, field-level security is enforced on DML even in test context, so direct writes to protected fields are proven blocked twice: by FLS for a Sales user, and by the trigger for an administrator-level user with field access.
- **Verification scripts:** Phase 1 19/19, Phase 2 12/12, Phase 3 18/18.
- **Follow-up A1 to A3 (deploy `0Afg700000KRt9mCAD`):** 135 of 135 tests passed (3 new), coverage 97.6%; verification scripts Phase 1 19/19, Phase 2 12/12, Phase 3 19/19 (one A1 check added).
- **Follow-up A4 (deploy `0Afg700000KRUWMCA5`):** 136 of 136 tests passed (1 new; the conversion validity test was reworked), coverage 97.6%; verification scripts 19/19, 12/12 and 19/19.

## 2c. Phase 4 results (2026-11-20, `eLogixDev`, check-only)

- **Apex tests:** check-only validation `0Afg700000KSngbCAD` ran 173 of 173 tests and all passed: 136 from Phases 2 and 3, and 37 from Phase 4. Phase 4 classes have 87% to 100% coverage; the org has 97.1%. Scenarios are in [APEX_TEST_MATRIX.md](APEX_TEST_MATRIX.md) section 6.
- **Regression adjustment:** `ShipmentStatusTransitionConfigTest.deployedLifecycleBehavesAsDocumented` now builds the policy with the item guard only, because in-memory records cannot hold an assignment. It also asserts that the default guard set includes `ShipmentAllocationGuard`.
- **Verification scripts:** Phase 1 19/19, Phase 2 12/12 and Phase 3 19/19 passed against the org, which still runs the Phase 3 code. `verify-phase4-fleet.apex` (15 checks) needs the Phase 4 classes and runs after deployment.
- **Audit fixes (validation `0Afg700000KVnYnCAL`):** 190 of 190 tests passed, 17 of them new: `FleetDispatchRulesTest` 8, `FleetLockingTest` 6, and 3 delete/undelete tests in `VehicleAssignmentTriggerHandlerTest`. Org coverage is 96.6%. Phase 1, 2 and 3 scripts: 19/19, 12/12, 19/19 (the Phase 3 run was repeated once after a network DNS failure). Lock contention cannot be produced in Apex tests, so every lock point is made to time out through the selector seam.
- **Round 3 (validation `0Afg700000KW0hJCAT`):**
  - **Tests:** 201 of 201 passed, 11 of them new: `FleetCorrectionTest` 7, `FleetDispatchRulesTest` +2 (In Transit), `VehicleAssignmentTriggerHandlerTest` +2 (shipment deletion).
  - **Coverage:** 96.4% org-wide.
  - **Earlier attempts:**
    - `0Afg700000KVyIvCAL` failed on deploy: a custom permission description over 255 characters, which the model validator does not check.
    - `0Afg700000KVydtCAD` ran 200 of 201 tests: one test exceeded 100 queries walking shipments one at a time, and was rewritten to move them in bulk.
  - **Verification scripts:** Phase 1 19/19, Phase 2 12/12, Phase 3 19/19.
- **Found during validation:** enforcement reads applied the caller's sharing, so the quoted-vehicle-type rule was skipped for a Fleet Manager. Fixed with a `without sharing` reader; the test now proves the precondition.

## 2d. Phase 5 results (2026-11-20, `eLogixDev`, check-only)

- **Apex tests:** 225 of 225 passed in validation `0Afg700000KWxZJCA1`, 24 of them new; coverage 95.33%. Scenarios are in [APEX_TEST_MATRIX.md](APEX_TEST_MATRIX.md) section 7.
- **Earlier tests changed (test data only):** one Phase 2 test now builds a real delivery, because guards apply under override; Phase 4 tests drive the lifecycle through shipment statuses.
- **Verification scripts against the Phase 4 org:** Phase 1 19/19, Phase 3 19/19, Phase 4 20/20, Phase 2 11/12 (the changed check needs Phase 5 deployed). The Phase 5 script runs after deployment.
- **Event-key fix (validation `0Afg700000KXB1BCAX`, 229/229, coverage 95.34%):** status-event keys carry a per-shipment sequence, so the same transition repeated within one second is recorded once per save. Re-fired triggers still record nothing twice. Tests: `TrackingEventSequenceTest` (4).

## 3. Phase 1 results (2026-11-19, `eLogixDev`)

**Model validation.** It passes. Three deliberately injected faults (an unknown cross-object field, a misspelled picklist value and a broken View All dependency) were each reported by the validator.

**Check-only deploy.** 621/621 components, 0 errors.

**Metadata behaviour script.** 19 checks, 0 failures:

| Check | Result |
|---|---|
| `ACC_Customer_Mandatory_Info` rejects a customer without address and phone | Pass |
| `SR_Customer_Must_Be_Active` rejects a request for an inactive customer | Pass |
| Request Auto Number and default status (`SR-…`, Draft) | Pass |
| `SR_Delivery_After_Pickup` | Pass |
| Quotation totals: lines 500, subtotal 10,500, tax 12% = 1,260, total 11,760, cross-object customer name | Pass |
| `QTL_Amount_Sign_Matches_Type` | Pass |
| `SHP_Weight_Must_Be_Positive` | Pass |
| Shipment roll-ups (2 items, 1,200 kg, 240,000 declared value, 750 extra charges); `Is_Delayed__c` true; `Is_Billable__c` false | Pass |
| `TE_Events_Are_Immutable` | Pass |
| Vehicle `Open_Maintenance_Count__c` = 1 (Completed and Cancelled excluded by a multi-value roll-up filter); `Is_Allocatable__c` | Pass |
| `STK_Reserved_Within_Available` | Pass |
| Inventory net / below-reorder / stock value formulas; warehouse roll-ups | Pass |
| Invoice: subtotal 10,750, tax 1,290, total 12,040, paid 5,000 (Pending payment excluded), balance 7,040 | Pass |
| Duplicate `Invoice_Key__c` rejected | Pass |
| `RET_Approval_Before_Pickup` | Pass |
| Rate card with 12% fuel surcharge accepted; `Is_Currently_Effective__c` true | Pass |
| `RC_Percentages_In_Range` rejects 150% | Pass |
| 46 active transition records; `Default_Tax_Percent` = 12 readable from Apex | Pass |

**Defect found and fixed during verification.** The first run failed the quotation check: tax was 12.60 instead of 1,260. Percent fields are fractions inside formulas, so `Tax_Percent__c / 100` divided twice, and three percent range rules compared against 100 instead of 1. The formulas and rules were fixed and redeployed, and the generator now rejects that pattern.

**Not run:** Apex unit tests (no Apex exists yet), LWC Jest (no components; `node_modules` not installed), and per-role login tests (Phase 9).
