/**
 * The single Vehicle_Assignment__c trigger. All logic lives in VehicleAssignmentTriggerHandler and VehicleAssignmentDomain.
 */
trigger VehicleAssignmentTrigger on Vehicle_Assignment__c(before insert, before update, before delete, after insert, after update, after undelete) {
    new VehicleAssignmentTriggerHandler().run();
}
