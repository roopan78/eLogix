/**
 * Routes Vehicle_Assignment__c trigger contexts to VehicleAssignmentDomain. No business rules here.
 *
 * before insert / update: permission, transitions, immutability, dispatch history, eligibility under row locks.
 * before delete / after undelete: always refused (cancellation is the only release; history is kept).
 * after insert / update:  mirror the vehicle and driver onto the shipment (the domain reads the trigger itself).
 * after update:           record allocation corrections in tracking history.
 */
public with sharing class VehicleAssignmentTriggerHandler extends TriggerHandler {
    public VehicleAssignmentTriggerHandler() {
        super();
    }

    @TestVisible
    private VehicleAssignmentTriggerHandler(System.TriggerOperation operation, List<SObject> newList, Map<Id, SObject> oldMap) {
        super(operation, newList, oldMap);
    }

    protected override void beforeInsert() {
        new VehicleAssignmentDomain().validateNew((List<Vehicle_Assignment__c>) newList);
    }

    protected override void beforeUpdate() {
        new VehicleAssignmentDomain().validateChanges((List<Vehicle_Assignment__c>) newList, (Map<Id, Vehicle_Assignment__c>) oldMap);
    }

    protected override void beforeDelete() {
        new VehicleAssignmentDomain().rejectDeletion(oldMap.values());
    }

    protected override void afterInsert() {
        new VehicleAssignmentDomain().syncShipments();
    }

    protected override void afterUpdate() {
        VehicleAssignmentDomain domain = new VehicleAssignmentDomain();
        domain.syncShipments();
        domain.recordCorrections();
    }

    protected override void afterUndelete() {
        new VehicleAssignmentDomain().rejectRestore(newList);
    }
}
