/**
 * Phase 5 status guard: the shipment's delivery statuses must agree with its delivery attempts, on
 * every path (DeliveryService, UI, API, Flow) and, like every guard, under the status override too.
 *
 *   Out for Delivery  its latest attempt is open (Scheduled or Out for Delivery)
 *   Delivered         its latest attempt is Delivered (which itself required the proof of delivery,
 *                     the time received and, when configured, an evidence file)
 *   Failed Delivery   its latest attempt is Failed (with its reason)
 *
 * Enforced in the Shipment__c before-update trigger. In the after-update trigger (TrackingService
 * re-evaluates the policy to type tracking events) it trusts exactly the records of the same save that
 * now hold the target status; anywhere else it fails closed. Validation only.
 */
public with sharing class ShipmentDeliveryGuard implements ShipmentStatusGuard {
    public static final String DELIVERY_REQUIRED = 'DELIVERY_REQUIRED';
    @TestVisible
    private static final String OUT_FOR_DELIVERY = 'Out for Delivery';
    @TestVisible
    private static final String DELIVERED = 'Delivered';
    @TestVisible
    private static final String FAILED_DELIVERY = 'Failed Delivery';
    private static final Set<String> GUARDED = new Set<String>{ OUT_FOR_DELIVERY, DELIVERED, FAILED_DELIVERY };

    @TestVisible
    private static DeliverySelector selector = new DeliverySelector();

    public Set<String> targetStatuses() {
        return GUARDED.clone();
    }

    public Map<Integer, ShipmentStatusPolicy.Violation> check(List<ShipmentStatusPolicy.StatusChange> changes) {
        Map<Integer, ShipmentStatusPolicy.Violation> violations = new Map<Integer, ShipmentStatusPolicy.Violation>();
        if (isShipmentTrigger(System.TriggerOperation.BEFORE_UPDATE)) {
            Set<Id> shipmentIds = new Set<Id>();
            for (ShipmentStatusPolicy.StatusChange change : changes) {
                if (change.record != null && change.record.Id != null) {
                    shipmentIds.add(change.record.Id);
                }
            }
            Map<Id, Delivery__c> latest = new Map<Id, Delivery__c>();
            if (!shipmentIds.isEmpty()) {
                for (Delivery__c attempt : selector.attemptsOfShipments(shipmentIds)) {
                    Delivery__c current = latest.get(attempt.Shipment__c);
                    if (current == null || attempt.Attempt_Number__c > current.Attempt_Number__c) {
                        latest.put(attempt.Shipment__c, attempt);
                    }
                }
            }
            for (ShipmentStatusPolicy.StatusChange change : changes) {
                Delivery__c attempt = change.record == null ? null : latest.get(change.record.Id);
                String attemptStatus = attempt?.Delivery_Status__c;
                Boolean ok =
                    (OUT_FOR_DELIVERY.equals(change.toStatus) && DeliveryDomain.OPEN.contains(attemptStatus)) ||
                    (DELIVERED.equals(change.toStatus) && DeliveryDomain.DELIVERED.equals(attemptStatus)) ||
                    (FAILED_DELIVERY.equals(change.toStatus) && DeliveryDomain.FAILED.equals(attemptStatus));
                if (!ok) {
                    violations.put(change.index, violation(change.toStatus));
                }
            }
            return violations;
        }

        Map<Id, SObject> saved = isShipmentTrigger(System.TriggerOperation.AFTER_UPDATE) ? Trigger.newMap : null;
        for (ShipmentStatusPolicy.StatusChange change : changes) {
            Shipment__c record = change.record;
            Shipment__c savedRecord = saved == null || record == null || record.Id == null ? null : (Shipment__c) saved.get(record.Id);
            if (savedRecord == null || savedRecord.Status__c != change.toStatus) {
                violations.put(change.index, violation(change.toStatus));
            }
        }
        return violations;
    }

    private static ShipmentStatusPolicy.Violation violation(String toStatus) {
        String message = OUT_FOR_DELIVERY.equals(toStatus)
            ? Label.eLogix_Delivery_Guard_Open_Attempt
            : DELIVERED.equals(toStatus) ? Label.eLogix_Delivery_Guard_Delivered : Label.eLogix_Delivery_Guard_Failed;
        return new ShipmentStatusPolicy.Violation(DELIVERY_REQUIRED, message);
    }

    private static Boolean isShipmentTrigger(System.TriggerOperation operation) {
        return Trigger.isExecuting &&
            Trigger.operationType == operation &&
            Trigger.new != null &&
            Trigger.new.getSObjectType() == Shipment__c.SObjectType;
    }
}
