# eLogix ERP - Project Status

|               |                                                                                                                                                                                                                                                                                               |
| ------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Last updated  | 2026-11-20                                                                                                                                                                                                                                                                                    |
| Current phase | **Phase 8 - Analytics.** Report types, 19 reports and 5 dashboards implemented locally, awaiting check-only validation. See [docs/ANALYTICS_IMPLEMENTATION.md](docs/ANALYTICS_IMPLEMENTATION.md). Phase 7 screens are implemented ([docs/LWC_IMPLEMENTATION.md](docs/LWC_IMPLEMENTATION.md)). |
| Next phase    | Phase 9 (seed data, roles and sharing, E2E regression, demo), after Phase 8 is validated, deployed and accepted                                                                                                                                                                               |
| Target org    | `eLogixDev` - Developer Edition, instance API 68.0, source API 67.0                                                                                                                                                                                                                           |

## Phase plan

| Phase | Scope                                                                                                                                                                                            | Status                                                                                                                                        |
| ----- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ | --------------------------------------------------------------------------------------------------------------------------------------------- |
| 1     | Project inspection, architecture docs, data model, security, configuration and app metadata                                                                                                      | **Done - deployed and verified**                                                                                                              |
| 2     | Apex foundation (trigger handler, result/exception pattern, logger, settings and permission services, selectors), `ShipmentStatusPolicy`, `ShipmentService`, `TrackingService`, triggers, tests  | **Done - deployed and verified** (`0Afg700000KNnfeCAD`, 77/77 tests, 97.5% coverage). Commit pending your review.                             |
| 3     | `FreightCalculationService`, rate card selection, quotation service, tests                                                                                                                       | **Done - deployed and verified** (`0Afg700000KRUWMCA5` after follow-ups A1 to A4, 136/136 tests, 97.6% coverage). Commit pending your review. |
| 4     | `FleetAllocationService`, `VehicleAvailabilityService` (capacity, validity, overlap, row locking), tests                                                                                         | **Done - deployed and committed** (`ee5d39f`)                                                                                                 |
| 5     | Dispatch and delivery: delivery attempts, proof of delivery and evidence, trip lifecycle ([docs/DELIVERY_IMPLEMENTATION.md](docs/DELIVERY_IMPLEMENTATION.md))                                    | **Done - deployed and committed** (`216af55`). Inventory and stock movements, invoicing, payments and the Flows are not started (5B).         |
| 6     | GPS tracking: REST ingestion, mock provider, throttling, retries and dead letters, F5 robustness                                                                                                 | **Done - deployed and committed** (`8c11ac7`). Returns and claims, other integration mocks, platform events and log purge are not started.    |
| 7     | LWCs (CLAUDE.md section 8) for the implemented modules; Lightning pages and navigation ([docs/LWC_IMPLEMENTATION.md](docs/LWC_IMPLEMENTATION.md))                                                | Steps 1–2 committed (`e4215c5`, `6a8489d`); Step 3 deployed (`0Afg700000Kax4UCAR`); Steps 4–7 implemented, **awaiting validation**            |
| 8     | 7 report types, 19 reports, 5 dashboards including "eLogix - Executive Operations Dashboard"; `Shipment__c.Is_On_Time__c` ([docs/ANALYTICS_IMPLEMENTATION.md](docs/ANALYTICS_IMPLEMENTATION.md)) | Implemented, **awaiting validation**                                                                                                          |
| 9     | Idempotent seed data, roles and sharing rules, per-role security validation, E2E regression, demo rehearsal                                                                                      | Not started                                                                                                                                   |

## Two-day execution checklist

**Day 1**

- [x] Project inspection and setup (CLI 2.140.6, org edition and limits, API versions, existing metadata)
- [x] Architecture and documentation (12 documents in `docs/`, generated catalogue)
- [x] Data model and metadata (deployed: 621 components; 674 with the Phase 2 Apex)
- [x] Shipment and quotation services (shipment service P2; quotation, approval and conversion P3)
- [x] Freight calculation (P3)
- [ ] Fleet allocation (P4)
- [x] Status transition policy (P2)
- [x] Tracking history (P2)
- [ ] Initial Apex tests (P2: 79 tests, P3: 53 tests; P4 to follow)

