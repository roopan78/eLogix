/**
 * Routes Proof_of_Delivery__c trigger contexts to ProofOfDeliveryDomain. No business rules here.
 *
 * before insert / update: open-attempt, one-proof, lock-after-closure and verification rules.
 * before delete: always refused (delivery evidence).
 */
public with sharing class ProofOfDeliveryTriggerHandler extends TriggerHandler {
    public ProofOfDeliveryTriggerHandler() {
        super();
    }

    @TestVisible
    private ProofOfDeliveryTriggerHandler(System.TriggerOperation operation, List<SObject> newList, Map<Id, SObject> oldMap) {
        super(operation, newList, oldMap);
    }

    protected override void beforeInsert() {
        new ProofOfDeliveryDomain().validateNew((List<Proof_of_Delivery__c>) newList);
    }

    protected override void beforeUpdate() {
        new ProofOfDeliveryDomain().validateChanges((List<Proof_of_Delivery__c>) newList, (Map<Id, Proof_of_Delivery__c>) oldMap);
    }

    protected override void beforeDelete() {
        new ProofOfDeliveryDomain().rejectDeletion(oldMap.values());
    }
}
