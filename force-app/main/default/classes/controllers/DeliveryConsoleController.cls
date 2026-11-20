/**
 * Phase 7 LWC controller for deliveryManagement. Thin: every action delegates to DeliveryService, the
 * only owner of Out for Delivery, Delivered and Failed Delivery (decision P5). Evidence files are
 * uploaded by the component with lightning-file-upload against the proof Id that recordProof returns.
 */
public with sharing class DeliveryConsoleController {
    private static final String LOG_CONTEXT = 'DeliveryConsoleController';

    public class DeliveryState {
        @AuraEnabled
        public List<Delivery__c> attempts;
        @AuraEnabled
        public List<Proof_of_Delivery__c> proofs;
    }

    /** The shipment's delivery attempts (newest first) and their proofs, as the user may read them. */
    @AuraEnabled
    public static DeliveryState getDeliveryState(Id shipmentId) {
        try {
            DeliveryState state = new DeliveryState();
            state.attempts = [
                SELECT
                    Id,
                    Name,
                    Attempt_Number__c,
                    Delivery_Status__c,
                    Delivery_Date__c,
                    Receiver_Name__c,
                    Failure_Reason__c,
                    Failure_Notes__c,
                    Delivered_By__r.Name
                FROM Delivery__c
                WHERE Shipment__c = :shipmentId
                WITH USER_MODE
                ORDER BY Attempt_Number__c DESC
            ];
            state.proofs = [
                SELECT
                    Id,
                    Name,
                    Delivery__c,
                    Receiver_Name__c,
                    Received_Date__c,
                    Signature_Reference__c,
                    Delivery_Notes__c,
                    Has_Exception__c,
                    Exception_Notes__c,
                    Verified_By__r.Name
                FROM Proof_of_Delivery__c
                WHERE Shipment__c = :shipmentId
                WITH USER_MODE
                ORDER BY CreatedDate DESC
            ];
            return state;
        } catch (Exception e) {
            throw toAura(e);
        }
    }

    @AuraEnabled
    public static ServiceResult startAttempt(Id shipmentId) {
        try {
            return new DeliveryService().startAttempts(new List<Id>{ shipmentId });
        } catch (Exception e) {
            throw toAura(e);
        }
    }

    @AuraEnabled
    public static ServiceResult recordProof(ProofOfDeliveryRequest request) {
        try {
            return new DeliveryService().recordProofs(new List<ProofOfDeliveryRequest>{ request });
        } catch (Exception e) {
            throw toAura(e);
        }
    }

    @AuraEnabled
    public static ServiceResult confirmDelivery(Id shipmentId) {
        try {
            return new DeliveryService().confirmDeliveries(new List<Id>{ shipmentId });
        } catch (Exception e) {
            throw toAura(e);
        }
    }

    @AuraEnabled
    public static ServiceResult recordFailure(DeliveryFailureRequest request) {
        try {
            return new DeliveryService().recordFailures(new List<DeliveryFailureRequest>{ request });
        } catch (Exception e) {
            throw toAura(e);
        }
    }

    @AuraEnabled
    public static ServiceResult verifyProof(Id proofId) {
        try {
            return new DeliveryService().verifyProofs(new List<Id>{ proofId });
        } catch (Exception e) {
            throw toAura(e);
        }
    }

    private static AuraHandledException toAura(Exception e) {
        String message = ExceptionHandler.toUserMessage(e, LOG_CONTEXT);
        AuraHandledException error = new AuraHandledException(message);
        error.setMessage(message);
        return error;
    }
}
