# eLogix ERP - Deployment Guide

## Prerequisites

| Tool | Verified version |
|---|---|
| Salesforce CLI (`sf`) | 2.140.6 |
| Node.js | 22.x (generator uses only built-in modules) |
| Target org | Developer Edition, alias `eLogixDev` (default org for this project) |
| Source API version | 67.0 |

Several orgs are authenticated on the development machine, including a client sandbox. **Always pass `--target-org eLogixDev`** (or the alias of the org you intend to change). Never rely on the default alone.

## 1. Regenerate metadata (only when the model changed)

```bash
npm run metadata:validate   # validates the model; writes nothing
npm run metadata:generate   # writes force-app/main/default/** and docs/generated/DATA_MODEL_CATALOGUE.md
```

The generator owns these paths. Hand edits there are overwritten:

- `objects/<custom object>/` (object, fields, validation rules, list views, compact layouts)
- `objects/Account/fields`, `objects/Account/validationRules`, `objects/Contact/fields`
- `layouts/<custom object>-<label> Layout`, `layouts/<metadata type>-<label> Layout`
- `globalValueSets/`, `customMetadata/`, `customPermissions/`, `permissionsets/`, `tabs/`, `applications/eLogix_ERP.app-meta.xml`

These paths are **hand-maintained** (retrieved from the org, then extended):

- `layouts/Account-Account Layout.layout-meta.xml` (eLogix Customer Profile section and related lists)
- `layouts/Contact-Contact Layout.layout-meta.xml` (eLogix Contact Role section)

The generator does not delete files. After renaming or removing something in the model, delete the old file and add it to a destructive change if it was already deployed.

## 2. Validate, then deploy

```bash
# Check-only deploy: compiles and validates everything, saves nothing
sf project deploy start --dry-run --source-dir force-app --target-org eLogixDev --wait 30

# Real deploy
sf project deploy start --source-dir force-app --target-org eLogixDev --wait 30
```

From Phase 2 onward, every deploy runs all local Apex tests. Pass the test level explicitly, and run the check-only deploy with tests too:

```bash
sf project deploy start --dry-run --source-dir force-app --target-org eLogixDev --test-level RunLocalTests --wait 30
sf project deploy start --source-dir force-app --target-org eLogixDev --test-level RunLocalTests --wait 30
```

Never use `--test-level NoTestRun` to force a deployment (CLAUDE.md rule 29). `ShipmentStatusTransitionConfigTest` reads the deployed `Shipment_Status_Transition__mdt` records. A transition edit that breaks a lifecycle rule therefore fails the next deploy.

`labels/CustomLabels.labels-meta.xml` is **hand-maintained**. The generator does not own it. Label values must not contain apostrophes, because Apex formats them with `String.format`.

## 3. Post-deploy steps

```bash
# Give the admin user field-level access to everything eLogix (fields deployed via API have no FLS otherwise)
sf org assign permset --name eLogix_Administrator --target-org eLogixDev

# Verify the data model behaves correctly (all DML is rolled back; no storage used)
sf apex run --file scripts/apex/verify-phase1-metadata.apex --target-org eLogixDev
```

Expect `SMOKE SUMMARY checks=19 failures=0` in the debug output.

```bash
# Verify the status policy and tracking against live configuration (rolled back; run as a user with eLogix_Administrator)
sf apex run --file scripts/apex/verify-phase2-apex.apex --target-org eLogixDev
```

Expect `SMOKE SUMMARY checks=12 failures=0`.

```bash
# Verify pricing, quotation approval and conversion against live configuration (rolled back; run as a user with eLogix_Administrator)
sf apex run --file scripts/apex/verify-phase3-pricing.apex --target-org eLogixDev
```

Expect `SMOKE SUMMARY checks=19 failures=0`. The script also prints `SMOKE INFO rate card region after insert without a region = South`; see PRICING_IMPLEMENTATION section 1.

For data seeding (Phase 9), temporarily assign `eLogix_Data_Migration` so that historical dates pass the bypassable validation rules. Remove it afterwards:

```bash
sf org assign permset --name eLogix_Data_Migration --target-org eLogixDev
# ... run seed ...
# Remove: Setup → Users → <user> → Permission Set Assignments (the CLI has no unassign command)
```