**Day 2**

- [ ] Warehouse and inventory essentials (P5)
- [ ] Delivery and invoice automation (P5)
- [ ] Returns, if time permits (P6)
- [ ] LWC screens (P7): shipments, quotations, fleet, tracking and delivery implemented; warehouse, invoicing and returns screens wait for their services
- [ ] Native reports and dashboards (P8): implemented, awaiting validation; finance metrics limited to delivered freight value until invoicing exists
- [ ] Demo data (P9)
- [ ] Regression tests, deployment validation, demo rehearsal (P9)

---

## Phase 3 report

Full report: [docs/PHASE3_IMPLEMENTATION_REPORT.md](docs/PHASE3_IMPLEMENTATION_REPORT.md). Plan and approved decisions: [docs/PHASE3_PLAN.md](docs/PHASE3_PLAN.md). Design: [docs/PRICING_IMPLEMENTATION.md](docs/PRICING_IMPLEMENTATION.md).

| Step                                                        | ID                       | Result                                                                                                                                                            |
| ----------------------------------------------------------- | ------------------------ | ----------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Model change Q14/Q18, check-only                            | `0Afg700000KOurxCAD`     | Succeeded, 55/55, 79/79 tests                                                                                                                                     |
| **Model change Q14/Q18, deploy**                            | **`0Afg700000KOim0CAD`** | **Succeeded, 55/55, 79/79 tests**; Phase 1 19/19 and Phase 2 12/12 afterwards                                                                                     |
| Apex check-only, final run                                  | `0Afg700000KREzSCAX`     | Succeeded, 717/717, 132/132 tests (runs 1 to 4 found test-only defects, fixed)                                                                                    |
| **Apex deploy + `RunLocalTests`**                           | **`0Afg700000KRoekCAD`** | **Succeeded, 717/717, 132/132 tests, coverage 97.2%**                                                                                                             |
| Verification scripts                                        | n/a                      | Phase 1 **19/19**, Phase 2 **12/12**, Phase 3 **18/18**; no rows left behind                                                                                      |
| Pre-commit audit follow-up A1 to A3, check-only             | `0Afg700000KQcR8CAL`     | Succeeded, 718/718, 135/135 tests                                                                                                                                 |
| **Pre-commit audit follow-up A1 to A3, deploy**             | **`0Afg700000KRt9mCAD`** | **Succeeded, 718/718, 135/135 tests, coverage 97.6%**; scripts Phase 1 19/19, Phase 2 12/12, Phase 3 19/19; all 48 Apex classes and triggers match the repository |
| Follow-up A4, check-only                                    | `0Afg700000KRMCFCA5`     | Succeeded, 718/718, 136/136 tests                                                                                                                                 |
| **Follow-up A4 (validity date locked after Draft), deploy** | **`0Afg700000KRUWMCA5`** | **Succeeded, 718/718, 136/136 tests, coverage 97.6%**; scripts 19/19, 12/12, 19/19; all 48 Apex classes and triggers match the repository                         |

Audit follow-up (report section 9):

- **A1:** a quotation's request link is now immutable.
- **A2:** self-approval is checked against the previous owner too.
- **A3:** conversion locks the request and re-checks its status under the lock.

Built: 10 production classes (`pricing/`, `crm/`, selectors, handler), `QuotationTrigger`, 27 labels, 53 tests, `verify-phase3-pricing.apex`, the approved Q14 (taxable lines) and Q18 (line lock) model changes. No Phase 2 production class changed.

**Known issues** (report section 7):

1. New rate cards default to Region = South (value-set default), so they are region-specific unless cleared.
2. Narrow `without sharing` writers for approval, request status and conversion compensation, until Phase 9 roles exist (documented deviation from the plan).
3. Conversion is available to the Logistics Manager or an administrator until Phase 9 sharing.
4. A5: when the customer rejects a quotation, its request stays at Quoted. This is a known limitation until quotation revisions are implemented.

**Source control:** nothing committed. All Phase 3 changes are uncommitted on `feature/phase-2-apex-foundation`, on top of `90751c6`; awaiting your review.

---

## Phase 2 report

