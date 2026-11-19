# eLogix ERP - Project Status

| | |
|---|---|
| Last updated | 2026-11-19 |
| Current phase | **Phase 1 - complete** (project setup, architecture documentation, metadata foundation) |
| Next phase | Phase 2 - Apex foundation, shipment status policy and tracking (awaiting go-ahead) |
| Target org | `eLogixDev` - Developer Edition, instance API 68.0, source API 67.0 |

## Phase plan

| Phase | Scope | Status |
|---|---|---|
| 1 | Project inspection, architecture docs, data model, security, configuration and app metadata | **Done - deployed and verified** |
| 2 | Apex foundation (trigger handler, result/exception pattern, logger, settings and permission services, selectors), `ShipmentStatusPolicy`, `ShipmentService`, `TrackingService`, triggers, tests | Not started |
| 3 | `FreightCalculationService`, rate card selection, quotation service, tests | Not started |
| 4 | `FleetAllocationService`, `VehicleAvailabilityService` (capacity, validity, overlap, row locking), tests | Not started |
| 5 | Inventory and stock movements, delivery, invoicing, payments; Flows (request, quotation approval, delivery completion, invoice generation, payment status, SLA) | Not started |
| 6 | Returns and claims; integration interfaces and mocks; platform events; log purge | Not started |
| 7 | LWCs (CLAUDE.md section 8) | Not started |
| 8 | Report types, operational reports, "eLogix - Executive Operations Dashboard" | Not started |
| 9 | Idempotent seed data, roles and sharing rules, per-role security validation, E2E regression, demo rehearsal | Not started |

## Two-day execution checklist

**Day 1**
- [x] Project inspection and setup (CLI 2.140.6, org edition and limits, API versions, existing metadata)
- [x] Architecture and documentation (12 documents in `docs/`, generated catalogue)
- [x] Data model and metadata (deployed: 621 components)
- [ ] Shipment and quotation services (P2, P3)
- [ ] Freight calculation (P3)
- [ ] Fleet allocation (P4)
- [ ] Status transition policy (P2; configuration already live)
- [ ] Tracking history (P2)
- [ ] Initial Apex tests (P2 to P4)

**Day 2**
- [ ] Warehouse and inventory essentials (P5)
- [ ] Delivery and invoice automation (P5)
- [ ] Returns, if time permits (P6)
- [ ] LWC screens (P7)
- [ ] Native reports and dashboards (P8)
- [ ] Demo data (P9)
- [ ] Regression tests, deployment validation, demo rehearsal (P9)

---

## Phase 1 report

### What was built

| Component | Count | Location |
|---|---|---|
| Custom objects | 26 | `force-app/main/default/objects/` |
| Custom fields (incl. 9 on Account/Contact) | 327 | `objects/*/fields/` |
| Validation rules (all with a bypass guard except 2 stock invariants) | 70 | `objects/*/validationRules/` |
| Global value sets | 10 | `globalValueSets/` |
| Custom metadata types / records | 2 / 53 (46 status transitions, 7 settings) | `objects/*__mdt/`, `customMetadata/` |
| Custom permissions | 10 | `customPermissions/` |
| Permission sets (8 roles + data migration) | 9 | `permissionsets/` |
| Lightning app with 20 nav items | 1 | `applications/eLogix_ERP.app-meta.xml` |
| Custom tabs | 21 | `tabs/` |
| Page layouts (26 objects + 2 metadata types) / compact layouts / list views | 28 / 26 / 26 | `layouts/`, `objects/*/compactLayouts/`, `objects/*/listViews/` |
| Extended standard layouts | Account Layout, Contact Layout | `layouts/` (hand-maintained) |

### Files created and changed

