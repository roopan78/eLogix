/**
 * Delivery use cases (Phase 5). Shipments are the handle: each has at most one open attempt.
 *
 *   startAttempts      new attempt (numbered by the Delivery trigger) and shipment -> Out for Delivery
 *   recordProofs       the proof of delivery for the open attempt; evidence files are then uploaded
 *                      to the proof record
 *   confirmDeliveries  attempt -> Delivered (receiver and time from the proof) and shipment ->
 *                      Delivered with its actual delivery date; the trip's assignment is completed by
 *                      the shipment trigger
 *   recordFailures     attempt -> Failed with the reason and shipment -> Failed Delivery; the trip
 *                      stays Active, and a retry is a new attempt on the same assignment
 *   verifyProofs       the verifier stamp on delivered proofs (Logistics Manager by field access)
 *
 * Every rule is enforced by the triggers (DeliveryDomain, ProofOfDeliveryDomain, the shipment status
 * policy and its guards), so it also holds for direct edits; this service orders the steps, checks
 * access and reports per record. Writes run in user mode. Shipments are locked first, before their
 * attempts, which also serialises duplicate confirmations: a second one finds ALREADY_DELIVERED.
 *
 * Consistency and partial success (requirements 3 and 4): each two-step operation runs the attempt
 * step for the whole batch, then the shipment step for the records whose first step succeeded, under
 * one savepoint per round. A record that fails its first step changed nothing. If any record fails its
 * second step, the round is rolled back and retried without the failed records, so a failure never
 * leaves a partly updated attempt, proof or shipment. At most MAX_ROUNDS rounds, each with a fixed
 * number of DML statements: no savepoint, SOQL or DML per record.
 */
