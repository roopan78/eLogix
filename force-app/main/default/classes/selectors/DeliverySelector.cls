/**
 * SOQL for delivery attempts, proofs of delivery and their evidence files (Phase 5).
 *
 * User-mode reads serve DeliveryService: the caller must be able to see what it acts on.
 * Enforcement reads (locks, attempt numbering, proof and evidence checks, file protection) run in
 * system mode without sharing, in the private EnforcementReader, and only from the trigger context
 * each was built for (TriggerContext.require); any other caller gets an AuthorizationException
 * (DELIVERY_ENFORCEMENT_TRIGGER_ONLY). Same pattern as FleetSelector.
 *
 * Virtual so that a test can substitute a selector whose lock query times out.
 */
public inherited sharing virtual class DeliverySelector {
    public static final String ENFORCEMENT_TRIGGER_ONLY = 'DELIVERY_ENFORCEMENT_TRIGGER_ONLY';
    public static final Set<String> OPEN_STATUSES = new Set<String>{ 'Scheduled', 'Out for Delivery' };

    private static final Set<String> DELIVERY_BEFORE_INSERT = new Set<String>{ 'Delivery__c.BEFORE_INSERT' };
    private static final Set<String> DELIVERY_BEFORE_UPDATE = new Set<String>{ 'Delivery__c.BEFORE_UPDATE' };
    private static final Set<String> ATTEMPT_CONTEXTS = new Set<String>{ 'Delivery__c.BEFORE_INSERT', 'Shipment__c.BEFORE_UPDATE' };
    private static final Set<String> POD_CONTEXTS = new Set<String>{ 'Proof_of_Delivery__c.BEFORE_INSERT', 'Proof_of_Delivery__c.BEFORE_UPDATE' };
    private static final Set<String> PROOF_CONTEXTS = new Set<String>{ 'Delivery__c.BEFORE_UPDATE', 'Proof_of_Delivery__c.BEFORE_INSERT' };
    private static final Set<String> SHIPMENT_AFTER_UPDATE = new Set<String>{ 'Shipment__c.AFTER_UPDATE' };
    private static final Set<String> SHIPMENT_BEFORE_DELETE = new Set<String>{ 'Shipment__c.BEFORE_DELETE' };
    private static final Set<String> FILE_CONTEXTS = new Set<String>{ 'ContentDocument.BEFORE_DELETE', 'ContentVersion.BEFORE_INSERT' };

    private static final EnforcementReader ENFORCEMENT = new EnforcementReader();

    private static void requireContext(Set<String> permitted) {
        TriggerContext.require(permitted, ENFORCEMENT_TRIGGER_ONLY);
    }

    /* ---------------- user-mode reads (DeliveryService) ---------------- */

    /** Shipments the caller can read, locked first: shipment, then its delivery records. */
    public virtual Map<Id, Shipment__c> shipmentsForDelivery(Set<Id> shipmentIds) {
        if (shipmentIds == null || shipmentIds.isEmpty()) {
            return new Map<Id, Shipment__c>();
        }
        return new Map<Id, Shipment__c>(
            [SELECT Id, Name, Status__c FROM Shipment__c WHERE Id IN :shipmentIds WITH USER_MODE FOR UPDATE]
        );
    }

    /** The open (Scheduled or Out for Delivery) attempt of each shipment the caller can read. */
    public Map<Id, Delivery__c> openAttemptByShipment(Set<Id> shipmentIds) {
        Map<Id, Delivery__c> byShipment = new Map<Id, Delivery__c>();
        if (shipmentIds == null || shipmentIds.isEmpty()) {
            return byShipment;
        }
        Set<String> open = OPEN_STATUSES;
        for (Delivery__c attempt : [
            SELECT Id, Shipment__c, Delivery_Status__c, Attempt_Number__c
            FROM Delivery__c
            WHERE Shipment__c IN :shipmentIds AND Delivery_Status__c IN :open
            WITH USER_MODE
        ]) {
            byShipment.put(attempt.Shipment__c, attempt);
        }
        return byShipment;
    }

    /** The proof of delivery of each attempt the caller can read. */
    public Map<Id, Proof_of_Delivery__c> proofByAttempt(Set<Id> deliveryIds) {
        Map<Id, Proof_of_Delivery__c> byAttempt = new Map<Id, Proof_of_Delivery__c>();
        if (deliveryIds == null || deliveryIds.isEmpty()) {
            return byAttempt;
        }
        for (Proof_of_Delivery__c proof : [
            SELECT Id, Delivery__c, Receiver_Name__c, Received_Date__c
            FROM Proof_of_Delivery__c
            WHERE Delivery__c IN :deliveryIds
            WITH USER_MODE
        ]) {
            byAttempt.put(proof.Delivery__c, proof);
        }
        return byAttempt;
    }

    /* ---------------- enforcement reads (trigger context only, without sharing) ---------------- */

    /** Shipments of new attempts, locked so attempt numbers are assigned one transaction at a time. */
    public virtual Map<Id, Shipment__c> lockShipmentsForAttempts(Set<Id> shipmentIds) {
        requireContext(DELIVERY_BEFORE_INSERT);
        return ENFORCEMENT.lockShipments(shipmentIds);
    }

    /** Current status of the shipments of changed attempts. */
    public Map<Id, Shipment__c> shipmentStatuses(Set<Id> shipmentIds) {
        requireContext(DELIVERY_BEFORE_UPDATE);
        return ENFORCEMENT.shipments(shipmentIds);
    }

    /** Every attempt of the given shipments (numbering, open and delivered checks, shipment delivery guard). */
    public List<Delivery__c> attemptsOfShipments(Set<Id> shipmentIds) {
        requireContext(ATTEMPT_CONTEXTS);
        return ENFORCEMENT.attemptsOfShipments(shipmentIds);
    }

    /** Attempts that proofs of delivery belong to. */
    public Map<Id, Delivery__c> attempts(Set<Id> deliveryIds) {
        requireContext(POD_CONTEXTS);
        return ENFORCEMENT.attempts(deliveryIds);
    }

    /** Proofs of delivery of the given attempts. */
    public List<Proof_of_Delivery__c> proofsOfAttempts(Set<Id> deliveryIds) {
        requireContext(PROOF_CONTEXTS);
        return ENFORCEMENT.proofsOfAttempts(deliveryIds);
    }

    /** The proofs of delivery, among those given, that have at least one file attached. */
    public Set<Id> proofIdsWithFiles(Set<Id> proofIds) {
        requireContext(DELIVERY_BEFORE_UPDATE);
        return ENFORCEMENT.proofIdsWithFiles(proofIds);
    }

    /** Open attempts of the given shipments, locked (closure on cancellation, D2). */
    public virtual List<Delivery__c> lockOpenAttemptsOfShipments(Set<Id> shipmentIds) {
        requireContext(SHIPMENT_AFTER_UPDATE);
        return ENFORCEMENT.lockOpenAttemptsOfShipments(shipmentIds);
    }

    /** The shipments, among those given, that have a proof of delivery. */
    public Set<Id> shipmentIdsWithProofs(Set<Id> shipmentIds) {
        requireContext(SHIPMENT_BEFORE_DELETE);
        return ENFORCEMENT.shipmentIdsWithProofs(shipmentIds);
    }

    /** The documents, among those given, that are linked to any proof of delivery (D5). */
    public Set<Id> documentIdsLinkedToProofs(Set<Id> documentIds) {
        requireContext(FILE_CONTEXTS);
        return ENFORCEMENT.documentIdsLinkedToProofs(documentIds);
    }

    /**
     * The enforcement queries, without sharing: attempt numbering, the one-open and one-delivered
     * rules, proof and evidence checks and file protection must see every record, whoever owns it.
     * Reachable only through the trigger-context-checked methods above; results go only to the rules.
     */
    private without sharing class EnforcementReader {
        public Map<Id, Shipment__c> lockShipments(Set<Id> shipmentIds) {
            if (shipmentIds == null || shipmentIds.isEmpty()) {
                return new Map<Id, Shipment__c>();
            }
            return new Map<Id, Shipment__c>(
                [SELECT Id, Name, Status__c, Driver__c FROM Shipment__c WHERE Id IN :shipmentIds WITH SYSTEM_MODE FOR UPDATE]
            );
        }

        public Map<Id, Shipment__c> shipments(Set<Id> shipmentIds) {
            if (shipmentIds == null || shipmentIds.isEmpty()) {
                return new Map<Id, Shipment__c>();
            }
            return new Map<Id, Shipment__c>([SELECT Id, Name, Status__c FROM Shipment__c WHERE Id IN :shipmentIds WITH SYSTEM_MODE]);
        }

        public List<Delivery__c> attemptsOfShipments(Set<Id> shipmentIds) {
            if (shipmentIds == null || shipmentIds.isEmpty()) {
                return new List<Delivery__c>();
            }
            return [
                SELECT Id, Shipment__c, Delivery_Status__c, Attempt_Number__c
                FROM Delivery__c
                WHERE Shipment__c IN :shipmentIds
                WITH SYSTEM_MODE
            ];
        }

        public Map<Id, Delivery__c> attempts(Set<Id> deliveryIds) {
            if (deliveryIds == null || deliveryIds.isEmpty()) {
                return new Map<Id, Delivery__c>();
            }
            return new Map<Id, Delivery__c>(
                [SELECT Id, Shipment__c, Delivery_Status__c FROM Delivery__c WHERE Id IN :deliveryIds WITH SYSTEM_MODE]
            );
        }

        public List<Proof_of_Delivery__c> proofsOfAttempts(Set<Id> deliveryIds) {
            if (deliveryIds == null || deliveryIds.isEmpty()) {
                return new List<Proof_of_Delivery__c>();
            }
            return [
                SELECT Id, Delivery__c, Receiver_Name__c, Received_Date__c
                FROM Proof_of_Delivery__c
                WHERE Delivery__c IN :deliveryIds
                WITH SYSTEM_MODE
            ];
        }

        public Set<Id> proofIdsWithFiles(Set<Id> proofIds) {
            Set<Id> withFiles = new Set<Id>();
            if (proofIds == null || proofIds.isEmpty()) {
                return withFiles;
            }
            for (ContentDocumentLink link : [
                SELECT LinkedEntityId
                FROM ContentDocumentLink
                WHERE LinkedEntityId IN :proofIds
                WITH SYSTEM_MODE
            ]) {
                withFiles.add(link.LinkedEntityId);
            }
            return withFiles;
        }

        public List<Delivery__c> lockOpenAttemptsOfShipments(Set<Id> shipmentIds) {
            if (shipmentIds == null || shipmentIds.isEmpty()) {
                return new List<Delivery__c>();
            }
            Set<String> open = OPEN_STATUSES;
            return [
                SELECT Id, Shipment__c, Delivery_Status__c
                FROM Delivery__c
                WHERE Shipment__c IN :shipmentIds AND Delivery_Status__c IN :open
                WITH SYSTEM_MODE
                FOR UPDATE
            ];
        }

        public Set<Id> shipmentIdsWithProofs(Set<Id> shipmentIds) {
            Set<Id> result = new Set<Id>();
            if (shipmentIds == null || shipmentIds.isEmpty()) {
                return result;
            }
            for (Proof_of_Delivery__c proof : [
                SELECT Delivery__r.Shipment__c
                FROM Proof_of_Delivery__c
                WHERE Delivery__r.Shipment__c IN :shipmentIds
                WITH SYSTEM_MODE
            ]) {
                result.add(proof.Delivery__r.Shipment__c);
            }
            return result;
        }

        public Set<Id> documentIdsLinkedToProofs(Set<Id> documentIds) {
            Set<Id> linked = new Set<Id>();
            if (documentIds == null || documentIds.isEmpty()) {
                return linked;
            }
            for (ContentDocumentLink link : [
                SELECT ContentDocumentId, LinkedEntityId
                FROM ContentDocumentLink
                WHERE ContentDocumentId IN :documentIds
                WITH SYSTEM_MODE
            ]) {
                if (link.LinkedEntityId != null && link.LinkedEntityId.getSObjectType() == Proof_of_Delivery__c.SObjectType) {
                    linked.add(link.ContentDocumentId);
                }
            }
            return linked;
        }
    }
}
