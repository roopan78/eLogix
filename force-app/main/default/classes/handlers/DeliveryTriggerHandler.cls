/**
 * Routes Delivery__c trigger contexts to DeliveryDomain. No business rules here.
 *
 * before insert: attempt rules, numbering and the unique attempt key, under a lock on the shipment.
 * before update: transitions, immutability, proof and evidence checks for Delivered.
 * before delete: always refused (delivery history).
 */
public with sharing class DeliveryTriggerHandler extends TriggerHandler {
    public DeliveryTriggerHandler() {
        super();
    }

    @TestVisible
    private DeliveryTriggerHandler(System.TriggerOperation operation, List<SObject> newList, Map<Id, SObject> oldMap) {
        super(operation, newList, oldMap);
    }

    protected override void beforeInsert() {
        new DeliveryDomain().validateNew((List<Delivery__c>) newList);
    }

    protected override void beforeUpdate() {
        new DeliveryDomain().validateChanges((List<Delivery__c>) newList, (Map<Id, Delivery__c>) oldMap);
    }

    protected override void beforeDelete() {
        new DeliveryDomain().rejectDeletion(oldMap.values());
    }
}
