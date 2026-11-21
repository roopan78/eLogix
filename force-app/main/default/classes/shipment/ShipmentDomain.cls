/**
 * Shipment domain logic that runs in the before-trigger.
 *
 * Applies ShipmentStatusPolicy decisions to the records being saved: rejected changes get a field
 * error on Status__c, and allowed changes stamp Latest_Tracking_Timestamp__c. Single-record
 * invariants (weight, distance, dates, hold and cancellation reasons) are owned by validation
 * rules and are not repeated here.
 */
public with sharing class ShipmentDomain {
    private final ShipmentStatusPolicy policy;

    public ShipmentDomain() {
        this(new ShipmentStatusPolicy());
    }

    @TestVisible
    private ShipmentDomain(ShipmentStatusPolicy policy) {
        this.policy = policy;
    }

    public void validateNewShipments(List<Shipment__c> records) {
        apply(records, policy.evaluateCreation(records));
    }

    public void validateStatusChanges(List<Shipment__c> records, Map<Id, Shipment__c> oldById) {
        apply(records, policy.evaluateStatusChanges(records, oldById));
    }

    private static void apply(List<Shipment__c> records, List<ShipmentStatusPolicy.Decision> decisions) {
        Datetime now = System.now();
        for (ShipmentStatusPolicy.Decision decision : decisions) {
            Shipment__c record = records[decision.index];
            if (decision.isRejected()) {
                record.Status__c.addError(decision.message);
            } else if (decision.isAllowed()) {
                record.Latest_Tracking_Timestamp__c = now;
            }
        }
    }
}
