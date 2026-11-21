/**
 * The single Delivery__c trigger. All logic lives in DeliveryTriggerHandler and DeliveryDomain.
 */
trigger DeliveryTrigger on Delivery__c(before insert, before update, before delete) {
    new DeliveryTriggerHandler().run();
}
