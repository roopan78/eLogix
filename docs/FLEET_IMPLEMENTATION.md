# eLogix ERP - Fleet Allocation Implementation (Phase 4)

| | |
|---|---|
| Status | Implemented, including the six audit fixes (section 9). Check-only verified on `eLogixDev`: see [PHASE4_IMPLEMENTATION_REPORT.md](PHASE4_IMPLEMENTATION_REPORT.md) for the current validation. **Not yet deployed.** |
| Decisions | [PHASE4_PLAN.md](PHASE4_PLAN.md) section 0 (Q1 to Q18, approved 2026-11-20) |
| Report | [PHASE4_IMPLEMENTATION_REPORT.md](PHASE4_IMPLEMENTATION_REPORT.md) |
| Related | [BUSINESS_RULES.md](BUSINESS_RULES.md#fleet-rules) · [SHIPMENT_LIFECYCLE.md](SHIPMENT_LIFECYCLE.md) · [SECURITY_DESIGN.md](SECURITY_DESIGN.md) · [API_SPECIFICATION.md](API_SPECIFICATION.md) |

## 1. What Phase 4 delivers

A Fleet Manager allocates a vehicle and a driver to a confirmed shipment. The allocation is a `Vehicle_Assignment__c` row that books both for a time window. Every eligibility rule is enforced in one place, the assignment trigger. That holds whether the save comes from the service, the UI, the API, Data Loader or other automation. A shipment cannot reach Ready for Dispatch without an allocation that still passes every rule. Once it has, the allocation is locked. Cancelling a shipment releases its allocation automatically. Assignments are never deleted.

## 2. Components

| Class | Layer | Responsibility |
|---|---|---|
| `FleetAllocationService` | Service (`with sharing`) | Use cases: `allocate`, `reallocate`, `correctDispatchedAllocation`, `release`, `activate`, `complete`. Also the trigger-only shipment hooks: cancellation (Q11) and the deletion check. Checks object access and `eLogix_Allocate_Fleet`, confirms the caller can read the shipment, vehicle and driver, and writes in user mode with partial success. Also holds the two trigger-only cancellation hooks (Q11). |
| `VehicleAssignmentDomain` | Domain (`with sharing`) | The single enforcement point (Q14). It handles before-insert and before-update validation, status transitions, immutability, the dispatch-history lock (Q9), derivation of the window and business unit, row locks, delete and undelete refusal, the shipment mirror (Q18), and the Ready for Dispatch revalidation (`checkDispatchReadiness`). |
| `VehicleAvailabilityService` | Pure rule evaluator | Takes candidates plus pre-loaded context and returns one violation per candidate. It does no SOQL or DML, so all 14 rules are unit-tested without data. |
| `AssignmentWindow` | Utility | Converts dates to org-time-zone datetimes (Q3) and holds the overlap helpers. |
| `FleetSelector` | Selector | Holds the user-mode access-check reads (caller's sharing) and the enforcement reads, which run in the private `without sharing` `EnforcementReader` (section 5). Each enforcement read refuses to run outside its permitted trigger context. The class is virtual so a test can simulate a lock timeout. |
| `ShipmentAllocationGuard` | Status guard | Into Ready for Dispatch **and In Transit**: the shipment's `Vehicle__c` and `Driver__c` must match an open assignment, and that assignment must still pass every rule against current data (Q10). Fails closed outside the shipment trigger. |
| `AllocationRequest` | DTO | `shipmentId`, `vehicleId`, `driverId`, `remarks`; `@AuraEnabled` for the Phase 7 LWC. |
| `VehicleAssignmentTriggerHandler`, `VehicleAssignmentTrigger` | Trigger | One thin trigger: before insert, before update, before delete, after insert, after update, after undelete. |

Changes to earlier phases (all authorised):
- `ShipmentStatusPolicy.defaultGuards()` adds `ShipmentAllocationGuard`.
- `ShipmentTriggerHandler` before-update calls `clearCancelledShipmentAllocations()`, and after-update calls `releaseCancelledShipmentAssignments()`.

## 3. Rules and their order

`VehicleAvailabilityService` reports the first violation per candidate, in this order:

| # | Code | Rule | Decision |
|---|---|---|---|
| 1 | `SHIPMENT_REQUIRED` | The assignment names a shipment | Q9 |
| 2 | `WINDOW_INVALID` | Pickup and expected delivery dates are present, and delivery is on or after pickup | Q3 |
| 3 | `RECORD_NOT_FOUND` | Vehicle and driver exist | - |
| 4 | `VEHICLE_INACTIVE` | Vehicle status is not Inactive | Q2 |
| 5 | `VEHICLE_UNDER_MAINTENANCE` | Vehicle status is not Under Maintenance | Q5 |
| 6 | `DRIVER_UNAVAILABLE` | Driver is not Inactive or On Leave | Q2 |
| 7 | `BUSINESS_UNIT_MISMATCH` | Shipment, vehicle and driver are in one business unit | Q8 |
| 8 | `CAPACITY_INSUFFICIENT` | `Capacity__c ≥ Weight__c`; no load sharing | Q6 |
| 9 | `VEHICLE_TYPE_MISMATCH` | A quoted shipment needs its rate card's vehicle type | Q7 |
| 10 | `VEHICLE_DOCUMENT_INVALID` | Registration and insurance valid through the window end; fitness too when filled in | Q4 |
| 11 | `DRIVER_LICENCE_INVALID` | Licence valid through the window end | Q4 |
| 12 | `MAINTENANCE_CONFLICT` | In Progress maintenance always blocks. Scheduled maintenance blocks when `Scheduled_Date__c` to `Completion_Date__c` overlaps the window's days; with no completion date it occupies only its scheduled day. | Q5 |
| 13 | `SHIPMENT_ALREADY_ALLOCATED` | One open assignment per shipment, including within the batch | Q9 |
| 14 | `VEHICLE_DOUBLE_BOOKED` / `DRIVER_DOUBLE_BOOKED` | No overlapping open assignment, stored or earlier in the same batch | Q1 |

Before these rules, the domain checks the shipment status:
- **Allocation and reallocation:** the shipment must be Confirmed or On Hold, and for a reallocation it must never have reached dispatch (section 9.2).
- **Release:** the shipment must be Confirmed, On Hold or Cancelled. Outside cancellation, it must also never have reached dispatch.
- **Activation:** the shipment must be Ready for Dispatch or Dispatched.

**Intentional business rule (Q4).** A blank `Fitness_Expiry__c` means fitness does not apply to that vehicle class, so it does not block allocation. When filled in, it must last through the window end, like registration and insurance.

## 4. Lifecycle and the shipment mirror

```
Planned ──▶ Active ──▶ Completed
   │
   └──────▶ Cancelled
```

- **New assignments** must start Planned. Completed and Cancelled are terminal; only `Remarks__c` may change after that.
- **Shipment link:** cannot change.
- **Status changes** cannot carry a vehicle, driver or window change. The exception is Active → Completed, which may set the actual end.
- **Active assignments:** vehicle, driver and window are frozen.
- **Planned changes:** a change of vehicle, driver or window is re-evaluated like a new allocation. The window is always re-derived from the shipment, so a caller-supplied window is ignored.

**Mirror (Q18).** The after-save trigger owns `Shipment__c.Vehicle__c` and `Driver__c`:

| Assignment becomes | Shipment fields |
|---|---|
| Planned or Active (new, or vehicle or driver changed) | Set to the assignment's vehicle and driver |
| Cancelled | Each field is cleared only if it still holds this assignment's vehicle or driver. An old assignment never clears a newer reference. |
| Completed | Kept, as history |

The write goes through the private `without sharing` `MirrorWriter`. It locks the shipments first, then updates in system mode with partial success. A failed write is reported as an error on the owning assignment, so the assignment save rolls back with it.

**Cancellation auto-release (Q11).** This runs in two trigger-only steps, which avoids `SELF_REFERENCE_FROM_TRIGGER`:
1. Shipment before-update (`clearCancelledShipmentAllocations`): on the records moving to Cancelled, clears `Vehicle__c` and `Driver__c` when they match the Planned assignment.
2. Shipment after-update (`releaseCancelledShipmentAssignments`): locks the Planned assignments and updates them to Cancelled in system mode. The mirror then has nothing to write back.

If the release fails, the shipment is refused with `eLogix_Fleet_Release_Failed`, so a cancelled shipment never keeps a live booking.

The domain accepts that release without `eLogix_Allocate_Fleet` only when the **stored** shipment status is Cancelled, the change is Planned → Cancelled, and nothing else changes (`isAutomaticRelease`). No caller-set flag exists, so the exemption cannot be borrowed for another change. A test proves this.

## 5. Security

| Path | Mode | Justification |
|---|---|---|
| Service writes (insert, update of assignments) | `AccessLevel.USER_MODE` | CRUD, FLS and sharing of the caller |
| Service access checks (shipment, vehicle, driver, assignment reads) | `WITH USER_MODE` | The caller must be able to read what they allocate |
| Enforcement reads (locks, conflicts, maintenance, shipment facts, quoted type, dispatch history) | `WITH SYSTEM_MODE` in the private `without sharing` `FleetSelector.EnforcementReader`, reachable only from its permitted trigger contexts (section 9.5) | Integrity checks must see every conflicting record, whoever owns it. With sharing, a Fleet Manager (no Quotation access, Private OWD) would get a null `Quotation__r`, and the quoted-type rule would be skipped silently. Found and fixed during check-only validation; regression test `theQuotedVehicleTypeIsEnforced`. Results feed only the rules. Messages name only the shipment, vehicle and driver the caller supplied. |
| Shipment mirror | Private `without sharing` `MirrorWriter`, system mode, trigger context only | `Vehicle__c` and `Driver__c` on Shipment are read-only for every role (protected fields). Callable only from the assignment trigger (`FLEET_MIRROR_TRIGGER_ONLY`). |
| Cancellation release | System mode, shipment trigger context only | Operations users who cancel a shipment do not hold `eLogix_Allocate_Fleet`. Callable only from the shipment trigger (`FLEET_CANCELLATION_TRIGGER_ONLY`). |

Permission changes:
- The Fleet Manager gains read-only View All on Shipment (Q13): read and View All, without create, edit, delete or Modify All.
- The Fleet Manager loses Delete on Vehicle Assignment (audit fix 1): CREV.
- No View All Data or Modify All Data was added anywhere.

## 6. Concurrency and bulk

Locks are always taken in the same order:
- **Service path:** shipments (user mode, `FOR UPDATE`), then vehicles, then drivers.
- **Direct DML path:** vehicles, then drivers.
- **Ready for Dispatch:** the shipment being saved, then vehicles, then drivers (same order as the service path).
- **Mirror:** shipments.
- **Cancellation:** the shipment being saved, then its Planned assignments.

`FOR UPDATE` cannot be combined with `ORDER BY`. The order across objects is fixed; within one object, the database locks a single statement's rows as a set.

A lock wait timeout (`UNABLE_TO_LOCK_ROW`, or a `QueryException` reporting the record as unavailable) becomes `eLogix_Fleet_Busy` on every affected row, at every lock point (section 9.4). The service reports it as the per-record code `FLEET_BUSY`, which is retryable (Q16), and never returns the raw database text. Nothing retries automatically.

Cost of `allocate` for 200 requests, measured in `twoHundredAllocationsInOneCall`:

| Part | SOQL | DML |
|---|---|---|
| Service: shipments, vehicles and drivers the caller can read | 3 | 1 (assignment insert) |
| Trigger: shipments, org time zone (cached), vehicle lock, driver lock, conflicts, maintenance | 6 | - |
| Mirror: shipment lock | 1 | 1 (shipment update) |
| **Total** | **10** | **2** |

A remarks-only save of 20 assignments costs 0 SOQL and 1 DML (`aRemarksOnlySaveCostsNothing`).

## 7. Expiry visibility (Q15)

| Field | Values | Window |
|---|---|---|
| `Vehicle__c.Document_Status__c` | Missing, Expired, Expiring Soon, Valid. Worst of registration, insurance and fitness (fitness only when filled in). | `eLogix_Setting.Document_Expiry_Warning_Days` (30) |
| `Driver__c.License_Status__c` | Missing, Expired, Expiring Soon, Valid | Same setting |

List views:
- Vehicles: Documents Expired, Documents Expiring Soon, Documents Missing.
- Drivers: Licences Expired, Licences Expiring Soon.

There is no scheduled batch: the formulas evaluate on read. `Is_Allocatable__c` is a list-view and reporting aid. The trigger always re-checks against the window end, not against today.

## 8. Known limitations

1. **Maintenance over existing bookings (Q17, deferred).** Creating or rescheduling maintenance does not check Planned assignments that already overlap it. Since audit fix 3, the conflict is caught when the shipment moves to Ready for Dispatch, but not when the maintenance is saved.
2. **Shipment date changes after allocation** do not move the assignment window by themselves. Ready for Dispatch refuses a stale window (`eLogix_Fleet_Window_Changed`). Reallocating, even to the same vehicle and driver, renews it.
3. **Recovery after first dispatch needs On Hold and a supervisor.** If an allocation becomes invalid after the shipment first reached dispatch, the shipment must be put On Hold. A user with `eLogix_Correct_Dispatched_Allocation` then corrects it (section 10.1), or the shipment is cancelled. A shipment that is Dispatched, In Transit, Delayed or Failed Delivery cannot be corrected in place.
4. **In Transit is guarded, the transition table is unchanged.** The Phase 2 configuration still allows On Hold → In Transit without Ready for Dispatch. Since round 3 the allocation guard also covers In Transit, so that route needs a valid allocation too (section 10.2).
5. **Active assignments are not auto-released.** The auto-release covers Planned assignments only, and Active → Cancelled is not an allowed transition. Phase 4 never activates assignments, so this cannot happen today. Phase 5 wires Active and Completed and must handle it: a shipment cancelled from Ready for Dispatch (permitted with `eLogix_Cancel_Confirmed_Shipment`), or under override after dispatch, would otherwise keep an Active assignment until it is completed.
6. **Initial allocation after dispatch is not locked.** Q9 locks reallocation and release. A shipment that reached dispatch with no allocation (only possible for data from before Phase 4, or through limitation 4) can still be given a first allocation while Confirmed or On Hold.
7. **Shipment deletion.** A shipment with a Planned or Active assignment cannot be deleted (section 10.3). Deleting a shipment whose assignments are all Completed or Cancelled (Administrator only, Phase 1) clears their `Shipment__c` lookup, which is the existing retention behaviour.
8. **Lock order across paths.** Each path has a fixed order (section 6). A direct edit of an assignment (assignment, then shipment) and a cancellation of the same shipment (shipment, then assignment) lock in opposite orders. The platform resolves such a deadlock by failing one save with a lock error, which is reported as `FLEET_BUSY`. Not reproducible in Apex tests.
9. **Real concurrency** cannot be reproduced in Apex tests. Every lock point's timeout handling is proven with a substituted selector (`FleetLockingTest`).
10. **Rate card region default.** `Rate_Card__c.Region__c` defaults to South (Phase 3 configuration note). It does not affect fleet rules.

## 9. Audit fixes (approved 2026-11-20)

### 9.1 No delete, no undelete (fix 1)
- `before delete` refuses every delete and `after undelete` refuses every restore, for every user including the Administrator. The message is `eLogix_Fleet_Delete_Not_Allowed`.
- Cancellation is the only release. Completed and Cancelled assignments stay as history.
- The Fleet Manager no longer holds Delete on Vehicle Assignment (least privilege, through the generator).
- Without this, a deleted booking could be restored from the Recycle Bin without any rule running, creating a double booking.

### 9.2 Allocation locked after first dispatch (fix 2, Q9)
- Once a shipment has a status event (`Tracking_Event__c.To_Status__c`) outside the pre-dispatch statuses (Draft, Requested, Quoted, Confirmed, On Hold, Cancelled), its Planned assignment can no longer be reallocated or released. The message is `eLogix_Fleet_Locked_After_Dispatch`.
- The history decides this, not the current status, so returning to On Hold or Confirmed does not reset it.
- Ready for Dispatch, every later status and any status added in future count as dispatch, as does the configured On Hold → In Transit shortcut.
- Tracking events are immutable and written only by `TrackingService`.
- Enforced in the assignment trigger, so it applies to the service and to direct DML alike.
- The automatic release on shipment cancellation is unaffected.
- Cost: one aggregate query, only for saves that reallocate or release.

### 9.3 Ready for Dispatch revalidation (fix 3, Q10)
`VehicleAssignmentDomain.checkDispatchReadiness` runs in the shipment before-update trigger, with the values being saved:
- **Matching:** `Vehicle__c` and `Driver__c` must match an open assignment (`ALLOCATION_REQUIRED`).
- **Window:** the assignment's stored window must still be the one the shipment's current dates give (`eLogix_Fleet_Window_Changed`).
- **Rules:** the assignment is re-run through every `VehicleAvailabilityService` rule against current data. That covers weight against capacity; the business units of shipment, vehicle and driver; vehicle and driver status; registration, insurance and optional fitness; the licence; maintenance; the quoted vehicle type; and overlaps (`ALLOCATION_INVALID`, with the rule's own message).
- **Self-exclusion:** the assignment is excluded from its own overlap check, both through the query's exclude list and the candidate's own Id.
- **No status gate:** the initial-allocation shipment-status gate is not applied here.
- **Locks:** vehicles, then drivers. A timeout gives `FLEET_BUSY`.
- **Validation only:** nothing is written.
- **After-update:** `TrackingService` re-evaluates the policy in the shipment after-update trigger. There the guard accepts exactly the records of that save that are now Ready for Dispatch, because they passed this check in before-update. Anywhere else the guard fails closed.

### 9.4 Lock timeouts at every lock point (fix 4, Q16)

| Lock point | Path | Result of a timeout |
|---|---|---|
| `shipmentsForAllocation` (shipments, user mode) | allocate, reallocate | Every well-formed request: `FLEET_BUSY`; malformed requests keep `REQUEST_INVALID` |
| `plannedAssignmentByShipment` | reallocate | Every request: `FLEET_BUSY` |
| `assignmentsForUpdate` | release, activate, complete | Every Id: `FLEET_BUSY` |
| `lockVehicles`, `lockDrivers` | assignment trigger; Ready for Dispatch guard | Each affected assignment or shipment: `eLogix_Fleet_Busy` |
| `lockShipmentsForMirror`, mirror update | assignment after-save trigger | Each affected assignment: `eLogix_Fleet_Busy` (the save rolls back) |
| `lockPlannedAssignmentsOfShipments`, release update | shipment after-update (cancellation) | The shipment's cancellation is refused: `eLogix_Fleet_Release_Failed` with the busy text |
| Platform `UNABLE_TO_LOCK_ROW` on DML | any service write | `FLEET_BUSY` with the busy text, never the raw database message |

### 9.5 Enforcement reads are trigger-only (fix 5)
Every public `FleetSelector` method that reaches `EnforcementReader` first checks the executing trigger's object and operation. Anything else throws `AuthorizationException` (`FLEET_ENFORCEMENT_TRIGGER_ONLY`).

| Method | Permitted contexts |
|---|---|
| `lockVehicles`, `lockDrivers`, `shipmentsForAssignments`, `openAssignmentsInWindow`, `openMaintenance` | Vehicle Assignment before insert and before update; Shipment before update (guard) |
| `shipmentsWithHistoryBeyond` | Vehicle Assignment before update |
| `openAssignmentsOfShipments` | Shipment before update |
| `lockPlannedAssignmentsOfShipments` | Shipment after update |
| `lockShipmentsForMirror` | Vehicle Assignment after insert and after update |

### 9.6 Q5 wording (fix 6)
- In Progress maintenance always blocks.
- Scheduled maintenance with no completion date blocks only its scheduled day (section 3, rule 12).
- The behaviour was already correct; only the documentation was corrected.

## 10. Workflow fixes (round 3, approved 2026-11-20)

### 10.1 Controlled recovery of a dispatched allocation
The Q9 lock stays the default. The only way to change the allocation of a shipment that has reached dispatch is a **correction**.

- **How it is requested.** A save sets a new value in `Vehicle_Assignment__c.Correction_Reason__c`. Use `FleetAllocationService.correctDispatchedAllocation`, or edit the record directly; the same trigger rules apply either way.
- **Field access.** The reason field is protected: only the Administrator and the Logistics Manager can edit it.
- **Conditions, all checked in the assignment trigger:**
  - `eLogix_Correct_Dispatched_Allocation` (Administrator and Logistics Manager), in addition to `eLogix_Allocate_Fleet`.
  - The shipment is **On Hold**, never Dispatched, In Transit, Delayed or Failed Delivery. Confirmed also does not qualify.
  - The assignment is Planned and stays Planned, so a correction is never a release.
  - The reason is not blank and differs (exactly) from the previous correction's reason.
- **Revalidation.** A correction is always revalidated in full against current data, even when the vehicle and driver do not change. That way it can renew a stale booking window. It uses the normal lock order: vehicles, then drivers.
- **History.** The after-update trigger writes an `Exception` tracking event through `TrackingService.recordEvents` (the operational-event API; the same event type a status override writes). Its remarks hold:
  - the assignment name;
  - the vehicle and driver, new and previous;
  - the renewed window;
  - the reason.

  The creator is the correcting user. If the event cannot be written (no tracking-event access, a lock timeout, any error), the correction fails with it.
- **No bypass.** There is no flag. The reason is persisted data, and changing it achieves nothing without the permission and the conditions above. Ordinary reallocation and release keep the Q9 lock.

### 10.2 In Transit needs a valid allocation
- `ShipmentAllocationGuard` now targets Ready for Dispatch **and In Transit**, from any source status: On Hold, Dispatched or Delayed.
- The check is the same `checkDispatchReadiness` as for Ready for Dispatch: matching open assignment, current window, every rule, excluding itself.
- It runs in the shipment before-update trigger, so it applies to the UI, API, Flow and services alike.
- Consequence: if a delay moves the expected delivery date, Delayed → In Transit is refused as a stale window until the allocation is corrected (On Hold, then a correction).

### 10.3 No orphaned bookings
- `ShipmentTrigger` now also runs `before delete`. `FleetAllocationService.rejectDeletionWithOpenAssignments` (trigger-only) refuses to delete a shipment that has a Planned or Active assignment, with `eLogix_Fleet_Shipment_Delete_Blocked`.
- To delete such a shipment, cancel the assignment through its lifecycle first, or cancel the shipment, which releases it.
- Completed and Cancelled assignments keep the existing behaviour: the lookup is cleared and the history row stays.