## 4. Org settings for the Indian demo

| Setting | Required value | Status (2026-11-19) | How |
|---|---|---|---|
| Org default time zone | Asia/Kolkata | Done (verified via `Organization.TimeZoneSidKey`) | Setup → Company Information, or `sf data update record --sobject Organization` |
| Admin user time zone | Asia/Kolkata | Done (verified via `UserInfo.getTimeZone()`) | User settings |
| Company currency locale | English (India) → INR | Done (verified: `SMOKE INFO org currency=INR`) | Manual, see below |

The currency locale of a single-currency org is not exposed through the SOAP/REST API (`Organization` has no such field) or through any settings metadata type (`CompanySettings` and `CurrencySettings` were retrieved and checked). On a fresh org, change it in the UI:

1. Setup → Quick Find "Company Information" → **Edit**.
2. **Currency Locale** → `English (India) - INR` → **Save**.
3. Verify: `sf apex run --file scripts/apex/verify-phase1-metadata.apex --target-org eLogixDev`. The `SMOKE INFO` line must show `org currency=INR`.

Do this **before** loading demo data. Changing the currency locale relabels amounts; it does not convert them. Users created later (Phase 9 role test users) should be given time zone Asia/Kolkata.

## 5. Deployment history

| Date (UTC) | Deploy ID | Scope | Components | Result |
|---|---|---|---|---|
| 2026-11-19 03:58 | `0Afg700000KLr5pCAD` | Phase 1 metadata foundation | 565 / 565 | Succeeded |
| 2026-11-19 ~04:03 | `0Afg700000KLuLRCA1` | Percent-field fix (quotation tax formulas, 3 validation rules) | 565 / 565 | Succeeded |
| 2026-11-19 04:10 | `0Afg700000KLxb3CAD` | Page layouts, compact layouts, Account/Contact layout extensions | 621 / 621 | Succeeded |
| 2026-11-19 09:49 | `0Afg700000KNnfeCAD` | Phase 2: 33 Apex classes, `ShipmentTrigger`, 18 custom labels (`RunLocalTests`: 77/77 passed, coverage 97.5%) | 674 / 674 | Succeeded |
| 2026-11-19 10:59 | `0Afg700000KOZcDCAX` | Phase 2 follow-up F1 to F3: `recordStatusEvents` restricted to the shipment trigger, rollback test, `ShipmentService` comment (`RunLocalTests`: 79/79 passed, coverage 98.5%) | 674 / 674 | Succeeded |
| 2026-11-19 ~11:53 | `0Afg700000KOim0CAD` | Phase 3 model change: `Quotation__c.Taxable_Line_Total__c`, tax/total formulas (Q14), `QTL_Locked_Unless_Draft` (Q18), layout, FLS (`RunLocalTests`: 79/79) | 55 / 55 | Succeeded |
| 2026-11-19 17:41 | `0Afg700000KRoekCAD` | Phase 3 Apex: pricing, quotation, approval, conversion; `QuotationTrigger`; 27 labels (`RunLocalTests`: 132/132 passed, coverage 97.2%) | 717 / 717 | Succeeded |
| 2026-11-19 18:03 | `0Afg700000KRt9mCAD` | Phase 3 follow-up A1 to A3: request link immutable, self-approval check against previous owner, request lock on conversion; 1 label (`RunLocalTests`: 135/135 passed, coverage 97.6%) | 718 / 718 | Succeeded |
| 2026-11-19 18:13 | `0Afg700000KRUWMCA5` | Phase 3 follow-up A4: quotation validity date locked after Draft; lock label wording (`RunLocalTests`: 136/136 passed, coverage 97.6%) | 718 / 718 | Succeeded |

Each deploy was preceded by a successful `--dry-run`. The only dry-run failure in the phase was the first one: `isNavAutomaticallyAdded` is not a valid `CustomApplication` element. The writer now copies the element set of a Lightning app retrieved from the org.

## 6. Rollback

Phase 1 is additive metadata in a clean org. To remove it, build a destructive changes manifest from `force-app` (`sf project generate manifest --source-dir force-app`, rename to `destructiveChanges.xml`, pair with an empty `package.xml`) and deploy with `--manifest`. Do not include the Account and Contact layouts; they pre-existed. Delete custom objects only after removing their data.
