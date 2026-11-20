/**
 * Vehicle assignment rules that must hold on every entry path: FleetAllocationService, the UI, the
 * API, Data Loader and other automation (decision Q14). Called by VehicleAssignmentTriggerHandler and,
 * for the Ready for Dispatch and In Transit revalidation, by ShipmentAllocationGuard.
 * See docs/FLEET_IMPLEMENTATION.md and docs/PHASE4_PLAN.md section 0.
 *
 * before insert   eLogix_Allocate_Fleet; status Planned; shipment required; shipment Confirmed or On Hold
 *                 (Q9); window derived from the shipment (Q3); every eligibility rule, under row locks
 * before update   shipment link immutable; Q12 transitions (Planned -> Active | Cancelled; Active ->
 *                 Completed; Completed and Cancelled terminal); vehicle, driver and window frozen once
 *                 Active; a Planned vehicle or driver change is re-evaluated like a new allocation; no
 *                 reallocation or release once the shipment has ever reached Ready for Dispatch (Q9),
 *                 except a controlled correction (new Correction_Reason__c, eLogix_Correct_Dispatched_
 *                 Allocation, shipment On Hold), which is always revalidated in full
 * after update    correction history (recordCorrections)
 * before delete   always refused: assignments are released by cancellation and kept as history
 * after undelete  always refused (a restored row would skip every rule)
 * after save      mirror Vehicle__c / Driver__c onto the shipment (Q18), from the trigger context only
 *
 * Permission: every insert and update needs eLogix_Allocate_Fleet, with one state-justified
 * exception and no caller-controlled flag: a Planned assignment may be cancelled, with no other
 * change, when its shipment is already Cancelled (the automatic release of Q11).
 */
