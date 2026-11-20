/**
 * Fleet allocation use cases (CLAUDE.md section 7; Phase 4 decisions Q1 to Q18). Results are per
 * record (ServiceResult); one record's failure never undoes another's. Every business rule is
 * enforced by VehicleAssignmentDomain in the assignment trigger, so it also holds for direct edits;
 * this service adds access checks, orchestration and clear per-record errors.
 *
 * Writes from user-initiated operations run in user mode: CRUD, FLS and sharing apply, and the
 * assignment trigger then mirrors the shipment's protected Vehicle__c / Driver__c fields.
 * See docs/FLEET_IMPLEMENTATION.md.
 */
public with sharing class FleetAllocationService {
    public static final String REQUEST_INVALID = 'REQUEST_INVALID';
    public static final String NOT_FOUND = 'NOT_FOUND';
    public static final String NO_OPEN_ASSIGNMENT = 'NO_OPEN_ASSIGNMENT';
    public static final String STATUS_NOT_ALLOWED = 'STATUS_NOT_ALLOWED';
    public static final String FLEET_BUSY = VehicleAssignmentDomain.FLEET_BUSY;
    public static final String CANCELLATION_TRIGGER_ONLY = 'FLEET_CANCELLATION_TRIGGER_ONLY';
    public static final String DELETION_TRIGGER_ONLY = 'FLEET_SHIPMENT_DELETION_TRIGGER_ONLY';
    public static final String CORRECTION_REASON_REQUIRED = 'CORRECTION_REASON_REQUIRED';
    private static final String SHIPMENT_CANCELLED = 'Cancelled';
    private static final String CONTEXT = 'FleetAllocationService';

    /** Test seam for lock timeouts (Q16): a test substitutes a selector whose lock query fails. */
    @TestVisible
    private static FleetSelector selector = new FleetSelector();

    /* ------------------------------------------------------------------ */
    /* Allocate and reallocate                                             */
    /* ------------------------------------------------------------------ */

    /** Creates one Planned assignment per request. The window is derived from the shipment (Q3). */
    public ServiceResult allocate(List<AllocationRequest> requests) {
        ServiceResult result = new ServiceResult();
        if (requests == null || requests.isEmpty()) {
            return result;
        }
        requireAccess(Schema.SObjectType.Vehicle_Assignment__c.isCreateable());

        AccessibleRecords visible;
        try {
            visible = readVisible(requests);
        } catch (QueryException e) {
            return busy(result, e, requests);
        }
        List<Vehicle_Assignment__c> inserts = new List<Vehicle_Assignment__c>();
        List<Integer> indexes = new List<Integer>();
        for (Integer i = 0; i < requests.size(); i++) {
            AllocationRequest request = requests[i];
            if (!addRequestProblem(result, request, visible, i)) {
                inserts.add(
                    new Vehicle_Assignment__c(
                        Shipment__c = request.shipmentId,
                        Vehicle__c = request.vehicleId,
                        Driver__c = request.driverId,
                        Status__c = VehicleAssignmentDomain.PLANNED,
                        Remarks__c = request.remarks
                    )
                );
                indexes.add(i);
            }
        }
        recordResults(result, Database.insert(inserts, false, AccessLevel.USER_MODE), indexes, requestShipmentIds(requests));
        Logger.info(CONTEXT, 'allocate requested=' + requests.size() + ' allocated=' + result.recordIds.size());
        return result;
    }

    /**
     * Changes the vehicle and/or driver of each shipment's Planned assignment in place (Q9), and
     * refreshes its window from the shipment's current dates (Q3), so reallocating the same vehicle and
     * driver after a date change renews the booking. The change is re-evaluated by the assignment
     * trigger like a new allocation; if it fails, the existing allocation stays as it was. Refused by
     * the trigger once the shipment has ever reached Ready for Dispatch (see correctDispatchedAllocation).
     */
    public ServiceResult reallocate(List<AllocationRequest> requests) {
        return changeAllocation(requests, false);
    }

    /**
     * Controlled recovery (audit round 3, issue 1): corrects the vehicle, driver or booking window of a
     * shipment that has already reached dispatch. Needs eLogix_Correct_Dispatched_Allocation and
     * eLogix_Allocate_Fleet, a shipment that is On Hold, and a correction reason per request that
     * differs from the previous correction's. Same path as reallocate, plus Correction_Reason__c: the
     * assignment trigger accepts the change only under those conditions, revalidates it in full against
     * current data, and writes it to tracking history (or refuses the whole correction).
     */
    public ServiceResult correctDispatchedAllocation(List<AllocationRequest> requests) {
        return changeAllocation(requests, true);
    }

    private ServiceResult changeAllocation(List<AllocationRequest> requests, Boolean correcting) {
        ServiceResult result = new ServiceResult();
        if (requests == null || requests.isEmpty()) {
            return result;
        }
        requireAccess(Schema.SObjectType.Vehicle_Assignment__c.isUpdateable());
        if (correcting && !PermissionService.hasPermission(VehicleAssignmentDomain.CORRECT_PERMISSION)) {
            throw new AuthorizationException(Label.eLogix_Access_Denied).withCode(AuthorizationException.ACCESS_DENIED);
        }

        AccessibleRecords visible;
        Map<Id, Vehicle_Assignment__c> plannedByShipment;
        try {
            visible = readVisible(requests);
            plannedByShipment = selector.plannedAssignmentByShipment(visible.shipments.keySet());
        } catch (QueryException e) {
            return busy(result, e, requests);
        }
        List<Vehicle_Assignment__c> updates = new List<Vehicle_Assignment__c>();
        List<Integer> indexes = new List<Integer>();
        for (Integer i = 0; i < requests.size(); i++) {
            AllocationRequest request = requests[i];
            if (addRequestProblem(result, request, visible, i)) {
                continue;
            }
            Vehicle_Assignment__c planned = plannedByShipment.get(request.shipmentId);
            if (planned == null) {
                result.addError(
                    NO_OPEN_ASSIGNMENT,
                    String.format(Label.eLogix_Fleet_No_Open_Assignment, new List<Object>{ visible.shipments.get(request.shipmentId).Name }),
                    i,
                    request.shipmentId
                );
                continue;
            }
            Vehicle_Assignment__c change = new Vehicle_Assignment__c(Id = planned.Id, Vehicle__c = request.vehicleId, Driver__c = request.driverId);
            if (correcting) {
                String reason = request.correctionReason?.trim();
                if (String.isBlank(reason) || VehicleAssignmentDomain.sameText(reason, planned.Correction_Reason__c)) {
                    result.addError(CORRECTION_REASON_REQUIRED, Label.eLogix_Fleet_Correction_Reason_Required, i, request.shipmentId);
                    continue;
                }
                change.Correction_Reason__c = reason;
            }
            Shipment__c shipment = visible.shipments.get(request.shipmentId);
            Date pickup = shipment.Pickup_Date__c;
            Date delivery = shipment.Expected_Delivery_Date__c;
            if (pickup != null && delivery != null && delivery >= pickup) {
                change.Assignment_Start__c = AssignmentWindow.startOf(pickup);
                change.Assignment_End__c = AssignmentWindow.endOf(delivery);
            }
            updates.add(change);
            indexes.add(i);
        }
        recordResults(result, Database.update(updates, false, AccessLevel.USER_MODE), indexes, requestShipmentIds(requests));
        return result;
    }

    /* ------------------------------------------------------------------ */
    /* Lifecycle (Q12)                                                     */
    /* ------------------------------------------------------------------ */

    /** Planned -> Cancelled while the shipment is Confirmed or On Hold. Clears the shipment mirror (Q18). */
    public ServiceResult release(List<Id> assignmentIds) {
        return changeStatus(assignmentIds, VehicleAssignmentDomain.PLANNED, VehicleAssignmentDomain.CANCELLED);
    }

    /** Planned -> Active, for the Phase 5 dispatch wiring (shipment Ready for Dispatch or Dispatched). */
    public ServiceResult activate(List<Id> assignmentIds) {
        return changeStatus(assignmentIds, VehicleAssignmentDomain.PLANNED, VehicleAssignmentDomain.ACTIVE);
    }

    /** Active -> Completed, recording the actual end; the shipment keeps its vehicle and driver as history. */
    public ServiceResult complete(List<Id> assignmentIds) {
        return changeStatus(assignmentIds, VehicleAssignmentDomain.ACTIVE, VehicleAssignmentDomain.COMPLETED);
    }

    private ServiceResult changeStatus(List<Id> assignmentIds, String fromStatus, String toStatus) {
        ServiceResult result = new ServiceResult();
        if (assignmentIds == null || assignmentIds.isEmpty()) {
            return result;
        }
        requireAccess(Schema.SObjectType.Vehicle_Assignment__c.isUpdateable());
        Set<Id> ids = new Set<Id>(assignmentIds);
        ids.remove(null);
        Map<Id, Vehicle_Assignment__c> assignments;
        try {
            assignments = selector.assignmentsForUpdate(ids);
        } catch (QueryException e) {
            if (!VehicleAssignmentDomain.isLockTimeout(e)) {
                throw e;
            }
            for (Integer i = 0; i < assignmentIds.size(); i++) {
                result.addError(FLEET_BUSY, Label.eLogix_Fleet_Busy, i, assignmentIds[i]);
            }
            return result;
        }

        List<Vehicle_Assignment__c> updates = new List<Vehicle_Assignment__c>();
        List<Integer> indexes = new List<Integer>();
        Datetime now = System.now();
        for (Integer i = 0; i < assignmentIds.size(); i++) {
            Vehicle_Assignment__c assignment = assignments.get(assignmentIds[i]);
            if (assignment == null) {
                result.addError(NOT_FOUND, String.format(Label.eLogix_Fleet_Record_Not_Found, new List<Object>{ assignmentIds[i] }), i, assignmentIds[i]);
                continue;
            }
            if (assignment.Status__c != fromStatus) {
                result.addError(
                    STATUS_NOT_ALLOWED,
                    String.format(Label.eLogix_Fleet_Transition_Not_Allowed, new List<Object>{ assignment.Status__c, toStatus }),
                    i,
                    assignment.Id
                );
                continue;
            }
            Vehicle_Assignment__c change = new Vehicle_Assignment__c(Id = assignment.Id, Status__c = toStatus);
            if (VehicleAssignmentDomain.COMPLETED.equals(toStatus) && now > assignment.Assignment_Start__c) {
                change.Assignment_End__c = now;
            }
            updates.add(change);
            indexes.add(i);
        }
        recordResults(result, Database.update(updates, false, AccessLevel.USER_MODE), indexes, assignmentIds);
        return result;
    }

    /* ------------------------------------------------------------------ */
    /* Shipment cancellation (Q11): called only from ShipmentTriggerHandler */
    /* ------------------------------------------------------------------ */

    /**
     * Before update of shipments moving to Cancelled: clears Vehicle__c / Driver__c on the trigger
     * records when they reference the shipment's Planned assignment (Q18 matching rule). Done here, in
     * memory, so the assignment trigger that runs on the release has nothing to write back to a
     * shipment that is still inside its own trigger. Reads Trigger.new and Trigger.oldMap itself and
     * refuses to run anywhere else. No SOQL when no shipment is being cancelled.
     */
    public void clearCancelledShipmentAllocations() {
        if (!isShipmentUpdateTrigger(true)) {
            throw new AuthorizationException(Label.eLogix_Access_Denied).withCode(CANCELLATION_TRIGGER_ONLY);
        }
        Map<Id, Shipment__c> cancelling = shipmentsBeingCancelled();
        if (cancelling.isEmpty()) {
            return;
        }
        for (Vehicle_Assignment__c assignment : selector.openAssignmentsOfShipments(cancelling.keySet())) {
            Shipment__c shipment = cancelling.get(assignment.Shipment__c);
            if (!VehicleAssignmentDomain.PLANNED.equals(assignment.Status__c)) {
                continue; // an Active assignment is not released automatically
            }
            if (shipment.Vehicle__c == assignment.Vehicle__c) {
                shipment.Vehicle__c = null;
            }
            if (shipment.Driver__c == assignment.Driver__c) {
                shipment.Driver__c = null;
            }
        }
    }

    /**
     * After update of shipments moving to Cancelled: cancels their Planned assignments, which frees
     * the vehicle and driver. Stateless: a re-fired trigger finds no Planned assignment left, so a
     * release never happens twice, and Completed or Active assignments are never touched. A release
     * that fails fails only its own shipment's cancellation. Refuses to run outside that trigger.
     */
    public void releaseCancelledShipmentAssignments() {
        if (!isShipmentUpdateTrigger(false)) {
            throw new AuthorizationException(Label.eLogix_Access_Denied).withCode(CANCELLATION_TRIGGER_ONLY);
        }
        Map<Id, Shipment__c> cancelled = shipmentsBeingCancelled();
        if (cancelled.isEmpty()) {
            return;
        }
        List<Vehicle_Assignment__c> planned;
        try {
            planned = selector.lockPlannedAssignmentsOfShipments(cancelled.keySet());
        } catch (QueryException e) {
            if (!VehicleAssignmentDomain.isLockTimeout(e)) {
                throw e;
            }
            // Q16: the cancellation is refused with the retryable message; nothing is half-released.
            for (Shipment__c shipment : cancelled.values()) {
                shipment.addError(String.format(Label.eLogix_Fleet_Release_Failed, new List<Object>{ Label.eLogix_Fleet_Busy }));
            }
            return;
        }
        List<Vehicle_Assignment__c> releases = new List<Vehicle_Assignment__c>();
        for (Vehicle_Assignment__c assignment : planned) {
            releases.add(new Vehicle_Assignment__c(Id = assignment.Id, Shipment__c = assignment.Shipment__c, Status__c = VehicleAssignmentDomain.CANCELLED));
        }
        if (releases.isEmpty()) {
            return;
        }
        // System mode: the user cancelling a shipment may only read assignments. The assignment trigger
        // allows this one change only because the stored shipment is Cancelled (no bypass flag).
        List<Vehicle_Assignment__c> payload = new List<Vehicle_Assignment__c>();
        for (Vehicle_Assignment__c release : releases) {
            payload.add(new Vehicle_Assignment__c(Id = release.Id, Status__c = release.Status__c));
        }
        List<Database.SaveResult> results = Database.update(payload, false, AccessLevel.SYSTEM_MODE);
        for (Integer i = 0; i < results.size(); i++) {
            if (!results[i].isSuccess()) {
                Database.Error error = results[i].getErrors()[0];
                String reason = VehicleAssignmentDomain.isLockTimeout(error) ? Label.eLogix_Fleet_Busy : error.getMessage();
                cancelled.get(releases[i].Shipment__c).addError(String.format(Label.eLogix_Fleet_Release_Failed, new List<Object>{ reason }));
            }
        }
    }

    /**
     * Shipment before delete (audit round 3, issue 3): a shipment that still has a Planned or Active
     * assignment cannot be deleted, so no booking is ever orphaned. The assignment must first be
     * cancelled through its lifecycle (or the shipment cancelled, which releases it). Completed and
     * Cancelled assignments keep the existing retention behaviour (the lookup is cleared). Reads
     * Trigger.old itself and refuses to run anywhere else.
     */
    public void rejectDeletionWithOpenAssignments() {
        if (!(Trigger.isExecuting && Trigger.operationType == System.TriggerOperation.BEFORE_DELETE && Trigger.old != null &&
            Trigger.old.getSObjectType() == Shipment__c.SObjectType)) {
            throw new AuthorizationException(Label.eLogix_Access_Denied).withCode(DELETION_TRIGGER_ONLY);
        }
        Map<Id, Shipment__c> deleting = new Map<Id, Shipment__c>((List<Shipment__c>) Trigger.old);
        Set<Id> blocked = new Set<Id>();
        for (Vehicle_Assignment__c assignment : selector.openAssignmentsOfShipments(deleting.keySet())) {
            blocked.add(assignment.Shipment__c);
        }
        for (Id shipmentId : blocked) {
            Shipment__c shipment = deleting.get(shipmentId);
            shipment.addError(String.format(Label.eLogix_Fleet_Shipment_Delete_Blocked, new List<Object>{ shipment.Name }));
        }
    }

    /** Trigger records whose status changes to Cancelled in this save. */
    private static Map<Id, Shipment__c> shipmentsBeingCancelled() {
        Map<Id, Shipment__c> cancelling = new Map<Id, Shipment__c>();
        Map<Id, Shipment__c> oldById = (Map<Id, Shipment__c>) Trigger.oldMap;
        for (Shipment__c shipment : (List<Shipment__c>) Trigger.new) {
            if (SHIPMENT_CANCELLED.equals(shipment.Status__c) && !SHIPMENT_CANCELLED.equals(oldById.get(shipment.Id).Status__c)) {
                cancelling.put(shipment.Id, shipment);
            }
        }
        return cancelling;
    }

    private static Boolean isShipmentUpdateTrigger(Boolean before) {
        return Trigger.isExecuting &&
            Trigger.isUpdate &&
            (before ? Trigger.isBefore : Trigger.isAfter) &&
            Trigger.new != null &&
            Trigger.new.getSObjectType() == Shipment__c.SObjectType;
    }

    /* ------------------------------------------------------------------ */
    /* Helpers                                                             */
    /* ------------------------------------------------------------------ */

    /** Shipments (locked), vehicles and drivers the running user can read. Shipments are locked first. */
    private AccessibleRecords readVisible(List<AllocationRequest> requests) {
        Set<Id> shipmentIds = new Set<Id>();
        Set<Id> vehicleIds = new Set<Id>();
        Set<Id> driverIds = new Set<Id>();
        for (AllocationRequest request : requests) {
            if (request == null) {
                continue;
            }
            addIfType(shipmentIds, request.shipmentId, Shipment__c.SObjectType);
            addIfType(vehicleIds, request.vehicleId, Vehicle__c.SObjectType);
            addIfType(driverIds, request.driverId, Driver__c.SObjectType);
        }
        AccessibleRecords visible = new AccessibleRecords();
        visible.shipments = selector.shipmentsForAllocation(shipmentIds);
        visible.vehicleIds = selector.readableVehicleIds(vehicleIds);
        visible.driverIds = selector.readableDriverIds(driverIds);
        return visible;
    }

    /** Adds the request's first problem and returns true; returns false when the request can be saved. */
    private static Boolean addRequestProblem(ServiceResult result, AllocationRequest request, AccessibleRecords visible, Integer index) {
        if (
            request == null ||
            !isType(request.shipmentId, Shipment__c.SObjectType) ||
            !isType(request.vehicleId, Vehicle__c.SObjectType) ||
            !isType(request.driverId, Driver__c.SObjectType)
        ) {
            result.addError(REQUEST_INVALID, String.format(Label.eLogix_Request_Invalid, new List<Object>{ index + 1 }), index, request?.shipmentId);
            return true;
        }
        Id missing = !visible.shipments.containsKey(request.shipmentId)
            ? request.shipmentId
            : !visible.vehicleIds.contains(request.vehicleId) ? request.vehicleId : !visible.driverIds.contains(request.driverId) ? request.driverId : null;
        if (missing != null) {
            result.addError(NOT_FOUND, String.format(Label.eLogix_Fleet_Record_Not_Found, new List<Object>{ missing }), index, request.shipmentId);
            return true;
        }
        return false;
    }

    private static void recordResults(ServiceResult result, List<Database.SaveResult> saveResults, List<Integer> indexes, List<Id> inputIds) {
        for (Integer j = 0; j < saveResults.size(); j++) {
            Integer index = indexes[j];
            if (saveResults[j].isSuccess()) {
                result.addRecordId(saveResults[j].getId());
                continue;
            }
            for (Database.Error error : saveResults[j].getErrors()) {
                String code = codeFor(String.valueOf(error.getStatusCode()), error.getMessage());
                // Q16: a lock timeout is reported with the retryable message, never the raw database text.
                result.addError(code, FLEET_BUSY.equals(code) ? Label.eLogix_Fleet_Busy : error.getMessage(), index, inputIds[index]);
            }
        }
    }

    /** Q16: lock timeouts, raised by the platform or reported by the fleet rules, become FLEET_BUSY. */
    @TestVisible
    private static String codeFor(String statusCode, String message) {
        if (statusCode == 'UNABLE_TO_LOCK_ROW' || message == Label.eLogix_Fleet_Busy || VehicleAssignmentDomain.isLockTimeoutMessage(message)) {
            return FLEET_BUSY;
        }
        return statusCode;
    }

    /**
     * Q16: a lock timeout while reading the caller's shipments or assignments fails every request in
     * the call with the retryable FLEET_BUSY (malformed requests still get REQUEST_INVALID). Nothing
     * has been written. Any other query failure is not a lock problem and is rethrown.
     */
    private static ServiceResult busy(ServiceResult result, QueryException e, List<AllocationRequest> requests) {
        if (!VehicleAssignmentDomain.isLockTimeout(e)) {
            throw e;
        }
        Logger.warn(CONTEXT, 'Fleet lock timeout while reading ' + requests.size() + ' requests.');
        for (Integer i = 0; i < requests.size(); i++) {
            AllocationRequest request = requests[i];
            if (
                request == null ||
                !isType(request.shipmentId, Shipment__c.SObjectType) ||
                !isType(request.vehicleId, Vehicle__c.SObjectType) ||
                !isType(request.driverId, Driver__c.SObjectType)
            ) {
                result.addError(REQUEST_INVALID, String.format(Label.eLogix_Request_Invalid, new List<Object>{ i + 1 }), i, request?.shipmentId);
            } else {
                result.addError(FLEET_BUSY, Label.eLogix_Fleet_Busy, i, request.shipmentId);
            }
        }
        return result;
    }

    private static List<Id> requestShipmentIds(List<AllocationRequest> requests) {
        List<Id> ids = new List<Id>();
        for (AllocationRequest request : requests) {
            ids.add(request?.shipmentId);
        }
        return ids;
    }

    private static void addIfType(Set<Id> ids, Id value, Schema.SObjectType type) {
        if (isType(value, type)) {
            ids.add(value);
        }
    }

    private static Boolean isType(Id value, Schema.SObjectType type) {
        return value != null && value.getSObjectType() == type;
    }

    private static void requireAccess(Boolean objectAccess) {
        if (!objectAccess || !PermissionService.hasPermission(VehicleAssignmentDomain.ALLOCATE_PERMISSION)) {
            throw new AuthorizationException(Label.eLogix_Access_Denied).withCode(AuthorizationException.ACCESS_DENIED);
        }
    }

    private class AccessibleRecords {
        public Map<Id, Shipment__c> shipments = new Map<Id, Shipment__c>();
        public Set<Id> vehicleIds = new Set<Id>();
        public Set<Id> driverIds = new Set<Id>();
    }
}
