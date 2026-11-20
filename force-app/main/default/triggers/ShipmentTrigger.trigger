/**
 * The single Shipment__c trigger. All logic lives in ShipmentTriggerHandler and the classes it calls.
 */
trigger ShipmentTrigger on Shipment__c(before insert, before update, before delete, after insert, after update) {
    new ShipmentTriggerHandler().run();
}
