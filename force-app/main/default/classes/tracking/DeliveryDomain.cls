/**
 * Delivery attempt rules (Phase 5) that hold on every entry path: DeliveryService, the UI, the API,
 * Data Loader and automation. Called by DeliveryTriggerHandler. See docs/DELIVERY_IMPLEMENTATION.md.
 *
 * before insert  status Scheduled or Out for Delivery; shipment In Transit, Delayed or Failed Delivery;
 *                no open attempt and no delivered attempt for the shipment; attempt number and the
 *                unique attempt key assigned here, under a lock on the shipment, never by the caller;
 *                at most Max_Delivery_Attempts attempts (D4)
 * before update  shipment, number and key immutable; Delivered and Failed attempts are history and
 *                cannot change; Scheduled -> Out for Delivery | Failed, Out for Delivery -> Delivered |
 *                Failed; Delivered needs the shipment Out for Delivery and a proof of delivery with the
 *                receiver, the time received and (POD_File_Required) at least one file; Failed needs
 *                the shipment Out for Delivery, or Cancelled (the closure of D2)
 * before delete  always refused: attempts are delivery history
 */
public with sharing class DeliveryDomain {
    public static final String SCHEDULED = 'Scheduled';
    public static final String OUT_FOR_DELIVERY = 'Out for Delivery';
    public static final String DELIVERED = 'Delivered';
    public static final String FAILED = 'Failed';
    public static final Set<String> OPEN = new Set<String>{ SCHEDULED, OUT_FOR_DELIVERY };
    public static final String MAX_ATTEMPTS_SETTING = 'Max_Delivery_Attempts';
    public static final String FILE_REQUIRED_SETTING = 'POD_File_Required';

    /** Shipment statuses from which a new attempt can start. */
    @TestVisible
    private static final Set<String> ATTEMPTABLE_SHIPMENT_STATUSES = new Set<String>{ 'In Transit', 'Delayed', 'Failed Delivery' };
    private static final Set<String> SUPPORTED = new Set<String>{ SCHEDULED, OUT_FOR_DELIVERY, DELIVERED, FAILED };
    private static final Map<String, Set<String>> TRANSITIONS = new Map<String, Set<String>>{
        SCHEDULED => new Set<String>{ OUT_FOR_DELIVERY, FAILED },
        OUT_FOR_DELIVERY => new Set<String>{ DELIVERED, FAILED }
    };
    private static final String SHIPMENT_OUT_FOR_DELIVERY = 'Out for Delivery';
    private static final String SHIPMENT_CANCELLED = 'Cancelled';
    private static final List<Schema.SObjectField> HISTORY_FIELDS = new List<Schema.SObjectField>{
        Delivery__c.Delivery_Status__c,
        Delivery__c.Receiver_Name__c,
        Delivery__c.Receiver_Phone__c,
        Delivery__c.Delivery_Date__c,
        Delivery__c.Failure_Reason__c,
        Delivery__c.Failure_Notes__c,
        Delivery__c.Delivered_By__c
    };

    /** Test seam for lock timeouts. */
    @TestVisible
    private static DeliverySelector selector = new DeliverySelector();

    /* ------------------------------------------------------------------ */
    /* Before insert                                                       */
    /* ------------------------------------------------------------------ */

    public void validateNew(List<Delivery__c> records) {
        Set<Id> shipmentIds = new Set<Id>();
        for (Delivery__c attempt : records) {
            if (attempt.Shipment__c != null) {
                shipmentIds.add(attempt.Shipment__c);
            }
        }
        if (shipmentIds.isEmpty()) {
            return;
        }
        Map<Id, Shipment__c> shipments;
        try {
            shipments = selector.lockShipmentsForAttempts(shipmentIds);
        } catch (QueryException e) {
            if (!VehicleAssignmentDomain.isLockTimeout(e)) {
                throw e;
            }
            for (Delivery__c attempt : records) {
                attempt.addError(Label.eLogix_Delivery_Busy);
            }
            return;
        }
        Map<Id, Integer> highestNumber = new Map<Id, Integer>();
        Set<Id> hasOpen = new Set<Id>();
        Set<Id> hasDelivered = new Set<Id>();
        for (Delivery__c existing : selector.attemptsOfShipments(shipmentIds)) {
            Integer attemptNumber = existing.Attempt_Number__c == null ? 0 : existing.Attempt_Number__c.intValue();
            if (!highestNumber.containsKey(existing.Shipment__c) || attemptNumber > highestNumber.get(existing.Shipment__c)) {
                highestNumber.put(existing.Shipment__c, attemptNumber);
            }
            if (OPEN.contains(existing.Delivery_Status__c)) {
                hasOpen.add(existing.Shipment__c);
            } else if (DELIVERED.equals(existing.Delivery_Status__c)) {
                hasDelivered.add(existing.Shipment__c);
            }
        }
        Integer maxAttempts = SettingsService.getNumber(MAX_ATTEMPTS_SETTING).intValue();

        for (Delivery__c attempt : records) {
            Shipment__c shipment = shipments.get(attempt.Shipment__c);
            if (shipment == null) {
                continue; // the master-detail relationship reports a missing shipment itself
            }
            String error = newAttemptError(attempt, shipment, hasOpen, hasDelivered);
            Integer attemptNumber = (highestNumber.containsKey(shipment.Id) ? highestNumber.get(shipment.Id) : 0) + 1;
            if (error == null && attemptNumber > maxAttempts) {
                error = String.format(Label.eLogix_Delivery_Max_Attempts, new List<Object>{ shipment.Name, maxAttempts });
            }
            if (error != null) {
                attempt.addError(error);
                continue;
            }
            // D4 and requirement 2: numbered here, under the shipment lock; the key is unique in the database.
            attempt.Attempt_Number__c = attemptNumber;
            attempt.Attempt_Key__c = attemptKey(shipment.Id, attemptNumber);
            if (attempt.Delivered_By__c == null) {
                attempt.Delivered_By__c = shipment.Driver__c;
            }
            highestNumber.put(shipment.Id, attemptNumber);
            hasOpen.add(shipment.Id);
        }
    }

    private static String newAttemptError(Delivery__c attempt, Shipment__c shipment, Set<Id> hasOpen, Set<Id> hasDelivered) {
        if (!SUPPORTED.contains(attempt.Delivery_Status__c)) {
            return String.format(Label.eLogix_Delivery_Status_Not_Supported, new List<Object>{ attempt.Delivery_Status__c });
        }
        if (!OPEN.contains(attempt.Delivery_Status__c)) {
            return String.format(Label.eLogix_Delivery_Transition_Not_Allowed, new List<Object>{ 'New', attempt.Delivery_Status__c });
        }
        if (hasDelivered.contains(shipment.Id)) {
            return String.format(Label.eLogix_Delivery_Already_Delivered, new List<Object>{ shipment.Name });
        }
        if (hasOpen.contains(shipment.Id)) {
            return String.format(Label.eLogix_Delivery_Attempt_Open, new List<Object>{ shipment.Name });
        }
        if (!ATTEMPTABLE_SHIPMENT_STATUSES.contains(shipment.Status__c)) {
            return String.format(Label.eLogix_Delivery_Attempt_Not_Allowed, new List<Object>{ shipment.Name });
        }
        return null;
    }

    public static String attemptKey(Id shipmentId, Integer attemptNumber) {
        return String.valueOf(shipmentId) + ':' + attemptNumber;
    }

    /* ------------------------------------------------------------------ */
    /* Before update                                                       */
    /* ------------------------------------------------------------------ */

    public void validateChanges(List<Delivery__c> records, Map<Id, Delivery__c> oldById) {
        List<Delivery__c> closing = new List<Delivery__c>();
        Set<Id> shipmentIds = new Set<Id>();
        Set<Id> delivering = new Set<Id>();
        for (Delivery__c attempt : records) {
            Delivery__c previous = oldById.get(attempt.Id);
            String error = changeError(attempt, previous);
            if (error != null) {
                attempt.addError(error);
                continue;
            }
            Boolean statusChanged = !VehicleAssignmentDomain.sameText(attempt.Delivery_Status__c, previous.Delivery_Status__c);
            if (statusChanged && (DELIVERED.equals(attempt.Delivery_Status__c) || FAILED.equals(attempt.Delivery_Status__c))) {
                closing.add(attempt);
                shipmentIds.add(attempt.Shipment__c);
                if (DELIVERED.equals(attempt.Delivery_Status__c)) {
                    delivering.add(attempt.Id);
                }
            }
        }
        if (closing.isEmpty()) {
            return;
        }
        Map<Id, Shipment__c> shipments = selector.shipmentStatuses(shipmentIds);
        Map<Id, Proof_of_Delivery__c> proofByAttempt = new Map<Id, Proof_of_Delivery__c>();
        Set<Id> proofsWithFiles = new Set<Id>();
        if (!delivering.isEmpty()) {
            for (Proof_of_Delivery__c proof : selector.proofsOfAttempts(delivering)) {
                proofByAttempt.put(proof.Delivery__c, proof);
            }
            Boolean fileRequired = SettingsService.getBoolean(FILE_REQUIRED_SETTING) == true;
            if (fileRequired && !proofByAttempt.isEmpty()) {
                Set<Id> proofIds = new Set<Id>();
                for (Proof_of_Delivery__c proof : proofByAttempt.values()) {
                    proofIds.add(proof.Id);
                }
                proofsWithFiles = selector.proofIdsWithFiles(proofIds);
            } else if (!fileRequired) {
                proofsWithFiles = null; // not checked
            }
        }
        for (Delivery__c attempt : closing) {
            Shipment__c shipment = shipments.get(attempt.Shipment__c);
            String shipmentStatus = shipment?.Status__c;
            String name = shipment?.Name;
            if (DELIVERED.equals(attempt.Delivery_Status__c)) {
                Proof_of_Delivery__c proof = proofByAttempt.get(attempt.Id);
                if (!SHIPMENT_OUT_FOR_DELIVERY.equals(shipmentStatus)) {
                    attempt.addError(String.format(Label.eLogix_Delivery_Confirm_Status, new List<Object>{ name }));
                } else if (proof == null || String.isBlank(proof.Receiver_Name__c) || proof.Received_Date__c == null) {
                    attempt.addError(Label.eLogix_Delivery_Pod_Required);
                } else if (proofsWithFiles != null && !proofsWithFiles.contains(proof.Id)) {
                    attempt.addError(Label.eLogix_Delivery_Evidence_Required);
                }
            } else if (!SHIPMENT_OUT_FOR_DELIVERY.equals(shipmentStatus) && !SHIPMENT_CANCELLED.equals(shipmentStatus)) {
                attempt.addError(String.format(Label.eLogix_Delivery_Fail_Status, new List<Object>{ name }));
            }
        }
    }

    private static String changeError(Delivery__c attempt, Delivery__c previous) {
        if (
            attempt.Shipment__c != previous.Shipment__c ||
            attempt.Attempt_Number__c != previous.Attempt_Number__c ||
            !VehicleAssignmentDomain.sameText(attempt.Attempt_Key__c, previous.Attempt_Key__c)
        ) {
            return Label.eLogix_Delivery_Attempt_Immutable;
        }
        String fromStatus = previous.Delivery_Status__c;
        String toStatus = attempt.Delivery_Status__c;
        if (DELIVERED.equals(fromStatus) || FAILED.equals(fromStatus) || !SUPPORTED.contains(fromStatus)) {
            for (Schema.SObjectField field : HISTORY_FIELDS) {
                if (attempt.get(field) != previous.get(field)) {
                    return String.format(Label.eLogix_Delivery_Attempt_Locked, new List<Object>{ fromStatus });
                }
            }
            return null;
        }
        if (VehicleAssignmentDomain.sameText(fromStatus, toStatus)) {
            return null;
        }
        if (!SUPPORTED.contains(toStatus)) {
            return String.format(Label.eLogix_Delivery_Status_Not_Supported, new List<Object>{ toStatus });
        }
        Set<String> allowed = TRANSITIONS.get(fromStatus);
        if (allowed == null || !allowed.contains(toStatus)) {
            return String.format(Label.eLogix_Delivery_Transition_Not_Allowed, new List<Object>{ fromStatus, toStatus });
        }
        return null;
    }

    /* ------------------------------------------------------------------ */
    /* Before delete                                                       */
    /* ------------------------------------------------------------------ */

    public void rejectDeletion(List<SObject> records) {
        for (SObject record : records) {
            record.addError(Label.eLogix_Delivery_Delete_Not_Allowed);
        }
    }
}
