/**
 * The single Proof_of_Delivery__c trigger. All logic lives in ProofOfDeliveryTriggerHandler and ProofOfDeliveryDomain.
 */
trigger ProofOfDeliveryTrigger on Proof_of_Delivery__c(before insert, before update, before delete) {
    new ProofOfDeliveryTriggerHandler().run();
}
