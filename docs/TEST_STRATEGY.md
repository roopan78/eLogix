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
