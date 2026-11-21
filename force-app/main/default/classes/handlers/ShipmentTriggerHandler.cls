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
        // Phase 4 (Q11): a cancelled shipment drops the vehicle and driver of its Planned assignment.
        new FleetAllocationService().clearCancelledShipmentAllocations();
    }

    /** TrackingService reads Trigger.new and Trigger.oldMap itself; see TrackingService.recordStatusEvents. */
    protected override void afterInsert() {
        new TrackingService().recordStatusEvents();
    }

    /** Phase 4 (audit round 3): a shipment with a Planned or Active vehicle assignment cannot be deleted. */
    protected override void beforeDelete() {
        new FleetAllocationService().rejectDeletionWithOpenAssignments();
        // Phase 5 (D5): proof of delivery evidence keeps its shipment.
        new DeliveryService().rejectDeletionWithProofOfDelivery();
    }

    protected override void afterUpdate() {
        new TrackingService().recordStatusEvents();
        // Phase 4 (Q11): ...and its Planned assignment is cancelled, freeing the vehicle and driver.
        new FleetAllocationService().releaseCancelledShipmentAssignments();
        // Phase 5: Dispatched / In Transit activate the assignment; a trip-ending status completes it.
        new FleetAllocationService().advanceAssignmentLifecycle();
        // Phase 5 (D2): a shipment cancelled after dispatch closes its open delivery attempt.
        new DeliveryService().closeAttemptsOfCancelledShipments();
    }
}