public with sharing class VehicleAssignmentDomain {
    public static final String PLANNED = 'Planned';
    public static final String ACTIVE = 'Active';
    public static final String COMPLETED = 'Completed';
    public static final String CANCELLED = 'Cancelled';
    public static final String ALLOCATE_PERMISSION = 'eLogix_Allocate_Fleet';
    public static final String FLEET_BUSY = 'FLEET_BUSY';
    public static final String MIRROR_TRIGGER_ONLY = 'FLEET_MIRROR_TRIGGER_ONLY';
    public static final String CORRECTION_TRIGGER_ONLY = 'FLEET_CORRECTION_TRIGGER_ONLY';
    /** Controlled recovery of a dispatched allocation (audit round 3, issue 1). Needs ALLOCATE_PERMISSION too. */
    public static final String CORRECT_PERMISSION = 'eLogix_Correct_Dispatched_Allocation';
    /** Tracking event type for allocation corrections: the operational type also used for status overrides. */
    public static final String CORRECTION_EVENT_TYPE = 'Exception';
    /** Ready for Dispatch / In Transit guard codes. */
    public static final String ALLOCATION_REQUIRED = 'ALLOCATION_REQUIRED';
    public static final String ALLOCATION_INVALID = 'ALLOCATION_INVALID';

    /** Shipment statuses in which a vehicle may be allocated, changed or released (Q9). */
    @TestVisible
    private static final Set<String> ALLOCATABLE_SHIPMENT_STATUSES = new Set<String>{ 'Confirmed', 'On Hold' };
    /**
     * Phase 5: a Planned assignment becomes Active only once its shipment has been dispatched: through
     * Ready for Dispatch to Dispatched, or the configured On Hold -> In Transit route. Both transitions
     * pass the allocation guard, so the stored status proves a validated transition.
     */
    @TestVisible
    private static final Set<String> ACTIVATING_SHIPMENT_STATUSES = new Set<String>{ 'Dispatched', 'In Transit' };
    /** Phase 5: an Active assignment is Completed only once its shipment's trip has ended (D2 includes Cancelled). */
    @TestVisible
    private static final Set<String> TRIP_ENDING_SHIPMENT_STATUSES = new Set<String>{ 'Delivered', 'Damaged', 'Lost', 'Return Initiated', 'Cancelled' };
    /**
     * Q9: statuses a shipment can hold before it is first dispatched. A status event to any other
     * status (Ready for Dispatch, Dispatched, In Transit and every later or exception status, including
     * statuses added in future) means the shipment has reached dispatch, and its allocation is locked.
     */
    @TestVisible
    private static final Set<String> PRE_DISPATCH_STATUSES = new Set<String>{ 'Draft', 'Requested', 'Quoted', 'Confirmed', 'On Hold', 'Cancelled' };
    private static final String SHIPMENT_CANCELLED = 'Cancelled';
    private static final String SHIPMENT_ON_HOLD = 'On Hold';

    @TestVisible
    private static final Map<String, Set<String>> ALLOWED_TRANSITIONS = new Map<String, Set<String>>{
        PLANNED => new Set<String>{ ACTIVE, CANCELLED },
        ACTIVE => new Set<String>{ COMPLETED }
    };

    /** Test seam for lock timeouts (Q16): a test substitutes a selector whose lock query fails. */
    @TestVisible
    private static FleetSelector selector = new FleetSelector();

    /* ------------------------------------------------------------------ */
    /* Before insert                                                       */
    /* ------------------------------------------------------------------ */

    public void validateNew(List<Vehicle_Assignment__c> records) {
        Boolean allowed = PermissionService.hasPermission(ALLOCATE_PERMISSION);
        List<Vehicle_Assignment__c> toEvaluate = new List<Vehicle_Assignment__c>();
        for (Vehicle_Assignment__c assignment : records) {
            if (!allowed) {
                assignment.addError(Label.eLogix_Fleet_Permission_Required);
            } else if (!PLANNED.equals(assignment.Status__c)) {
                assignment.addError(Label.eLogix_Fleet_Must_Start_Planned);
            } else if (String.isNotBlank(assignment.Correction_Reason__c)) {
                // A first allocation is not a correction; the field records corrections only.
                assignment.addError(Label.eLogix_Fleet_Correction_Not_Allowed);
            } else if (assignment.Shipment__c == null) {
                assignment.addError(Label.eLogix_Fleet_Shipment_Required);
            } else {
                toEvaluate.add(assignment);
            }
        }
        Set<Id> shipmentIds = shipmentIdsOf(toEvaluate);
        evaluate(toEvaluate, shipmentIds.isEmpty() ? new Map<Id, Shipment__c>() : selector.shipmentsForAssignments(shipmentIds));
    }

    /* ------------------------------------------------------------------ */
    /* Before update                                                       */
    /* ------------------------------------------------------------------ */

    public void validateChanges(List<Vehicle_Assignment__c> records, Map<Id, Vehicle_Assignment__c> oldById) {
        Boolean allowed = PermissionService.hasPermission(ALLOCATE_PERMISSION);
        Boolean canCorrect = PermissionService.hasPermission(CORRECT_PERMISSION);
        // Shipment facts are needed only for status, vehicle, driver, window or correction changes; a
        // save that changes none of them (for example remarks only) costs no SOQL.
        Set<Id> shipmentIds = new Set<Id>();
        for (Vehicle_Assignment__c assignment : records) {
            Vehicle_Assignment__c previous = oldById.get(assignment.Id);
            Boolean relevant =
                assignment.Status__c != previous.Status__c ||
                allocationChanged(assignment, previous) ||
                endChanged(assignment, previous) ||
                correctionRequested(assignment, previous);
            if (relevant && assignment.Shipment__c != null) {
                shipmentIds.add(assignment.Shipment__c);
            }
        }
        Map<Id, Shipment__c> shipments = shipmentIds.isEmpty() ? new Map<Id, Shipment__c>() : selector.shipmentsForAssignments(shipmentIds);

        // Pass 1: transitions, permission, immutability, status gates and correction requests.
        List<Vehicle_Assignment__c> passed = new List<Vehicle_Assignment__c>();
        Set<Id> lockCandidates = new Set<Id>();
        Set<Id> corrections = new Set<Id>();
        for (Vehicle_Assignment__c assignment : records) {
            Vehicle_Assignment__c previous = oldById.get(assignment.Id);
            Shipment__c shipment = shipments.get(assignment.Shipment__c);
            String error = changeError(assignment, previous, shipment, allowed);
            if (error == null && correctionRequested(assignment, previous)) {
                error = correctionError(assignment, previous, shipment, canCorrect);
                if (error == null) {
                    corrections.add(assignment.Id);
                }
            }
            if (error != null) {
                assignment.addError(error);
                continue;
            }
            passed.add(assignment);
            if (!corrections.contains(assignment.Id) && isReallocationOrRelease(assignment, previous, shipment)) {
                lockCandidates.add(assignment.Shipment__c);
            }
        }

        // Pass 2 (Q9): a shipment that has ever reached Ready for Dispatch keeps its allocation, even
        // after it returns to On Hold or Confirmed. Decided from its immutable status history.
        Set<Id> dispatched = lockCandidates.isEmpty()
            ? new Set<Id>()
            : selector.shipmentsWithHistoryBeyond(lockCandidates, PRE_DISPATCH_STATUSES);

        List<Vehicle_Assignment__c> toEvaluate = new List<Vehicle_Assignment__c>();
        for (Vehicle_Assignment__c assignment : passed) {
            Vehicle_Assignment__c previous = oldById.get(assignment.Id);
            Shipment__c shipment = shipments.get(assignment.Shipment__c);
            if (corrections.contains(assignment.Id)) {
                // A correction is always revalidated in full against current data, even when the
                // vehicle and driver stay the same (it may only renew the window).
                toEvaluate.add(assignment);
            } else if (dispatched.contains(assignment.Shipment__c) && isReallocationOrRelease(assignment, previous, shipment)) {
                assignment.addError(format(Label.eLogix_Fleet_Locked_After_Dispatch, shipment?.Name, null));
            } else if (PLANNED.equals(assignment.Status__c) && (allocationChanged(assignment, previous) || endChanged(assignment, previous))) {
                // A Planned change of vehicle, driver or window is re-evaluated like a new allocation.
                toEvaluate.add(assignment);
            }
        }
        evaluate(toEvaluate, shipments);
    }

    /**
     * Q9: a Planned assignment whose vehicle, driver or window changes, or which is released while
     * its shipment is still live. The automatic release on shipment cancellation (Q11) is not one.
     */
    private static Boolean isReallocationOrRelease(Vehicle_Assignment__c assignment, Vehicle_Assignment__c previous, Shipment__c shipment) {
        if (!PLANNED.equals(previous.Status__c) || shipment == null || SHIPMENT_CANCELLED.equals(shipment.Status__c)) {
            return false;
        }
        Boolean releasing = CANCELLED.equals(assignment.Status__c);
        Boolean changing = PLANNED.equals(assignment.Status__c) && (allocationChanged(assignment, previous) || endChanged(assignment, previous));
        return releasing || changing;
    }

    /** A save that sets a new correction reason asks for a correction of a dispatched allocation. */
    private static Boolean correctionRequested(Vehicle_Assignment__c assignment, Vehicle_Assignment__c previous) {
        return !sameText(assignment.Correction_Reason__c, previous.Correction_Reason__c);
    }

    /** Exact (case-sensitive) comparison; Apex == on strings ignores case. */
    public static Boolean sameText(String first, String second) {
        return first == null ? second == null : first.equals(second);
    }

    /**
     * Controlled recovery (audit round 3, issue 1): the only way to change the allocation of a shipment
     * that has reached dispatch. Not a bypass: it needs eLogix_Correct_Dispatched_Allocation (on top
     * of eLogix_Allocate_Fleet, checked in changeError), a shipment that is On Hold (never Dispatched,
     * In Transit, Delayed or Failed Delivery), a Planned assignment that stays Planned, and a
     * non-blank reason. The change is then revalidated in full and written to tracking history.
     */
    private static String correctionError(Vehicle_Assignment__c assignment, Vehicle_Assignment__c previous, Shipment__c shipment, Boolean canCorrect) {
        Boolean permitted =
            canCorrect &&
            PLANNED.equals(previous.Status__c) &&
            PLANNED.equals(assignment.Status__c) &&
            shipment != null &&
            SHIPMENT_ON_HOLD.equals(shipment.Status__c) &&
            String.isNotBlank(assignment.Correction_Reason__c);
        return permitted ? null : Label.eLogix_Fleet_Correction_Not_Allowed;
    }

    private static String changeError(Vehicle_Assignment__c assignment, Vehicle_Assignment__c previous, Shipment__c shipment, Boolean allowed) {
        if (assignment.Shipment__c != previous.Shipment__c) {
            return Label.eLogix_Fleet_Shipment_Immutable;
        }
        String fromStatus = previous.Status__c;
        String toStatus = assignment.Status__c;
        Boolean statusChanged = fromStatus != toStatus;

        // Terminal assignments are history: nothing but remarks may change.
        if (COMPLETED.equals(fromStatus) || CANCELLED.equals(fromStatus)) {
            if (statusChanged || allocationChanged(assignment, previous) || assignment.Assignment_End__c != previous.Assignment_End__c) {
                return format(Label.eLogix_Fleet_Assignment_Locked, fromStatus, null);
            }
        }
        if (statusChanged) {
            Set<String> allowedTargets = ALLOWED_TRANSITIONS.get(fromStatus);
            if (allowedTargets == null || !allowedTargets.contains(toStatus)) {
                return format(Label.eLogix_Fleet_Transition_Not_Allowed, fromStatus, toStatus);
            }
            // A status change cannot carry a vehicle, driver or window change; only completion sets the end.
            Boolean completing = ACTIVE.equals(fromStatus) && COMPLETED.equals(toStatus);
            if (allocationChanged(assignment, previous) || (endChanged(assignment, previous) && !completing)) {
                return format(Label.eLogix_Fleet_Assignment_Locked, fromStatus, null);
            }
        }
        if (!allowed && !isAutomaticRelease(assignment, previous, shipment) && !isAutomaticLifecycle(assignment, previous, shipment)) {
            return Label.eLogix_Fleet_Permission_Required;
        }
        // Once Active, the vehicle, driver and window are fixed; only completion may set the end.
        if (ACTIVE.equals(fromStatus)) {
            Boolean endChanged = assignment.Assignment_End__c != previous.Assignment_End__c;
            if (allocationChanged(assignment, previous) || (endChanged && !COMPLETED.equals(toStatus))) {
                return format(Label.eLogix_Fleet_Assignment_Locked, ACTIVE, null);
            }
            if (COMPLETED.equals(toStatus) && !TRIP_ENDING_SHIPMENT_STATUSES.contains(shipment?.Status__c)) {
                return format(Label.eLogix_Fleet_Completion_Status, shipment?.Name, shipment?.Status__c);
            }
        }
        if (PLANNED.equals(fromStatus)) {
            String shipmentStatus = shipment?.Status__c;
            if (ACTIVE.equals(toStatus) && !ACTIVATING_SHIPMENT_STATUSES.contains(shipmentStatus)) {
                return format(Label.eLogix_Fleet_Activation_Status, shipment?.Name, shipmentStatus);
            }
            Boolean releasing = CANCELLED.equals(toStatus);
            Boolean changingAllocation = !statusChanged && (allocationChanged(assignment, previous) || endChanged(assignment, previous));
            Boolean releasable = ALLOCATABLE_SHIPMENT_STATUSES.contains(shipmentStatus) || SHIPMENT_CANCELLED.equals(shipmentStatus);
            if ((releasing && !releasable) || (changingAllocation && !ALLOCATABLE_SHIPMENT_STATUSES.contains(shipmentStatus))) {
                return format(Label.eLogix_Fleet_Shipment_Status, shipment?.Name, shipmentStatus);
            }
        }
        return null;
    }

    /**
     * Q11: the automatic release is justified by the stored shipment state, not by any caller-set
     * value: Planned -> Cancelled, nothing else changed, and the shipment is already Cancelled.
     */
    private static Boolean isAutomaticRelease(Vehicle_Assignment__c assignment, Vehicle_Assignment__c previous, Shipment__c shipment) {
        return PLANNED.equals(previous.Status__c) &&
            CANCELLED.equals(assignment.Status__c) &&
            !allocationChanged(assignment, previous) &&
            assignment.Assignment_End__c == previous.Assignment_End__c &&
            assignment.Remarks__c == previous.Remarks__c &&
            shipment != null &&
            SHIPMENT_CANCELLED.equals(shipment.Status__c);
    }

    /**
     * Phase 5: the automatic lifecycle, justified only by the stored shipment status that a validated
     * transition produced, never by a caller-set value. Planned -> Active with nothing else changed
     * while the shipment is Dispatched or In Transit; Active -> Completed, changing at most the actual
     * end, once the shipment's trip has ended. Anything else still needs eLogix_Allocate_Fleet.
     */
    private static Boolean isAutomaticLifecycle(Vehicle_Assignment__c assignment, Vehicle_Assignment__c previous, Shipment__c shipment) {
        if (shipment == null || allocationChanged(assignment, previous) || !sameText(assignment.Remarks__c, previous.Remarks__c)) {
            return false;
        }
        Boolean activating =
            PLANNED.equals(previous.Status__c) &&
            ACTIVE.equals(assignment.Status__c) &&
            !endChanged(assignment, previous) &&
            ACTIVATING_SHIPMENT_STATUSES.contains(shipment.Status__c);
        Boolean completing =
            ACTIVE.equals(previous.Status__c) &&
            COMPLETED.equals(assignment.Status__c) &&
            TRIP_ENDING_SHIPMENT_STATUSES.contains(shipment.Status__c);
        return activating || completing;
    }

    private static Boolean endChanged(Vehicle_Assignment__c assignment, Vehicle_Assignment__c previous) {
        return assignment.Assignment_End__c != previous.Assignment_End__c;
    }

    /** Vehicle, driver, start or business unit changed (the window end is checked separately). */
    private static Boolean allocationChanged(Vehicle_Assignment__c assignment, Vehicle_Assignment__c previous) {
        return assignment.Vehicle__c != previous.Vehicle__c ||
            assignment.Driver__c != previous.Driver__c ||
            assignment.Assignment_Start__c != previous.Assignment_Start__c ||
            assignment.Business_Unit__c != previous.Business_Unit__c;
    }

    /* ------------------------------------------------------------------ */
    /* Before delete / after undelete                                      */
    /* ------------------------------------------------------------------ */

    /**
     * Deleting an assignment would free its vehicle and driver without the lifecycle (and could later
     * be undone from the Recycle Bin without any rule running), and would destroy Completed and
     * Cancelled history. Refused for every user, Administrator included; release is by cancellation.
     */
    public void rejectDeletion(List<SObject> records) {
        for (SObject assignment : records) {
            assignment.addError(Label.eLogix_Fleet_Delete_Not_Allowed);
        }
    }

    /** A restored assignment would re-enter the booking table without any rule running. */
    public void rejectRestore(List<SObject> records) {
        for (SObject assignment : records) {
            assignment.addError(Label.eLogix_Fleet_Delete_Not_Allowed);
        }
    }

    /* ------------------------------------------------------------------ */
    /* Evaluation                                                          */
    /* ------------------------------------------------------------------ */

    /**
     * Gates the shipment status, derives the window and business unit from the shipment, locks the
     * vehicles and drivers (vehicles first, then drivers), loads conflicts and maintenance, and applies
     * VehicleAvailabilityService. Cost: 4 SOQL for the whole batch.
     */
    private void evaluate(List<Vehicle_Assignment__c> records, Map<Id, Shipment__c> shipments) {
        if (records.isEmpty()) {
            return;
        }
        List<VehicleAvailabilityService.Candidate> candidates = new List<VehicleAvailabilityService.Candidate>();
        Map<Integer, Vehicle_Assignment__c> recordByIndex = new Map<Integer, Vehicle_Assignment__c>();
        for (Vehicle_Assignment__c assignment : records) {
            Shipment__c shipment = shipments.get(assignment.Shipment__c);
            if (shipment == null) {
                assignment.addError(format(Label.eLogix_Fleet_Record_Not_Found, assignment.Shipment__c, null));
                continue;
            }
            if (!ALLOCATABLE_SHIPMENT_STATUSES.contains(shipment.Status__c)) {
                assignment.addError(format(Label.eLogix_Fleet_Shipment_Status, shipment.Name, shipment.Status__c));
                continue;
            }
            VehicleAvailabilityService.Candidate candidate = candidateFor(assignment, shipment, candidates.size());
            if (candidate.startAt != null) {
                // Q3: the window always comes from the shipment, whatever the caller supplied.
                assignment.Assignment_Start__c = candidate.startAt;
                assignment.Assignment_End__c = candidate.endAt;
            }
            assignment.Business_Unit__c = shipment.Business_Unit__c;
            candidates.add(candidate);
            recordByIndex.put(candidate.index, assignment);
        }
        Map<Integer, VehicleAvailabilityService.Violation> violations = evaluateCandidates(candidates, shipments);
        for (Integer index : violations.keySet()) {
            recordByIndex.get(index).addError(violations.get(index).message);
        }
    }

    /** A candidate with the window derived from the shipment's current dates (Q3), when they are valid. */
    private static VehicleAvailabilityService.Candidate candidateFor(Vehicle_Assignment__c assignment, Shipment__c shipment, Integer index) {
        VehicleAvailabilityService.Candidate candidate = new VehicleAvailabilityService.Candidate();
        candidate.index = index;
        candidate.assignmentId = assignment.Id;
        candidate.shipmentId = shipment.Id;
        candidate.vehicleId = assignment.Vehicle__c;
        candidate.driverId = assignment.Driver__c;
        candidate.startDate = shipment.Pickup_Date__c;
        candidate.endDate = shipment.Expected_Delivery_Date__c;
        if (candidate.startDate != null && candidate.endDate != null && candidate.endDate >= candidate.startDate) {
            candidate.startAt = AssignmentWindow.startOf(candidate.startDate);
            candidate.endAt = AssignmentWindow.endOf(candidate.endDate);
        }
        return candidate;
    }

    /**
     * Locks the candidates' vehicles, then drivers, loads overlapping open assignments (excluding the
     * candidates' own rows) and maintenance, and applies the rules. A lock timeout becomes the
     * retryable eLogix_Fleet_Busy violation on every candidate (Q16); nothing is retried.
     */
    private Map<Integer, VehicleAvailabilityService.Violation> evaluateCandidates(
        List<VehicleAvailabilityService.Candidate> candidates,
        Map<Id, Shipment__c> shipments
    ) {
        Map<Integer, VehicleAvailabilityService.Violation> violations = new Map<Integer, VehicleAvailabilityService.Violation>();
        if (candidates.isEmpty()) {
            return violations;
        }
        Set<Id> vehicleIds = new Set<Id>();
        Set<Id> driverIds = new Set<Id>();
        Set<Id> selfIds = new Set<Id>();
        Set<Id> shipmentIds = new Set<Id>();
        Datetime earliest;
        Datetime latest;
        for (VehicleAvailabilityService.Candidate candidate : candidates) {
            vehicleIds.add(candidate.vehicleId);
            driverIds.add(candidate.driverId);
            shipmentIds.add(candidate.shipmentId);
            if (candidate.assignmentId != null) {
                selfIds.add(candidate.assignmentId);
            }
            if (candidate.startAt != null) {
                earliest = earliest == null || candidate.startAt < earliest ? candidate.startAt : earliest;
                latest = latest == null || candidate.endAt > latest ? candidate.endAt : latest;
            }
        }
        vehicleIds.remove(null);
        driverIds.remove(null);

        VehicleAvailabilityService.Context context = new VehicleAvailabilityService.Context();
        context.shipments = shipments;
        try {
            context.vehicles = selector.lockVehicles(vehicleIds);
            context.drivers = selector.lockDrivers(driverIds);
        } catch (QueryException e) {
            if (!isLockTimeout(e)) {
                throw e;
            }
            Logger.warn('VehicleAssignmentDomain.evaluate', 'Fleet lock timeout for ' + candidates.size() + ' assignments.');
            for (VehicleAvailabilityService.Candidate candidate : candidates) {
                violations.put(candidate.index, new VehicleAvailabilityService.Violation(FLEET_BUSY, Label.eLogix_Fleet_Busy));
            }
            return violations;
        }
        if (earliest != null) {
            context.openAssignments = selector.openAssignmentsInWindow(shipmentIds, vehicleIds, driverIds, earliest, latest, selfIds);
        }
        context.maintenance = selector.openMaintenance(vehicleIds);
        return new VehicleAvailabilityService().evaluate(candidates, context);
    }

    /* ------------------------------------------------------------------ */
    /* Ready for Dispatch and In Transit revalidation (Q10, audit fixes)  */
    /* ------------------------------------------------------------------ */

    /**
     * For shipments moving to Ready for Dispatch or In Transit (the Shipment__c before-update records, with their
     * current values): each must carry a vehicle and driver that match an open assignment, and that
     * assignment must still pass every eligibility rule against current data: shipment weight,
     * business unit and dates, vehicle status, capacity, documents and maintenance, driver status and
     * licence, quoted vehicle type, and no overlapping booking other than itself. The stored window must
     * still be the one the shipment's current dates give (Q3); otherwise the assignment is stale.
     *
     * Validation only: no assignment or shipment is written. Shipment statuses are not gated here: the
     * initial-allocation gate does not apply (the shipment may be leaving Confirmed, On Hold, Dispatched
     * or Delayed). Returns violations by shipment Id.
     */
    public Map<Id, VehicleAvailabilityService.Violation> checkDispatchReadiness(List<Shipment__c> shipments) {
        Map<Id, VehicleAvailabilityService.Violation> violations = new Map<Id, VehicleAvailabilityService.Violation>();
        Set<Id> shipmentIds = new Set<Id>();
        for (Shipment__c shipment : shipments) {
            if (shipment.Id != null) {
                shipmentIds.add(shipment.Id);
            }
        }
        Map<String, Vehicle_Assignment__c> openByKey = new Map<String, Vehicle_Assignment__c>();
        if (!shipmentIds.isEmpty()) {
            for (Vehicle_Assignment__c assignment : selector.openAssignmentsOfShipments(shipmentIds)) {
                openByKey.put(allocationKey(assignment.Shipment__c, assignment.Vehicle__c, assignment.Driver__c), assignment);
            }
        }

        Map<Id, Vehicle_Assignment__c> matched = new Map<Id, Vehicle_Assignment__c>();
        for (Shipment__c shipment : shipments) {
            Vehicle_Assignment__c assignment = shipment.Id == null || shipment.Vehicle__c == null || shipment.Driver__c == null
                ? null
                : openByKey.get(allocationKey(shipment.Id, shipment.Vehicle__c, shipment.Driver__c));
            if (assignment == null) {
                violations.put(shipment.Id, new VehicleAvailabilityService.Violation(ALLOCATION_REQUIRED, Label.eLogix_Fleet_Allocation_Required));
            } else {
                matched.put(shipment.Id, assignment);
            }
        }
        if (matched.isEmpty()) {
            return violations;
        }

        // Stored facts give the name and the quoted vehicle type; the values being saved now win.
        Map<Id, Shipment__c> facts = selector.shipmentsForAssignments(matched.keySet());
        List<VehicleAvailabilityService.Candidate> candidates = new List<VehicleAvailabilityService.Candidate>();
        Map<Integer, Id> shipmentByIndex = new Map<Integer, Id>();
        for (Shipment__c shipment : shipments) {
            Vehicle_Assignment__c assignment = matched.get(shipment.Id);
            Shipment__c current = assignment == null ? null : facts.get(shipment.Id);
            if (current == null) {
                continue;
            }
            current.Weight__c = shipment.Weight__c;
            current.Business_Unit__c = shipment.Business_Unit__c;
            current.Pickup_Date__c = shipment.Pickup_Date__c;
            current.Expected_Delivery_Date__c = shipment.Expected_Delivery_Date__c;

            VehicleAvailabilityService.Candidate candidate = candidateFor(assignment, current, candidates.size());
            // Phase 5 (D3): an Active trip is open-ended, so its planned window cannot go stale.
            Boolean planned = !ACTIVE.equals(assignment.Status__c);
            if (planned && candidate.startAt != null && (candidate.startAt != assignment.Assignment_Start__c || candidate.endAt != assignment.Assignment_End__c)) {
                violations.put(
                    shipment.Id,
                    new VehicleAvailabilityService.Violation(ALLOCATION_INVALID, format(Label.eLogix_Fleet_Window_Changed, current.Name, null))
                );
                continue;
            }
            candidates.add(candidate);
            shipmentByIndex.put(candidate.index, shipment.Id);
        }

        Map<Integer, VehicleAvailabilityService.Violation> ruleViolations = evaluateCandidates(candidates, facts);
        for (Integer index : ruleViolations.keySet()) {
            VehicleAvailabilityService.Violation violation = ruleViolations.get(index);
            violations.put(
                shipmentByIndex.get(index),
                FLEET_BUSY.equals(violation.code)
                    ? violation
                    : new VehicleAvailabilityService.Violation(
                          ALLOCATION_INVALID,
                          format(Label.eLogix_Fleet_Allocation_Invalid, violation.message, null)
                      )
            );
        }
        return violations;
    }

    private static String allocationKey(Id shipmentId, Id vehicleId, Id driverId) {
        return shipmentId + '|' + vehicleId + '|' + driverId;
    }

    /** Q16: true for a row-lock wait timeout, whether raised by a FOR UPDATE query or by DML. */
    public static Boolean isLockTimeout(Exception e) {
        return e != null && isLockTimeoutMessage(e.getMessage());
    }

    public static Boolean isLockTimeout(Database.Error error) {
        return error != null && (error.getStatusCode() == StatusCode.UNABLE_TO_LOCK_ROW || isLockTimeoutMessage(error.getMessage()));
    }

    public static Boolean isLockTimeoutMessage(String message) {
        String text = message == null ? '' : message;
        return text.contains('UNABLE_TO_LOCK_ROW') || text.contains('Record Currently Unavailable');
    }

    /* ------------------------------------------------------------------ */
    /* After insert / after update: shipment mirror (decision Q18)         */
    /* ------------------------------------------------------------------ */

    /**
     * Keeps Shipment__c.Vehicle__c and Driver__c in step with the assignments in the current trigger.
     * Takes no arguments: it reads Trigger.new and Trigger.oldMap itself and refuses to run outside a
     * Vehicle_Assignment__c after-save trigger (the Phase 2 F1 pattern), so no caller can point a
     * shipment at a vehicle that did not pass the rules.
     *
     * Planned or Active (new, or vehicle/driver changed): set. Cancelled: clear each field only if it
     * still references this assignment's vehicle or driver, so an old assignment can never clear a newer
     * one. Completed: kept as history. A shipment that cannot be updated fails only its own assignment;
     * a lock timeout fails the affected assignments with the retryable eLogix_Fleet_Busy (Q16).
     */
    public void syncShipments() {
        if (!isAssignmentAfterSaveTrigger()) {
            throw new AuthorizationException(Label.eLogix_Access_Denied).withCode(MIRROR_TRIGGER_ONLY);
        }
        List<Vehicle_Assignment__c> records = (List<Vehicle_Assignment__c>) Trigger.new;
        Map<Id, Vehicle_Assignment__c> oldById = Trigger.isInsert ? null : (Map<Id, Vehicle_Assignment__c>) Trigger.oldMap;

        List<Vehicle_Assignment__c> setting = new List<Vehicle_Assignment__c>();
        List<Vehicle_Assignment__c> clearing = new List<Vehicle_Assignment__c>();
        Set<Id> shipmentIds = new Set<Id>();
        for (Vehicle_Assignment__c assignment : records) {
            Vehicle_Assignment__c previous = oldById == null ? null : oldById.get(assignment.Id);
            Boolean open = FleetSelector.OPEN_STATUSES.contains(assignment.Status__c);
            if (open && (previous == null || previous.Vehicle__c != assignment.Vehicle__c || previous.Driver__c != assignment.Driver__c)) {
                setting.add(assignment);
                shipmentIds.add(assignment.Shipment__c);
            } else if (CANCELLED.equals(assignment.Status__c) && previous != null && !CANCELLED.equals(previous.Status__c)) {
                clearing.add(assignment);
                shipmentIds.add(assignment.Shipment__c);
            }
        }
        shipmentIds.remove(null);
        if (shipmentIds.isEmpty()) {
            return;
        }

        MirrorWriter writer = new MirrorWriter();
        Map<Id, Shipment__c> current;
        try {
            current = writer.lockShipments(shipmentIds);
        } catch (QueryException e) {
            if (!isLockTimeout(e)) {
                throw e;
            }
            Logger.warn('VehicleAssignmentDomain.syncShipments', 'Shipment lock timeout for ' + shipmentIds.size() + ' shipments.');
            for (Vehicle_Assignment__c assignment : setting) {
                assignment.addError(Label.eLogix_Fleet_Busy);
            }
            for (Vehicle_Assignment__c assignment : clearing) {
                assignment.addError(Label.eLogix_Fleet_Busy);
            }
            return;
        }
        Map<Id, Shipment__c> updates = new Map<Id, Shipment__c>();
        Map<Id, Vehicle_Assignment__c> ownerByShipment = new Map<Id, Vehicle_Assignment__c>();
        for (Vehicle_Assignment__c assignment : setting) {
            Shipment__c shipment = current.get(assignment.Shipment__c);
            if (shipment != null && (shipment.Vehicle__c != assignment.Vehicle__c || shipment.Driver__c != assignment.Driver__c)) {
                updates.put(shipment.Id, new Shipment__c(Id = shipment.Id, Vehicle__c = assignment.Vehicle__c, Driver__c = assignment.Driver__c));
                ownerByShipment.put(shipment.Id, assignment);
            }
        }
        for (Vehicle_Assignment__c assignment : clearing) {
            Shipment__c shipment = current.get(assignment.Shipment__c);
            if (shipment == null || updates.containsKey(shipment.Id)) {
                continue;
            }
            Shipment__c change = new Shipment__c(Id = shipment.Id);
            Boolean changed = false;
            if (shipment.Vehicle__c != null && shipment.Vehicle__c == assignment.Vehicle__c) {
                change.Vehicle__c = null;
                changed = true;
            }
            if (shipment.Driver__c != null && shipment.Driver__c == assignment.Driver__c) {
                change.Driver__c = null;
                changed = true;
            }
            if (changed) {
                updates.put(shipment.Id, change);
                ownerByShipment.put(shipment.Id, assignment);
            }
        }
        if (updates.isEmpty()) {
            return;
        }
        List<Shipment__c> changes = updates.values();
        List<Database.SaveResult> results = writer.updateShipments(changes);
        for (Integer i = 0; i < results.size(); i++) {
            if (!results[i].isSuccess()) {
                Database.Error error = results[i].getErrors()[0];
                ownerByShipment.get(changes[i].Id)
                    .addError(
                        isLockTimeout(error)
                            ? Label.eLogix_Fleet_Busy
                            : format(Label.eLogix_Fleet_Shipment_Sync_Failed, current.get(changes[i].Id).Name, error.getMessage())
                    );
            }
        }
    }

    /**
     * Writes one tracking event per allocation correction in the current Vehicle_Assignment__c
     * after-update trigger, through TrackingService.recordEvents (the operational-event API: the user
     * must be able to create tracking events and read the shipment). The event is an Exception event,
     * like a status override, whose remarks name the assignment, the vehicle and driver before and
     * after, the renewed window and the reason; its creator is the correcting user. If the event
     * cannot be written, the correction fails with it: no correction goes unrecorded. Takes no
     * arguments and refuses to run outside that trigger.
     */
    public void recordCorrections() {
        if (!(Trigger.isExecuting && Trigger.operationType == System.TriggerOperation.AFTER_UPDATE && Trigger.new != null &&
            Trigger.new.getSObjectType() == Vehicle_Assignment__c.SObjectType)) {
            throw new AuthorizationException(Label.eLogix_Access_Denied).withCode(CORRECTION_TRIGGER_ONLY);
        }
        Map<Id, Vehicle_Assignment__c> oldById = (Map<Id, Vehicle_Assignment__c>) Trigger.oldMap;
        List<Vehicle_Assignment__c> corrected = new List<Vehicle_Assignment__c>();
        Set<Id> vehicleIds = new Set<Id>();
        Set<Id> driverIds = new Set<Id>();
        for (Vehicle_Assignment__c assignment : (List<Vehicle_Assignment__c>) Trigger.new) {
            Vehicle_Assignment__c previous = oldById.get(assignment.Id);
            if (correctionRequested(assignment, previous)) {
                corrected.add(assignment);
                vehicleIds.addAll(new Set<Id>{ assignment.Vehicle__c, previous.Vehicle__c });
                driverIds.addAll(new Set<Id>{ assignment.Driver__c, previous.Driver__c });
            }
        }
        if (corrected.isEmpty()) {
            return;
        }
        Map<Id, String> names = selector.vehicleAndDriverNames(vehicleIds, driverIds);
        List<TrackingEventRequest> requests = new List<TrackingEventRequest>();
        for (Vehicle_Assignment__c assignment : corrected) {
            Vehicle_Assignment__c previous = oldById.get(assignment.Id);
            TrackingEventRequest request = new TrackingEventRequest(assignment.Shipment__c, CORRECTION_EVENT_TYPE, null);
            request.source = TrackingService.SOURCE_APEX;
            request.remarks = String.format(
                Label.eLogix_Fleet_Correction_Event,
                new List<Object>{
                    assignment.Name,
                    nameOf(names, assignment.Vehicle__c),
                    nameOf(names, previous.Vehicle__c),
                    nameOf(names, assignment.Driver__c),
                    nameOf(names, previous.Driver__c),
                    assignment.Assignment_Start__c?.format(),
                    assignment.Assignment_End__c?.format(),
                    assignment.Correction_Reason__c
                }
            );
            requests.add(request);
        }
        ServiceResult result;
        try {
            result = new TrackingService().recordEvents(requests);
        } catch (AuthorizationException e) {
            for (Vehicle_Assignment__c assignment : corrected) {
                assignment.addError(format(Label.eLogix_Fleet_Correction_Not_Recorded, e.getMessage(), null));
            }
            return;
        } catch (QueryException e) {
            // Q16: TrackingService locks the shipment to update its tracking summary.
            if (!isLockTimeout(e)) {
                throw e;
            }
            for (Vehicle_Assignment__c assignment : corrected) {
                assignment.addError(Label.eLogix_Fleet_Busy);
            }
            return;
        }
        for (ServiceResult.ServiceError error : result.errors) {
            corrected[error.recordIndex].addError(format(Label.eLogix_Fleet_Correction_Not_Recorded, error.message, null));
        }
    }

    private static String nameOf(Map<Id, String> names, Id recordId) {
        return names.containsKey(recordId) ? names.get(recordId) : String.valueOf(recordId);
    }

    private static Boolean isAssignmentAfterSaveTrigger() {
        return Trigger.isExecuting &&
            Trigger.isAfter &&
            (Trigger.isInsert || Trigger.isUpdate) &&
            Trigger.new != null &&
            Trigger.new.getSObjectType() == Vehicle_Assignment__c.SObjectType;
    }

    /* ------------------------------------------------------------------ */
    /* Helpers                                                             */
    /* ------------------------------------------------------------------ */

    private static Set<Id> shipmentIdsOf(List<Vehicle_Assignment__c> records) {
        Set<Id> ids = new Set<Id>();
        for (Vehicle_Assignment__c assignment : records) {
            ids.add(assignment.Shipment__c);
        }
        ids.remove(null);
        return ids;
    }

    private static String format(String template, Object first, Object second) {
        return String.format(template, new List<Object>{ first, second });
    }

    /**
     * Writes Shipment__c.Vehicle__c and Driver__c without sharing. Justification: these fields are
     * protected (read-only for every role except Administrator), and a Fleet Manager may only read
     * shipments. Called only from syncShipments, which reads the trigger context itself; the values
     * written are those of assignments that passed every rule in the before trigger.
     */
    private without sharing class MirrorWriter {
        public Map<Id, Shipment__c> lockShipments(Set<Id> shipmentIds) {
            return selector.lockShipmentsForMirror(shipmentIds);
        }

        public List<Database.SaveResult> updateShipments(List<Shipment__c> shipments) {
            return Database.update(shipments, false, AccessLevel.SYSTEM_MODE);
        }
    }
}