Full report: [docs/PHASE2_IMPLEMENTATION_REPORT.md](docs/PHASE2_IMPLEMENTATION_REPORT.md). Architecture contract (approved, with a deviations section): [docs/APEX_ARCHITECTURE.md](docs/APEX_ARCHITECTURE.md).

### What was built

| Component                                                                                | Count                 | Location                                                                             |
| ---------------------------------------------------------------------------------------- | --------------------- | ------------------------------------------------------------------------------------ |
| Production Apex classes (framework, policy, guard, domain, services, selectors, handler) | 20                    | `force-app/main/default/classes/{base,common,shipment,tracking,selectors,handlers}/` |
| Test classes (including `TestDataFactory`)                                               | 13                    | `classes/test/`                                                                      |
| Trigger                                                                                  | 1 (`ShipmentTrigger`) | `triggers/`                                                                          |
| Custom labels                                                                            | 18                    | `labels/CustomLabels.labels-meta.xml` (hand-maintained)                              |
| Post-deploy verification script                                                          | 1 (12 checks)         | `scripts/apex/verify-phase2-apex.apex`                                               |

Behaviour now live:

- Every shipment status change, from any entry path, is checked against the 46 deployed transitions.
- Leaving Closed or Cancelled, and moving Delivered backwards, are hard rules that no permission can bypass.
- Cancel after confirmation needs `eLogix_Cancel_Confirmed_Shipment`.
- Override changes are recorded as `Exception` events.
- A shipment needs an item before Confirmed.
- Every allowed change writes exactly one tracking event, keyed deterministically. If that event cannot be written, the status change is rolled back.

### Deployment results

| Step                                                        | ID                       | Result                                              |
| ----------------------------------------------------------- | ------------------------ | --------------------------------------------------- |
| Model validator                                             | n/a                      | Passed                                              |
| Check-only deploy + `RunLocalTests`                         | `0Afg700000KO3IzCAL`     | Succeeded, 674/674, 76/76 tests                     |
| Check-only deploy + `RunLocalTests` (after adding one test) | `0Afg700000KM5omCAD`     | Succeeded, 674/674, 77/77 tests                     |
| **Deploy + `RunLocalTests`**                                | **`0Afg700000KNnfeCAD`** | **Succeeded, 674/674, 77/77 tests, coverage 97.5%** |
| Follow-up check-only deploy + `RunLocalTests`               | `0Afg700000KOIRiCAP`     | Succeeded, 674/674, 79/79 tests                     |
| **Follow-up deploy + `RunLocalTests` (F1 to F3)**           | **`0Afg700000KOZcDCAX`** | **Succeeded, 674/674, 79/79 tests, coverage 98.5%** |

### Verification results

- `verify-phase2-apex.apex`: **12/12** against live configuration, all rolled back.
- `verify-phase1-metadata.apex`: **19/19**. Phase 1 still works with the trigger active.
- Org inventory: 33 classes, 1 active trigger, 18 labels, 0 shipments left behind.

### Known issues

