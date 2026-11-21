# eLogix ERP - Shipment Status Policy Implementation

| | |
|---|---|
| Status | Live since Phase 2 (deploy `0Afg700000KNnfeCAD`, 2026-11-19) |
| Contract | [APEX_ARCHITECTURE.md](APEX_ARCHITECTURE.md) section 5 |
| Lifecycle and transition table | [SHIPMENT_LIFECYCLE.md](SHIPMENT_LIFECYCLE.md) |
| Source | `classes/shipment/ShipmentStatusPolicy.cls`, `ShipmentStatusGuard.cls`, `ShipmentItemsRequiredGuard.cls`, `ShipmentDomain.cls`, `ShipmentService.cls`; `classes/handlers/ShipmentTriggerHandler.cls`; `triggers/ShipmentTrigger.trigger` |

## 1. Where the policy runs

`ShipmentTrigger` → `ShipmentTriggerHandler` → `ShipmentDomain` (before insert / before update) → `ShipmentStatusPolicy`.

- **Rejected changes:** `Status__c.addError(<label>)`. With `allOrNone=true` the whole DML fails; with `allOrNone=false` only that row fails.
- **Allowed changes:** `Latest_Tracking_Timestamp__c` is stamped with the current time.
- **Single entry point:** UI edits, list-view inline edits, Data Loader, REST, Flow and `ShipmentService.changeStatus` all pass through the same evaluation. Nothing in Apex can switch it off.

## 2. Configuration loading

`new ShipmentStatusPolicy()` reads `Shipment_Status_Transition__mdt.getAll()`, which costs no SOQL. Every row is indexed by the pair `From>To`, where a blank from-status is the empty string:

| Row state | Effect |
|---|---|
| Active and well-formed | Allowed transition. The event type is `Tracking_Event_Type__c`, or the target status when that field is blank. |
| Inactive | The pair is recorded as inactive, so the change is rejected with `TRANSITION_INACTIVE` rather than "not allowed". |
| Unknown status or event type, or a second active row for the same pair | The pair is invalid and is rejected with `CONFIGURATION_INVALID`, **even under override**. Other pairs are unaffected. |
| No active rows at all | Every change is rejected with `CONFIGURATION_MISSING` (fail closed), even for override users. |

Valid statuses and event types come from describe calls (`Shipment__c.Status__c`, `Tracking_Event__c.Event_Type__c`), so the policy cannot drift from the global value sets.

## 3. Decision outcomes

| Outcome | Meaning | Tracking event |
|---|---|---|
| `ALLOWED` | The table allows it, any required permission is held, and guards pass. | The row's event type |
| `ALLOWED_BY_OVERRIDE` | Steps 5 to 7 failed, but the user holds `eLogix_Override_Shipment_Status`. The decision carries `overriddenReasonCode` and `overriddenMessage`. | The row's event type, or `Exception` when no row exists. Remarks name the skipped rule. |
| `REJECTED` | A reason code and a label message. | None |
| `NO_CHANGE` | The status did not change. | None |

Reason codes: `STATUS_REQUIRED`, `CONFIGURATION_MISSING`, `TERMINAL_STATUS`, `DELIVERED_REVERSAL`, `CONFIGURATION_INVALID`, `INITIAL_STATUS_NOT_ALLOWED`, `TRANSITION_NOT_ALLOWED`, `TRANSITION_INACTIVE`, `PERMISSION_REQUIRED`, and guard codes (`ITEMS_REQUIRED`).

## 4. Hard rules (decision D1)

These are coded in `ShipmentStatusPolicy` as business invariants from CLAUDE.md section 5, not configuration. No permission skips them, and a misconfigured CMDT row cannot override them:

- No change out of `Closed` or `Cancelled` (`TERMINAL_STATUS`).
- No change from `Delivered` to `Draft`, `Requested`, `Quoted`, `Confirmed`, `Ready for Dispatch`, `Dispatched`, `In Transit` or `Out for Delivery` (`DELIVERED_REVERSAL`). `Delivered → Closed` and `Delivered → Return Initiated` remain governed by the table.

## 5. Guards (decision D2)

`ShipmentStatusGuard` is the extension point for rules that need more than the table:
- A guard declares its target statuses.
- It receives only changes the policy already allowed, including overrides.
- It returns violations keyed by change index.
- It must be bulk-safe and run no SOQL per change.

| Guard | Target | Rule | Phase |
|---|---|---|---|
| `ShipmentItemsRequiredGuard` | `Confirmed` | `Item_Count__c ≥ 1`, read from the roll-up in the trigger record (no SOQL) | Live |
| Vehicle and driver guard | `Ready for Dispatch` | Allocation present | P4 (decision D3) |
| Inventory guard | `Dispatched` | Stock reserved | P5 (decision D3) |

To add a guard, implement the interface and add it to `ShipmentStatusPolicy.defaultGuards()`.

## 6. Permissions

| Permission | Effect | Held by |
|---|---|---|
| `eLogix_Cancel_Confirmed_Shipment` | Needed by the rows Confirmed, Ready for Dispatch and On Hold → Cancelled | Administrator, Logistics Manager |
| `eLogix_Override_Shipment_Status` | Skips table steps 5 to 7 only | Administrator, Logistics Manager |

Permission checks are cached per evaluation call, never statically. Automated users (integration users, Flows running as Automated Process) hold no custom permissions unless they are assigned explicitly.

## 7. Cost

| Path | SOQL | DML |
|---|---|---|
| Before insert / before update (policy) | 0 | 0 |
| Policy construction | 0 (CMDT `getAll`, describe) | 0 |

Measured in `ShipmentTriggerHandlerTest.bulkInsertAndUpdateUseOneQueryAndOneInsertEach`: a 200-row insert and a 200-row update each used exactly 1 query and 2 DML statements in total (the shipment DML plus the tracking insert). Saves without a status change, such as roll-up recalculation after item inserts, used 0 queries.

## 8. Known limitations

- The policy is not a substitute for record access: users still need edit access to the shipment, and validation rules still apply to override users.
- A user who holds the override permission can create a shipment directly in a non-initial status, which records an `Exception` event. Phase 9 seeding relies on this (decision D5).