| Path | Change |
|---|---|
| `scripts/node/lib/metadata-writer.mjs` | Rewritten. Fixes from review: `unique` only on supported types; `enableSharing` and `externalSharingModel` on every object; CMDT `fieldManageability`. Added writers for validation rules, list views, compact layouts, page layouts, CMDT types and records, custom permissions, tabs, app and permission sets. |
| `scripts/node/scaffold-metadata.mjs` | Rewritten. Model validator (references, picklist values, permissions, permission-set dependencies, transition integrity, percent misuse), related-list derivation, catalogue generation. |
| `scripts/node/model/elogix-datamodel.mjs` | Tracking event types aligned 1:1 with statuses; maintenance roll-up filter excludes Cancelled; percent-formula fix. |
| `scripts/node/model/elogix-validation.mjs` | New: 70 validation rules. |
| `scripts/node/model/elogix-experience.mjs` | New: tabs, list views, Files related lists, app navigation. |
| `scripts/node/model/elogix-config.mjs` | New: custom permissions, status transitions, settings. |
| `scripts/node/model/elogix-security.mjs` | New: role access matrix, protected fields. |
| `scripts/apex/verify-phase1-metadata.apex` | New: rolled-back behaviour verification (19 checks). |
| `force-app/main/default/**` | Generated metadata (621 components) plus 2 hand-extended standard layouts. |
| `docs/*.md` (12 files), `docs/generated/DATA_MODEL_CATALOGUE.md` | New. |
| `package.json` | Added `metadata:validate` and `metadata:generate` scripts. |
| `PROJECT_STATUS.md` | New (this file). |

`CLAUDE.md` and `.gitignore` carry your own changes (the `claude.md` → `CLAUDE.md` rename and the removed ignore line). They are committed separately from the Phase 1 work (see Source control).

### Deployment results

| Deploy ID | Scope | Result |
|---|---|---|
| (dry run) | Initial check | Failed: 9 errors, one root cause. `isNavAutomaticallyAdded` is invalid in `CustomApplication`, and the 8 permission sets referencing the app failed with it. Fixed by mirroring a retrieved Lightning app. |
| (dry run) | Re-check | Succeeded, 565/565 |
| `0Afg700000KLr5pCAD` | Phase 1 metadata | **Succeeded, 565/565** |
| `0Afg700000KLuLRCA1` | Percent-field defect fix | **Succeeded, 565/565** |
| (dry run) | With layouts | Succeeded, 621/621 |
| `0Afg700000KLxb3CAD` | Layouts, compact layouts, Account/Contact layouts | **Succeeded, 621/621** |

Post-deploy: `eLogix_Administrator` assigned to the org admin user (needed for field visibility on API-deployed fields).

### Verification results

- **In-org inventory** (Tooling API / SOQL): 28 custom objects including the 2 CMDTs, 70 active validation rules, 9 permission sets, 10 custom permissions, 46 transition and 7 setting records, 10 global value sets, app `eLogix_ERP` (Lightning, Standard nav). The Shipment layout has 34 fields and 15 related lists (the auto-created one had 10 fields). The compact layout is assigned.
- **Behaviour script**: 19/19 checks pass. Details are in [docs/TEST_STRATEGY.md](docs/TEST_STRATEGY.md#3-phase-1-results-2026-11-19-elogixdev). No rows were left behind: the script rolls back, and counts were confirmed as 0 afterwards.
- **Defect found by verification and fixed**: the quotation tax formula was 100× too small. Percent fields are fractions in formulas; this also affected 3 range rules. The fix is deployed and the generator now blocks the pattern.
- **Apex tests**: none yet, because there is no Apex in Phase 1.

### Org settings for the Indian demo

| Setting | Status |
|---|---|
| Org default time zone, admin user time zone | **Asia/Kolkata**, verified (`Organization.TimeZoneSidKey`, `UserInfo.getTimeZone()`) |
| Company currency locale | **English (India) / INR**, verified 2026-11-19 (`SMOKE INFO org currency=INR`). Changed manually in Setup → Company Information, because single-currency orgs expose this setting through no API or metadata type. |

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

### Recommended next phase

**Phase 2 - Apex foundation and shipment core:** base framework (trigger handler, `ServiceResult`, exception hierarchy, logger, `SettingsService`, `PermissionService`, selectors). Then `ShipmentStatusPolicy` driven by the deployed transition metadata, `ShipmentService`, `TrackingService`, a single `ShipmentTrigger`, and unit tests covering valid and invalid transitions, the item guard, override and cancel permissions, tracking event creation, and 200-record bulk updates.
