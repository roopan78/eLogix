/**
 * CLAUDE.md section 5: a shipment must have at least one item before confirmation.
 *
 * Applies on entry to Confirmed from any status, including On Hold -> Confirmed, because items can
 * be removed while a shipment is on hold. Reads the Item_Count__c roll-up from the record in the
 * trigger, so it needs no SOQL.
 */
public with sharing class ShipmentItemsRequiredGuard implements ShipmentStatusGuard {
    public static final String ITEMS_REQUIRED = 'ITEMS_REQUIRED';
    @TestVisible
    private static final String CONFIRMED = 'Confirmed';

    public Set<String> targetStatuses() {
        return new Set<String>{ CONFIRMED };
    }

    public Map<Integer, ShipmentStatusPolicy.Violation> check(List<ShipmentStatusPolicy.StatusChange> changes) {
        Map<Integer, ShipmentStatusPolicy.Violation> violations = new Map<Integer, ShipmentStatusPolicy.Violation>();
        for (ShipmentStatusPolicy.StatusChange change : changes) {
            Decimal itemCount = change.record == null ? null : change.record.Item_Count__c;
            if (itemCount == null || itemCount < 1) {
                violations.put(change.index, new ShipmentStatusPolicy.Violation(ITEMS_REQUIRED, Label.eLogix_Shipment_Items_Required));
            }
        }
        return violations;
    }
}
