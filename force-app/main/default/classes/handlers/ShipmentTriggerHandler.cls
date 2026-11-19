/**
 * Routes Shipment__c trigger contexts. No business rules here.
 *
 * before insert / update: ShipmentDomain applies ShipmentStatusPolicy (reject or stamp).
 * after insert / update:  TrackingService records one tracking event per allowed status change.
 *
 * Saves without a status change, such as the roll-up recalculation after an item is added, cost
 * no SOQL and no DML.
 */
public with sharing class ShipmentTriggerHandler extends TriggerHandler {
    public ShipmentTriggerHandler() {
        super();
    }

    @TestVisible
    private ShipmentTriggerHandler(System.TriggerOperation operation, List<SObject> newList, Map<Id, SObject> oldMap) {
        super(operation, newList, oldMap);
    }

    protected override void beforeInsert() {
        new ShipmentDomain().validateNewShipments((List<Shipment__c>) newList);
    }

    protected override void beforeUpdate() {
        new ShipmentDomain().validateStatusChanges((List<Shipment__c>) newList, (Map<Id, Shipment__c>) oldMap);
    }

    /** TrackingService reads Trigger.new and Trigger.oldMap itself; see TrackingService.recordStatusEvents. */
    protected override void afterInsert() {
        new TrackingService().recordStatusEvents();
    }

    protected override void afterUpdate() {
        new TrackingService().recordStatusEvents();
    }
}