See [docs/PHASE2_IMPLEMENTATION_REPORT.md](docs/PHASE2_IMPLEMENTATION_REPORT.md#7-known-issues-and-limitations). The main ones:

1. ~~The misleading comment in `ShipmentService`~~: corrected and deployed in `0Afg700000KOZcDCAX` (F3).
2. ~~One untested rollback branch in `TrackingService.recordEvents`~~: covered by the F2 test.
3. Ready for Dispatch and Dispatched guards are deferred to Phases 4 and 5.
4. Prettier has not been run on the Apex code.
5. ~~`recordStatusEvents` public and trusting its inputs~~: restricted to the shipment trigger (F1). Open for Phase 6: the batch-wide rollback and GPS record-lock items (F5).

### Source control

Committed as `1d6d61d` ("feat: implement Phase 2 Apex foundation") on `feature/phase-2-apex-foundation`, branched from `feature/phase-1-metadata-foundation`. 82 files: 76 added, 6 modified, all documentation or Phase 2 source. Not pushed. The commit includes a comment-only correction to `ShipmentService` that is not yet deployed; the org copy differs from the repository by those comment lines until the follow-up deploy.

**Follow-up F1 to F5 (uncommitted, awaiting your review):** 5 Apex files changed (`TrackingService`, `ShipmentTriggerHandler`, `ShipmentTriggerHandlerTest`, `TrackingServiceTest`, `TestDataFactory`) plus documentation. They are deployed in `0Afg700000KOZcDCAX`. The `ShipmentService` comment correction was already in commit `1d6d61d` and is now deployed too.

### Mandatory follow-up before Phase 3

These items came from the pre-commit review ([docs/PHASE2_IMPLEMENTATION_REPORT.md](docs/PHASE2_IMPLEMENTATION_REPORT.md) section 9). Phase 3 does not start until all of them are done and you approve.

| #   | Item                                                                                                                                                            | Done when                                                                                                                                                                                            | Status                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                              |
| --- | --------------------------------------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| F1  | **Restrict `TrackingService.recordStatusEvents`** (finding S3) so no future controller, REST resource or invocable action can supply fabricated status history. | Status events can be created only from the shipment trigger context; a test proves an out-of-trigger call is refused; the re-entry test still proves duplicate suppression through the trigger path. | **Done.** The method is now `recordStatusEvents()`: it reads `Trigger.new` and `Trigger.oldMap` and throws `AuthorizationException` (`STATUS_EVENTS_TRIGGER_ONLY`) outside a `Shipment__c` after-save trigger. Tests: `statusEventsCannotBeRecordedOutsideTheShipmentTrigger` covers direct calls and fabricated records sent through the handler test constructor; `reEntryWithTheSameVersionDoesNotDuplicateEvents` now runs through the real trigger; `savesWithoutStatusChangeCostNothing` covers 200 rows.     |
| F2  | **Add the production-reachable rollback test** for the summary-update failure in `recordEvents`, with no production failure switch.                             | A Data Migration user creates a shipment that breaks `SHP_Delivery_After_Pickup`; a Logistics Manager records an event on it; the test asserts `OPERATION_FAILED` and that no event is left behind.  | **Done.** `TrackingServiceTest.summaryFailureRollsBackTheEventsOfTheWholeBatch`. `TrackingService` coverage rose from 96.2% to 99.1%. No failure switch was added.                                                                                                                                                                                                                                                                                                                                                  |
| F3  | **One deploy** carrying the corrected `ShipmentService` comment together with F1 and F2.                                                                        | Check-only, then real deploy with `RunLocalTests`; deploy ID recorded; the org matches the repository.                                                                                               | **Done.** Check-only `0Afg700000KOIRiCAP` (79/79), then **`0Afg700000KOZcDCAX`** (2026-11-19 10:59 UTC): 674/674 components, 79/79 tests, coverage 98.5% (637/647). Recorded in docs/DEPLOYMENT_GUIDE.md. The deployed source of all six changed classes was compared with the repository and is identical.                                                                                                                                                                                                         |
| F4  | **Re-run the validator and all Apex tests**, plus both verification scripts.                                                                                    | Validator passed; all tests pass; coverage at or above 85%; both scripts pass; results recorded.                                                                                                     | **Done.** Validator passed; 79/79 tests; 98.5% coverage. `verify-phase2-apex.apex` passed 12/12 and `verify-phase1-metadata.apex` passed 19/19 (INR, Asia/Kolkata), with 0 shipments left behind. Recorded in docs/APEX_TEST_MATRIX.md and docs/TEST_STRATEGY.md.                                                                                                                                                                                                                                                   |
| F5  | **Review the batch-wide rollback risk and the GPS record-lock risk**, and document the planned Phase 6 resolution.                                              | docs/TRACKING_IMPLEMENTATION.md and docs/INTEGRATION_DESIGN.md describe the chosen design for both risks.                                                                                            | **Done (documentation only, no code).** TRACKING_IMPLEMENTATION section 5: summaries updated with partial success, compensating deletion of only the failed shipment's new events, and a retryable `RECORD_LOCKED` result instead of an uncaught `QueryException`, each with acceptance criteria. INTEGRATION_DESIGN section 3: asynchronous ingestion, per-shipment grouping, backoff retry with dead letter in `Integration_Log__c`. **Both must be implemented in Phase 6 before live GPS pings are connected.** |

---

## Phase 1 report

### What was built

| Component                                                                   | Count                                      | Location                                                        |
| --------------------------------------------------------------------------- | ------------------------------------------ | --------------------------------------------------------------- |
| Custom objects                                                              | 26                                         | `force-app/main/default/objects/`                               |
| Custom fields (incl. 9 on Account/Contact)                                  | 327                                        | `objects/*/fields/`                                             |
| Validation rules (all with a bypass guard except 2 stock invariants)        | 70                                         | `objects/*/validationRules/`                                    |
| Global value sets                                                           | 10                                         | `globalValueSets/`                                              |
| Custom metadata types / records                                             | 2 / 53 (46 status transitions, 7 settings) | `objects/*__mdt/`, `customMetadata/`                            |
| Custom permissions                                                          | 10                                         | `customPermissions/`                                            |
| Permission sets (8 roles + data migration)                                  | 9                                          | `permissionsets/`                                               |
| Lightning app with 20 nav items                                             | 1                                          | `applications/eLogix_ERP.app-meta.xml`                          |
| Custom tabs                                                                 | 21                                         | `tabs/`                                                         |
| Page layouts (26 objects + 2 metadata types) / compact layouts / list views | 28 / 26 / 26                               | `layouts/`, `objects/*/compactLayouts/`, `objects/*/listViews/` |
| Extended standard layouts                                                   | Account Layout, Contact Layout             | `layouts/` (hand-maintained)                                    |

### Files created and changed

| Path                                                             | Change                                                                                                                                                                                                                                                                                                           |
| ---------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `scripts/node/lib/metadata-writer.mjs`                           | Rewritten. Fixes from review: `unique` only on supported types; `enableSharing` and `externalSharingModel` on every object; CMDT `fieldManageability`. Added writers for validation rules, list views, compact layouts, page layouts, CMDT types and records, custom permissions, tabs, app and permission sets. |
| `scripts/node/scaffold-metadata.mjs`                             | Rewritten. Model validator (references, picklist values, permissions, permission-set dependencies, transition integrity, percent misuse), related-list derivation, catalogue generation.                                                                                                                         |
| `scripts/node/model/elogix-datamodel.mjs`                        | Tracking event types aligned 1:1 with statuses; maintenance roll-up filter excludes Cancelled; percent-formula fix.                                                                                                                                                                                              |
| `scripts/node/model/elogix-validation.mjs`                       | New: 70 validation rules.                                                                                                                                                                                                                                                                                        |
| `scripts/node/model/elogix-experience.mjs`                       | New: tabs, list views, Files related lists, app navigation.                                                                                                                                                                                                                                                      |
| `scripts/node/model/elogix-config.mjs`                           | New: custom permissions, status transitions, settings.                                                                                                                                                                                                                                                           |
| `scripts/node/model/elogix-security.mjs`                         | New: role access matrix, protected fields.                                                                                                                                                                                                                                                                       |
| `scripts/apex/verify-phase1-metadata.apex`                       | New: rolled-back behaviour verification (19 checks).                                                                                                                                                                                                                                                             |
| `force-app/main/default/**`                                      | Generated metadata (621 components) plus 2 hand-extended standard layouts.                                                                                                                                                                                                                                       |
| `docs/*.md` (12 files), `docs/generated/DATA_MODEL_CATALOGUE.md` | New.                                                                                                                                                                                                                                                                                                             |
| `package.json`                                                   | Added `metadata:validate` and `metadata:generate` scripts.                                                                                                                                                                                                                                                       |
| `PROJECT_STATUS.md`                                              | New (this file).                                                                                                                                                                                                                                                                                                 |

`CLAUDE.md` and `.gitignore` carry your own changes (the `claude.md` → `CLAUDE.md` rename and the removed ignore line). They are committed separately from the Phase 1 work (see Source control).

### Deployment results

| Deploy ID            | Scope                                             | Result                                                                                                                                                                                                     |
| -------------------- | ------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| (dry run)            | Initial check                                     | Failed: 9 errors, one root cause. `isNavAutomaticallyAdded` is invalid in `CustomApplication`, and the 8 permission sets referencing the app failed with it. Fixed by mirroring a retrieved Lightning app. |
| (dry run)            | Re-check                                          | Succeeded, 565/565                                                                                                                                                                                         |
| `0Afg700000KLr5pCAD` | Phase 1 metadata                                  | **Succeeded, 565/565**                                                                                                                                                                                     |
| `0Afg700000KLuLRCA1` | Percent-field defect fix                          | **Succeeded, 565/565**                                                                                                                                                                                     |
| (dry run)            | With layouts                                      | Succeeded, 621/621                                                                                                                                                                                         |
| `0Afg700000KLxb3CAD` | Layouts, compact layouts, Account/Contact layouts | **Succeeded, 621/621**                                                                                                                                                                                     |

Post-deploy: `eLogix_Administrator` assigned to the org admin user (needed for field visibility on API-deployed fields).

### Verification results

- **In-org inventory** (Tooling API / SOQL): 28 custom objects including the 2 CMDTs, 70 active validation rules, 9 permission sets, 10 custom permissions, 46 transition and 7 setting records, 10 global value sets, app `eLogix_ERP` (Lightning, Standard nav). The Shipment layout has 34 fields and 15 related lists (the auto-created one had 10 fields). The compact layout is assigned.
- **Behaviour script**: 19/19 checks pass. Details are in [docs/TEST_STRATEGY.md](docs/TEST_STRATEGY.md#3-phase-1-results-2026-11-19-elogixdev). No rows were left behind: the script rolls back, and counts were confirmed as 0 afterwards.
- **Defect found by verification and fixed**: the quotation tax formula was 100× too small. Percent fields are fractions in formulas; this also affected 3 range rules. The fix is deployed and the generator now blocks the pattern.
- **Apex tests**: none yet, because there is no Apex in Phase 1.

### Org settings for the Indian demo

| Setting                                     | Status                                                                                                                                                                                                             |
| ------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| Org default time zone, admin user time zone | **Asia/Kolkata**, verified (`Organization.TimeZoneSidKey`, `UserInfo.getTimeZone()`)                                                                                                                               |
| Company currency locale                     | **English (India) / INR**, verified 2026-11-19 (`SMOKE INFO org currency=INR`). Changed manually in Setup → Company Information, because single-currency orgs expose this setting through no API or metadata type. |

### Source control

Phase 1 is committed on branch `feature/phase-1-metadata-foundation` (local only, not pushed):

1. Your `CLAUDE.md` rename and `.gitignore` change, kept separate so it can be reviewed or dropped on its own.
2. The Phase 1 metadata foundation, generator, verification script and documentation.
3. Org settings follow-up: currency verified as INR, docs updated.

### Known issues and limitations

1. **Roles and sharing rules are not deployed** (planned for Phase 9). Under Private org-wide defaults, non-manager roles currently see only records they own.
2. **Validation rule messages are plain text**, not Custom Labels. This is a platform limitation; they are translatable via Translation Workbench, and all Apex messages will use labels.
3. **Per-role access is designed and deployed but not yet exercised** with login-as test users (Phase 9).
4. **The generator does not delete files.** Renamed or removed model items must be removed by hand, plus a destructive deploy if they were already deployed.
5. **`node_modules` is not installed**, so the husky/lint-staged hooks (Prettier on XML) and LWC Jest are inactive. Once installed, Prettier may reformat the generated XML whitespace on commit.
6. Only the `Account Layout` and `Contact Layout` used by System Administrator were extended. The Sales, Support and Marketing variants were not.
7. The CLI session for `eLogixDev` still carries the admin user's previous username. It keeps working, but SOQL lookups on `User.Username` must use the current username.

### Actions for you

1. Push `feature/phase-1-metadata-foundation` and open a pull request when ready. Nothing has been pushed.

### Recommended next phase (Phase 1 recommendation, now delivered by Phase 2)

**Phase 2 - Apex foundation and shipment core:** base framework (trigger handler, `ServiceResult`, exception hierarchy, logger, `SettingsService`, `PermissionService`, selectors). Then `ShipmentStatusPolicy` driven by the deployed transition metadata, `ShipmentService`, `TrackingService`, a single `ShipmentTrigger`, and unit tests covering valid and invalid transitions, the item guard, override and cancel permissions, tracking event creation, and 200-record bulk updates.
