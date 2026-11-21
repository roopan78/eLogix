/**
 * SOQL for Tracking_Event__c.
 */
public inherited sharing class TrackingEventSelector {
    /** Which of the given event keys already exist. One query for the whole set; none when the set is empty. */
    public Set<String> selectExistingKeys(Set<String> eventKeys) {
        if (eventKeys == null || eventKeys.isEmpty()) {
            return new Set<String>();
        }
        return new KeyLookup().existingKeys(eventKeys);
    }

    /**
     * Number of status events (To_Status__c set) of each shipment, for the sequence part of the status
     * event key (Phase 5). One aggregate query for the whole set; none when the set is empty. Shipments
     * without status events are absent from the map.
     */
    public Map<Id, Integer> countStatusEvents(Set<Id> shipmentIds) {
        if (shipmentIds == null || shipmentIds.isEmpty()) {
            return new Map<Id, Integer>();
        }
        return new KeyLookup().statusEventCounts(shipmentIds);
    }

    /**
     * Without sharing on purpose. Duplicate detection must see every key that exists, and the sequence
     * every status event, whoever can see the event, otherwise the unique index on Event_Key__c would
     * reject the insert instead of the service skipping it. Event_Key__c is also read-only for every
     * role. Only key strings and counts leave this class, never record data.
     */
    private without sharing class KeyLookup {
        public Set<String> existingKeys(Set<String> eventKeys) {
            Set<String> found = new Set<String>();
            for (Tracking_Event__c event : [SELECT Event_Key__c FROM Tracking_Event__c WHERE Event_Key__c IN :eventKeys WITH SYSTEM_MODE]) {
                found.add(event.Event_Key__c);
            }
            return found;
        }

        public Map<Id, Integer> statusEventCounts(Set<Id> shipmentIds) {
            Map<Id, Integer> counts = new Map<Id, Integer>();
            for (AggregateResult row : [
                SELECT Shipment__c shipmentId, COUNT(Id) events
                FROM Tracking_Event__c
                WHERE Shipment__c IN :shipmentIds AND To_Status__c != NULL
                WITH SYSTEM_MODE
                GROUP BY Shipment__c
            ]) {
                counts.put((Id) row.get('shipmentId'), (Integer) row.get('events'));
            }
            return counts;
        }
    }
}
