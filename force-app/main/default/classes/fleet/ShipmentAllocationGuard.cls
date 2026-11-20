/**
 * Phase 4 guard (decision Q10; the Phase 2 "vehicle and driver allocation" requirement on
 * Confirmed -> Ready for Dispatch, deferred by decision D3), extended to In Transit (audit round 3,
 * issue 2) so that no route into transit skips it: the configured On Hold -> In Transit transition
 * never passes Ready for Dispatch. Like every guard, it applies under the status override too.
 *
 * In the Shipment__c before-update trigger (where the change is enforced, whatever saved it: UI, API,
 * Flow or a service), a shipment can enter Ready for Dispatch or In Transit only when its Vehicle__c
 * and Driver__c match an open (Planned or Active) assignment AND that assignment still passes every
 * allocation rule against current data (VehicleAssignmentDomain.checkDispatchReadiness): setting the
 * shipment fields by hand is not enough, and an allocation made invalid after the fact (weight,
 * business unit, dates, vehicle or driver status, documents, maintenance, quoted type) is caught here.
 * Validation only; nothing is written.
 *
 * The status policy is evaluated again by TrackingService in the Shipment__c after-update trigger to
 * type the tracking events. A record in that trigger has already passed this guard in the before-update
 * trigger of the same save (a record rejected there never reaches after-update), so the guard trusts
 * exactly those records and does not repeat the locking checks. In any other context it cannot verify
 * the allocation and fails closed.
 */
public with sharing class ShipmentAllocationGuard implements ShipmentStatusGuard {
    public static final String ALLOCATION_REQUIRED = VehicleAssignmentDomain.ALLOCATION_REQUIRED;
    @TestVisible
    private static final String READY_FOR_DISPATCH = 'Ready for Dispatch';
    @TestVisible
    private static final String IN_TRANSIT = 'In Transit';
    private static final Set<String> GUARDED = new Set<String>{ READY_FOR_DISPATCH, IN_TRANSIT };

    public Set<String> targetStatuses() {
        return GUARDED.clone();
    }

    public Map<Integer, ShipmentStatusPolicy.Violation> check(List<ShipmentStatusPolicy.StatusChange> changes) {
        Map<Integer, ShipmentStatusPolicy.Violation> violations = new Map<Integer, ShipmentStatusPolicy.Violation>();
        if (isShipmentTrigger(System.TriggerOperation.BEFORE_UPDATE)) {
            List<Shipment__c> shipments = new List<Shipment__c>();
            for (ShipmentStatusPolicy.StatusChange change : changes) {
                if (change.record != null) {
                    shipments.add(change.record);
                }
            }
            Map<Id, VehicleAvailabilityService.Violation> problems = new VehicleAssignmentDomain().checkDispatchReadiness(shipments);
            for (ShipmentStatusPolicy.StatusChange change : changes) {
                VehicleAvailabilityService.Violation problem = change.record == null ? null : problems.get(change.record.Id);
                if (change.record == null || change.record.Id == null) {
                    violations.put(change.index, required());
                } else if (problem != null) {
                    violations.put(change.index, new ShipmentStatusPolicy.Violation(problem.code, problem.message));
                }
            }
            return violations;
        }

        Boolean afterSameSave = isShipmentTrigger(System.TriggerOperation.AFTER_UPDATE);
        Map<Id, SObject> saved = afterSameSave ? Trigger.newMap : null;
        for (ShipmentStatusPolicy.StatusChange change : changes) {
            Shipment__c record = change.record;
            Shipment__c savedRecord = saved == null || record == null || record.Id == null ? null : (Shipment__c) saved.get(record.Id);
            Boolean alreadyEnforced = savedRecord != null && GUARDED.contains(savedRecord.Status__c) && savedRecord.Status__c == change.toStatus;
            if (!alreadyEnforced) {
                violations.put(change.index, required());
            }
        }
        return violations;
    }

    private static ShipmentStatusPolicy.Violation required() {
        return new ShipmentStatusPolicy.Violation(ALLOCATION_REQUIRED, Label.eLogix_Fleet_Allocation_Required);
    }

    private static Boolean isShipmentTrigger(System.TriggerOperation operation) {
        return Trigger.isExecuting &&
            Trigger.operationType == operation &&
            Trigger.new != null &&
            Trigger.new.getSObjectType() == Shipment__c.SObjectType;
    }
}