public with sharing class DeliveryService {
    public static final String REQUEST_INVALID = 'REQUEST_INVALID';
    public static final String NOT_FOUND = 'NOT_FOUND';
    public static final String DUPLICATE_REQUEST = 'DUPLICATE_REQUEST';
    public static final String NO_OPEN_ATTEMPT = 'NO_OPEN_ATTEMPT';
    public static final String ALREADY_DELIVERED = 'ALREADY_DELIVERED';
    public static final String DELIVERY_BUSY = 'DELIVERY_BUSY';
    public static final String NOT_COMPLETED = 'NOT_COMPLETED';
    public static final String CANCELLATION_TRIGGER_ONLY = 'DELIVERY_CANCELLATION_TRIGGER_ONLY';
    public static final String DELETION_TRIGGER_ONLY = 'DELIVERY_DELETION_TRIGGER_ONLY';
    public static final String CLOSED_ON_CANCELLATION_REASON = 'Other';
    @TestVisible
    private static final Integer MAX_ROUNDS = 3;
    private static final String CONTEXT = 'DeliveryService';
    private static final String SHIPMENT_OUT_FOR_DELIVERY = 'Out for Delivery';
    private static final String SHIPMENT_DELIVERED = 'Delivered';
    private static final String SHIPMENT_FAILED_DELIVERY = 'Failed Delivery';
    private static final String SHIPMENT_CANCELLED = 'Cancelled';

    /** Test seam for lock timeouts. */
    @TestVisible
    private static DeliverySelector selector = new DeliverySelector();

    /* ------------------------------------------------------------------ */
    /* Attempts                                                            */
    /* ------------------------------------------------------------------ */

    /** Starts a delivery attempt for each shipment (In Transit, Delayed or Failed Delivery). Returns the attempt Ids. */
    public ServiceResult startAttempts(List<Id> shipmentIds) {
        ServiceResult result = new ServiceResult();
        if (shipmentIds == null || shipmentIds.isEmpty()) {
            return result;
        }
        requireAccess(Schema.SObjectType.Delivery__c.isCreateable() && Schema.SObjectType.Shipment__c.isUpdateable());
        Locked locked = lockShipments(shipmentIds, result);
        if (locked == null) {
            return result;
        }
        StartAttempts save = new StartAttempts(shipmentIds);
        save.run(locked.indexes);
        report(result, save, shipmentIds, true);
        Logger.info(CONTEXT, 'startAttempts requested=' + shipmentIds.size() + ' started=' + save.succeeded.size());
        return result;
    }

    /** Records the proof of delivery for each shipment's open attempt. Returns the proof Ids, for the evidence upload. */
    public ServiceResult recordProofs(List<ProofOfDeliveryRequest> requests) {
        ServiceResult result = new ServiceResult();
        if (requests == null || requests.isEmpty()) {
            return result;
        }
        requireAccess(Schema.SObjectType.Proof_of_Delivery__c.isCreateable());
        Set<Id> shipmentIds = new Set<Id>();
        for (ProofOfDeliveryRequest request : requests) {
            if (request != null && isShipment(request.shipmentId)) {
                shipmentIds.add(request.shipmentId);
            }
        }
        Map<Id, Delivery__c> open = selector.openAttemptByShipment(shipmentIds);
        List<Proof_of_Delivery__c> proofs = new List<Proof_of_Delivery__c>();
        List<Integer> indexes = new List<Integer>();
        Set<Id> seen = new Set<Id>();
        for (Integer i = 0; i < requests.size(); i++) {
            ProofOfDeliveryRequest request = requests[i];
            if (request == null || !isShipment(request.shipmentId)) {
                result.addError(REQUEST_INVALID, String.format(Label.eLogix_Request_Invalid, new List<Object>{ i + 1 }), i, request?.shipmentId);
            } else if (!seen.add(request.shipmentId)) {
                result.addError(DUPLICATE_REQUEST, String.format(Label.eLogix_Delivery_Duplicate_Request, new List<Object>{ request.shipmentId }), i, request.shipmentId);
            } else if (!open.containsKey(request.shipmentId)) {
                result.addError(NO_OPEN_ATTEMPT, String.format(Label.eLogix_Delivery_No_Open_Attempt, new List<Object>{ request.shipmentId }), i, request.shipmentId);
            } else {
                proofs.add(
                    new Proof_of_Delivery__c(
                        Delivery__c = open.get(request.shipmentId).Id,
                        Receiver_Name__c = request.receiverName,
                        Received_Date__c = request.receivedAt,
                        Signature_Reference__c = request.signatureReference,
                        Delivery_Notes__c = request.deliveryNotes,
                        Has_Exception__c = request.hasException == true,
                        Exception_Notes__c = request.exceptionNotes
                    )
                );
                indexes.add(i);
            }
        }
        List<Database.SaveResult> results = Database.insert(proofs, false, AccessLevel.USER_MODE);
        for (Integer j = 0; j < results.size(); j++) {
            Integer i = indexes[j];
            if (results[j].isSuccess()) {
                result.addRecordId(results[j].getId());
            } else {
                Database.Error error = results[j].getErrors()[0];
                result.addError(String.valueOf(error.getStatusCode()), error.getMessage(), i, requests[i].shipmentId);
            }
        }
        return result;
    }

    /** Confirms each shipment's open attempt as Delivered and the shipment as Delivered. Returns the shipment Ids. */
    public ServiceResult confirmDeliveries(List<Id> shipmentIds) {
        ServiceResult result = new ServiceResult();
        if (shipmentIds == null || shipmentIds.isEmpty()) {
            return result;
        }
        requireAccess(Schema.SObjectType.Delivery__c.isUpdateable() && Schema.SObjectType.Shipment__c.isUpdateable());
        Locked locked = lockShipments(shipmentIds, result);
        if (locked == null) {
            return result;
        }
        Map<Id, Delivery__c> open = selector.openAttemptByShipment(locked.shipments.keySet());
        Set<Id> attemptIds = new Set<Id>();
        for (Delivery__c attempt : open.values()) {
            attemptIds.add(attempt.Id);
        }
        Map<Id, Proof_of_Delivery__c> proofs = selector.proofByAttempt(attemptIds);
        List<Integer> candidates = new List<Integer>();
        for (Integer i : locked.indexes) {
            Shipment__c shipment = locked.shipments.get(shipmentIds[i]);
            if (SHIPMENT_DELIVERED.equals(shipment.Status__c)) {
                // Idempotent: a repeated confirmation changes nothing and records no event.
                result.addError(ALREADY_DELIVERED, String.format(Label.eLogix_Delivery_Already_Delivered, new List<Object>{ shipment.Name }), i, shipment.Id);
            } else if (!open.containsKey(shipment.Id)) {
                result.addError(NO_OPEN_ATTEMPT, String.format(Label.eLogix_Delivery_No_Open_Attempt, new List<Object>{ shipment.Name }), i, shipment.Id);
            } else {
                candidates.add(i);
            }
        }
        ConfirmDeliveries save = new ConfirmDeliveries(shipmentIds, open, proofs);
        save.run(candidates);
        report(result, save, shipmentIds, false);
        Logger.info(CONTEXT, 'confirmDeliveries requested=' + shipmentIds.size() + ' delivered=' + save.succeeded.size());
        return result;
    }

    /** Records each shipment's open attempt as Failed and the shipment as Failed Delivery. Returns the shipment Ids. */
    public ServiceResult recordFailures(List<DeliveryFailureRequest> requests) {
        ServiceResult result = new ServiceResult();
        if (requests == null || requests.isEmpty()) {
            return result;
        }
        requireAccess(Schema.SObjectType.Delivery__c.isUpdateable() && Schema.SObjectType.Shipment__c.isUpdateable());
        List<Id> shipmentIds = new List<Id>();
        for (DeliveryFailureRequest request : requests) {
            shipmentIds.add(request?.shipmentId);
        }
        Locked locked = lockShipments(shipmentIds, result);
        if (locked == null) {
            return result;
        }
        Map<Id, Delivery__c> open = selector.openAttemptByShipment(locked.shipments.keySet());
        List<Integer> candidates = new List<Integer>();
        for (Integer i : locked.indexes) {
            Shipment__c shipment = locked.shipments.get(shipmentIds[i]);
            if (!open.containsKey(shipment.Id)) {
                result.addError(NO_OPEN_ATTEMPT, String.format(Label.eLogix_Delivery_No_Open_Attempt, new List<Object>{ shipment.Name }), i, shipment.Id);
            } else {
                candidates.add(i);
            }
        }
        RecordFailures save = new RecordFailures(shipmentIds, requests, open);
        save.run(candidates);
        report(result, save, shipmentIds, false);
        return result;
    }

    /** Stamps the running user as verifier of delivered proofs. Field access limits this to the Logistics Manager. */
    public ServiceResult verifyProofs(List<Id> proofIds) {
        ServiceResult result = new ServiceResult();
        if (proofIds == null || proofIds.isEmpty()) {
            return result;
        }
        requireAccess(
            Schema.SObjectType.Proof_of_Delivery__c.isUpdateable() && Schema.SObjectType.Proof_of_Delivery__c.fields.Verified_By__c.isUpdateable()
        );
        List<Proof_of_Delivery__c> updates = new List<Proof_of_Delivery__c>();
        List<Integer> indexes = new List<Integer>();
        for (Integer i = 0; i < proofIds.size(); i++) {
            Id proofId = proofIds[i];
            if (proofId == null || proofId.getSObjectType() != Proof_of_Delivery__c.SObjectType) {
                result.addError(REQUEST_INVALID, String.format(Label.eLogix_Request_Invalid, new List<Object>{ i + 1 }), i, proofId);
            } else {
                updates.add(new Proof_of_Delivery__c(Id = proofId, Verified_By__c = UserInfo.getUserId()));
                indexes.add(i);
            }
        }
        List<Database.SaveResult> results = Database.update(updates, false, AccessLevel.USER_MODE);
        for (Integer j = 0; j < results.size(); j++) {
            if (results[j].isSuccess()) {
                result.addRecordId(results[j].getId());
            } else {
                Database.Error error = results[j].getErrors()[0];
                result.addError(String.valueOf(error.getStatusCode()), error.getMessage(), indexes[j], proofIds[indexes[j]]);
            }
        }
        return result;
    }

    /* ------------------------------------------------------------------ */
    /* Shipment trigger hooks                                              */
    /* ------------------------------------------------------------------ */

    /**
     * D2: a shipment cancelled after dispatch closes its open delivery attempt as Failed, reason Other,
     * with a note. Shipment after update only (reads Trigger.new and Trigger.oldMap itself). System
     * mode: the cancelling user holds eLogix_Cancel_Confirmed_Shipment, and the Delivery trigger accepts
     * a Failed attempt here only because the stored shipment is Cancelled. Stateless, so a re-fired
     * trigger finds no open attempt left; a failure refuses the cancellation. The cancellation itself
     * is in the shipment's status history, with its reason.
     */
    public void closeAttemptsOfCancelledShipments() {
        if (!isShipmentTrigger(System.TriggerOperation.AFTER_UPDATE)) {
            throw new AuthorizationException(Label.eLogix_Access_Denied).withCode(CANCELLATION_TRIGGER_ONLY);
        }
        Map<Id, Shipment__c> oldById = (Map<Id, Shipment__c>) Trigger.oldMap;
        Map<Id, Shipment__c> cancelled = new Map<Id, Shipment__c>();
        for (Shipment__c shipment : (List<Shipment__c>) Trigger.new) {
            if (SHIPMENT_CANCELLED.equals(shipment.Status__c) && !SHIPMENT_CANCELLED.equals(oldById.get(shipment.Id).Status__c)) {
                cancelled.put(shipment.Id, shipment);
            }
        }
        if (cancelled.isEmpty()) {
            return;
        }
        List<Delivery__c> open;
        try {
            open = selector.lockOpenAttemptsOfShipments(cancelled.keySet());
        } catch (QueryException e) {
            if (!VehicleAssignmentDomain.isLockTimeout(e)) {
                throw e;
            }
            for (Shipment__c shipment : cancelled.values()) {
                shipment.addError(Label.eLogix_Delivery_Busy);
            }
            return;
        }
        if (open.isEmpty()) {
            return;
        }
        List<Delivery__c> closures = new List<Delivery__c>();
        for (Delivery__c attempt : open) {
            closures.add(
                new Delivery__c(
                    Id = attempt.Id,
                    Delivery_Status__c = DeliveryDomain.FAILED,
                    Failure_Reason__c = CLOSED_ON_CANCELLATION_REASON,
                    Failure_Notes__c = Label.eLogix_Delivery_Cancelled_Notes
                )
            );
        }
        List<Database.SaveResult> results = Database.update(closures, false, AccessLevel.SYSTEM_MODE);
        for (Integer i = 0; i < results.size(); i++) {
            if (!results[i].isSuccess()) {
                Database.Error error = results[i].getErrors()[0];
                cancelled.get(open[i].Shipment__c).addError(VehicleAssignmentDomain.isLockTimeout(error) ? Label.eLogix_Delivery_Busy : error.getMessage());
            }
        }
    }

    /** D5: a shipment with proof of delivery records cannot be deleted. Shipment before delete only. */
    public void rejectDeletionWithProofOfDelivery() {
        if (!(Trigger.isExecuting && Trigger.operationType == System.TriggerOperation.BEFORE_DELETE && Trigger.old != null &&
            Trigger.old.getSObjectType() == Shipment__c.SObjectType)) {
            throw new AuthorizationException(Label.eLogix_Access_Denied).withCode(DELETION_TRIGGER_ONLY);
        }
        Map<Id, Shipment__c> deleting = new Map<Id, Shipment__c>((List<Shipment__c>) Trigger.old);
        for (Id shipmentId : selector.shipmentIdsWithProofs(deleting.keySet())) {
            Shipment__c shipment = deleting.get(shipmentId);
            shipment.addError(String.format(Label.eLogix_Delivery_Shipment_Delete_Blocked, new List<Object>{ shipment.Name }));
        }
    }

    /* ------------------------------------------------------------------ */
    /* Helpers                                                             */
    /* ------------------------------------------------------------------ */

    private static Boolean isShipmentTrigger(System.TriggerOperation operation) {
        return Trigger.isExecuting && Trigger.operationType == operation && Trigger.new != null && Trigger.new.getSObjectType() == Shipment__c.SObjectType;
    }

    private static Boolean isShipment(Id recordId) {
        return recordId != null && recordId.getSObjectType() == Shipment__c.SObjectType;
    }

    private static void requireAccess(Boolean objectAccess) {
        if (!objectAccess) {
            throw new AuthorizationException(Label.eLogix_Access_Denied).withCode(AuthorizationException.ACCESS_DENIED);
        }
    }

    /**
     * Validates the Ids, locks the shipments the caller can read (shipment first, then its attempts),
     * and reports invalid, duplicate and unknown entries. Returns null after reporting a lock timeout.
     */
    private static Locked lockShipments(List<Id> shipmentIds, ServiceResult result) {
        Set<Id> ids = new Set<Id>();
        for (Id shipmentId : shipmentIds) {
            if (isShipment(shipmentId)) {
                ids.add(shipmentId);
            }
        }
        Locked locked = new Locked();
        try {
            locked.shipments = selector.shipmentsForDelivery(ids);
        } catch (QueryException e) {
            if (!VehicleAssignmentDomain.isLockTimeout(e)) {
                throw e;
            }
            for (Integer i = 0; i < shipmentIds.size(); i++) {
                result.addError(DELIVERY_BUSY, Label.eLogix_Delivery_Busy, i, shipmentIds[i]);
            }
            return null;
        }
        Set<Id> seen = new Set<Id>();
        for (Integer i = 0; i < shipmentIds.size(); i++) {
            Id shipmentId = shipmentIds[i];
            if (!isShipment(shipmentId)) {
                result.addError(REQUEST_INVALID, String.format(Label.eLogix_Request_Invalid, new List<Object>{ i + 1 }), i, shipmentId);
            } else if (!seen.add(shipmentId)) {
                result.addError(DUPLICATE_REQUEST, String.format(Label.eLogix_Delivery_Duplicate_Request, new List<Object>{ shipmentId }), i, shipmentId);
            } else if (!locked.shipments.containsKey(shipmentId)) {
                result.addError(NOT_FOUND, String.format(Label.eLogix_Fleet_Record_Not_Found, new List<Object>{ shipmentId }), i, shipmentId);
            } else {
                locked.indexes.add(i);
            }
        }
        return locked;
    }

    private static void report(ServiceResult result, TwoStepSave save, List<Id> shipmentIds, Boolean returnFirstIds) {
        for (Integer index : save.failures.keySet()) {
            List<String> failure = save.failures.get(index);
            result.addError(failure[0], failure[1], index, shipmentIds[index]);
        }
        for (Integer index : save.succeeded) {
            result.addRecordId(returnFirstIds ? save.firstIds.get(index) : shipmentIds[index]);
        }
    }

    private class Locked {
        public Map<Id, Shipment__c> shipments = new Map<Id, Shipment__c>();
        public List<Integer> indexes = new List<Integer>();
    }

    /* ------------------------------------------------------------------ */
    /* Two-step save with batch-level rollback                             */
    /* ------------------------------------------------------------------ */

    private abstract class TwoStepSave {
        /** Failed request index -> [code, message]. */
        public Map<Integer, List<String>> failures = new Map<Integer, List<String>>();
        /** Request index -> Id saved by the first step, for the successful round. */
        public Map<Integer, Id> firstIds = new Map<Integer, Id>();
        public List<Integer> succeeded = new List<Integer>();

        /** The attempt step for the given request indexes; results in the same order. */
        public abstract List<Database.SaveResult> firstStep(List<Integer> live);
        /** The shipment step for the given request indexes; results in the same order. */
        public abstract List<Database.SaveResult> secondStep(List<Integer> live);

        public void run(List<Integer> candidates) {
            List<Integer> live = candidates;
            for (Integer round = 0; round < MAX_ROUNDS && !live.isEmpty(); round++) {
                Savepoint savepoint = Database.setSavepoint();
                firstIds.clear();
                List<Database.SaveResult> first = firstStep(live);
                List<Integer> afterFirst = new List<Integer>();
                for (Integer j = 0; j < first.size(); j++) {
                    if (first[j].isSuccess()) {
                        afterFirst.add(live[j]);
                        firstIds.put(live[j], first[j].getId());
                    } else {
                        fail(live[j], first[j].getErrors()[0]); // nothing was saved for it
                    }
                }
                if (afterFirst.isEmpty()) {
                    return;
                }
                List<Database.SaveResult> second = secondStep(afterFirst);
                List<Integer> done = new List<Integer>();
                Boolean secondFailed = false;
                for (Integer j = 0; j < second.size(); j++) {
                    if (second[j].isSuccess()) {
                        done.add(afterFirst[j]);
                    } else {
                        fail(afterFirst[j], second[j].getErrors()[0]);
                        secondFailed = true;
                    }
                }
                if (!secondFailed) {
                    succeeded = done;
                    return;
                }
                // Undo the first step of the records whose second step failed by undoing the round, and
                // retry the others: one savepoint per round, never one per record.
                Database.rollback(savepoint);
                live = done;
            }
            // Still rolled back after the last round: nothing was saved for these records.
            for (Integer index : live) {
                failures.put(index, new List<String>{ NOT_COMPLETED, Label.eLogix_Delivery_Not_Completed });
            }
        }

        private void fail(Integer index, Database.Error error) {
            if (failures.containsKey(index)) {
                return;
            }
            Boolean busy = VehicleAssignmentDomain.isLockTimeout(error) || error.getMessage() == Label.eLogix_Delivery_Busy;
            failures.put(
                index,
                busy
                    ? new List<String>{ DELIVERY_BUSY, Label.eLogix_Delivery_Busy }
                    : new List<String>{ String.valueOf(error.getStatusCode()), error.getMessage() }
            );
        }
    }

    private class StartAttempts extends TwoStepSave {
        private final List<Id> shipmentIds;

        public StartAttempts(List<Id> shipmentIds) {
            this.shipmentIds = shipmentIds;
        }

        public override List<Database.SaveResult> firstStep(List<Integer> live) {
            List<Delivery__c> attempts = new List<Delivery__c>();
            for (Integer i : live) {
                attempts.add(new Delivery__c(Shipment__c = shipmentIds[i], Delivery_Status__c = DeliveryDomain.OUT_FOR_DELIVERY));
            }
            return Database.insert(attempts, false, AccessLevel.USER_MODE);
        }

        public override List<Database.SaveResult> secondStep(List<Integer> live) {
            List<Shipment__c> moves = new List<Shipment__c>();
            for (Integer i : live) {
                moves.add(new Shipment__c(Id = shipmentIds[i], Status__c = SHIPMENT_OUT_FOR_DELIVERY));
            }
            return Database.update(moves, false, AccessLevel.USER_MODE);
        }
    }

    private class ConfirmDeliveries extends TwoStepSave {
        private final List<Id> shipmentIds;
        private final Map<Id, Delivery__c> open;
        private final Map<Id, Proof_of_Delivery__c> proofs;

        public ConfirmDeliveries(List<Id> shipmentIds, Map<Id, Delivery__c> open, Map<Id, Proof_of_Delivery__c> proofs) {
            this.shipmentIds = shipmentIds;
            this.open = open;
            this.proofs = proofs;
        }

        public override List<Database.SaveResult> firstStep(List<Integer> live) {
            List<Delivery__c> attempts = new List<Delivery__c>();
            for (Integer i : live) {
                Delivery__c attempt = open.get(shipmentIds[i]);
                Proof_of_Delivery__c proof = proofs.get(attempt.Id);
                attempts.add(
                    new Delivery__c(
                        Id = attempt.Id,
                        Delivery_Status__c = DeliveryDomain.DELIVERED,
                        Receiver_Name__c = proof?.Receiver_Name__c,
                        Delivery_Date__c = proof?.Received_Date__c
                    )
                );
            }
            return Database.update(attempts, false, AccessLevel.USER_MODE);
        }

        public override List<Database.SaveResult> secondStep(List<Integer> live) {
            List<Shipment__c> moves = new List<Shipment__c>();
            for (Integer i : live) {
                Proof_of_Delivery__c proof = proofs.get(open.get(shipmentIds[i]).Id);
                moves.add(new Shipment__c(Id = shipmentIds[i], Status__c = SHIPMENT_DELIVERED, Actual_Delivery_Date__c = proof?.Received_Date__c?.date()));
            }
            return Database.update(moves, false, AccessLevel.USER_MODE);
        }
    }

    private class RecordFailures extends TwoStepSave {
        private final List<Id> shipmentIds;
        private final List<DeliveryFailureRequest> requests;
        private final Map<Id, Delivery__c> open;

        public RecordFailures(List<Id> shipmentIds, List<DeliveryFailureRequest> requests, Map<Id, Delivery__c> open) {
            this.shipmentIds = shipmentIds;
            this.requests = requests;
            this.open = open;
        }

        public override List<Database.SaveResult> firstStep(List<Integer> live) {
            List<Delivery__c> attempts = new List<Delivery__c>();
            for (Integer i : live) {
                attempts.add(
                    new Delivery__c(
                        Id = open.get(shipmentIds[i]).Id,
                        Delivery_Status__c = DeliveryDomain.FAILED,
                        Failure_Reason__c = requests[i].reason,
                        Failure_Notes__c = requests[i].notes
                    )
                );
            }
            return Database.update(attempts, false, AccessLevel.USER_MODE);
        }

        public override List<Database.SaveResult> secondStep(List<Integer> live) {
            List<Shipment__c> moves = new List<Shipment__c>();
            for (Integer i : live) {
                moves.add(new Shipment__c(Id = shipmentIds[i], Status__c = SHIPMENT_FAILED_DELIVERY));
            }
            return Database.update(moves, false, AccessLevel.USER_MODE);
        }
    }
}
