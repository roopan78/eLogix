/**
 * Proof of delivery rules (Phase 5, D5). Called by ProofOfDeliveryTriggerHandler.
 *
 * Lifecycle: an open attempt exists (DeliveryService.startAttempts); the proof is recorded against it
 * (recordProofs, or directly); its evidence files are uploaded to the proof record; the delivery is
 * then confirmed, which checks the proof and its files (DeliveryDomain). While the attempt is open the
 * proof can be corrected. Once the attempt is Delivered or Failed the proof is history: only its
 * verification can be recorded, once, in the name of the verifying user. Proofs are never deleted.
 *
 * before insert  the attempt must be open; one proof per attempt; Shipment__c derived from the
 *                attempt; not verified at creation; Received_Date__c defaults to now
 * before update  as above while open; locked except for verification once closed
 * before delete  always refused
 */
public with sharing class ProofOfDeliveryDomain {
    private static final List<Schema.SObjectField> EVIDENCE_FIELDS = new List<Schema.SObjectField>{
        Proof_of_Delivery__c.Receiver_Name__c,
        Proof_of_Delivery__c.Signature_Reference__c,
        Proof_of_Delivery__c.Received_Date__c,
        Proof_of_Delivery__c.Has_Exception__c,
        Proof_of_Delivery__c.Exception_Notes__c,
        Proof_of_Delivery__c.Delivery_Notes__c,
        Proof_of_Delivery__c.Shipment__c,
        Proof_of_Delivery__c.Delivery__c
    };

    @TestVisible
    private static DeliverySelector selector = new DeliverySelector();

    public void validateNew(List<Proof_of_Delivery__c> records) {
        Set<Id> deliveryIds = new Set<Id>();
        for (Proof_of_Delivery__c proof : records) {
            if (proof.Delivery__c != null) {
                deliveryIds.add(proof.Delivery__c);
            }
        }
        if (deliveryIds.isEmpty()) {
            return;
        }
        Map<Id, Delivery__c> attempts = selector.attempts(deliveryIds);
        Set<Id> withProof = new Set<Id>();
        for (Proof_of_Delivery__c existing : selector.proofsOfAttempts(deliveryIds)) {
            withProof.add(existing.Delivery__c);
        }
        for (Proof_of_Delivery__c proof : records) {
            Delivery__c attempt = attempts.get(proof.Delivery__c);
            if (attempt == null) {
                continue; // the master-detail relationship reports a missing attempt itself
            }
            if (!DeliveryDomain.OPEN.contains(attempt.Delivery_Status__c)) {
                proof.addError(Label.eLogix_Delivery_Pod_Attempt_Closed);
            } else if (withProof.contains(attempt.Id)) {
                proof.addError(Label.eLogix_Delivery_Pod_Exists);
            } else if (proof.Verified_By__c != null) {
                proof.addError(Label.eLogix_Delivery_Pod_Verification);
            } else {
                proof.Shipment__c = attempt.Shipment__c;
                if (proof.Received_Date__c == null) {
                    proof.Received_Date__c = System.now();
                }
                withProof.add(attempt.Id);
            }
        }
    }

    public void validateChanges(List<Proof_of_Delivery__c> records, Map<Id, Proof_of_Delivery__c> oldById) {
        Set<Id> deliveryIds = new Set<Id>();
        for (Proof_of_Delivery__c proof : records) {
            deliveryIds.add(oldById.get(proof.Id).Delivery__c);
        }
        Map<Id, Delivery__c> attempts = selector.attempts(deliveryIds);
        Id me = UserInfo.getUserId();
        for (Proof_of_Delivery__c proof : records) {
            Proof_of_Delivery__c previous = oldById.get(proof.Id);
            Delivery__c attempt = attempts.get(previous.Delivery__c);
            Boolean open = attempt != null && DeliveryDomain.OPEN.contains(attempt.Delivery_Status__c);
            Boolean evidenceChanged = false;
            for (Schema.SObjectField field : EVIDENCE_FIELDS) {
                if (proof.get(field) != previous.get(field)) {
                    evidenceChanged = true;
                }
            }
            Boolean verificationChanged = proof.Verified_By__c != previous.Verified_By__c;
            if (open) {
                if (verificationChanged) {
                    proof.addError(Label.eLogix_Delivery_Pod_Verification); // only after delivery
                } else if (proof.Delivery__c != previous.Delivery__c || proof.Shipment__c != previous.Shipment__c) {
                    proof.addError(Label.eLogix_Delivery_Pod_Locked);
                }
                continue;
            }
            if (evidenceChanged) {
                proof.addError(Label.eLogix_Delivery_Pod_Locked);
            } else if (verificationChanged) {
                Boolean delivered = attempt != null && DeliveryDomain.DELIVERED.equals(attempt.Delivery_Status__c);
                if (!delivered || previous.Verified_By__c != null || proof.Verified_By__c != me) {
                    proof.addError(Label.eLogix_Delivery_Pod_Verification);
                }
            }
        }
    }

    public void rejectDeletion(List<SObject> records) {
        for (SObject record : records) {
            record.addError(Label.eLogix_Delivery_Delete_Not_Allowed);
        }
    }
}
