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
     * Without sharing on purpose. Duplicate detection must see every key that exists, whoever can
     * see the event, otherwise the unique index on Event_Key__c would reject the insert instead of
     * the service skipping it. Event_Key__c is also read-only for every role. Only the key strings
     * leave this class, never record data.
     */
    private without sharing class KeyLookup {
        public Set<String> existingKeys(Set<String> eventKeys) {
            Set<String> found = new Set<String>();
            for (Tracking_Event__c event : [SELECT Event_Key__c FROM Tracking_Event__c WHERE Event_Key__c IN :eventKeys WITH SYSTEM_MODE]) {
                found.add(event.Event_Key__c);
            }
            return found;
        }
    }
}
