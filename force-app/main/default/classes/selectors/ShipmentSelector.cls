/**
 * SOQL for Shipment__c. Queries run in user mode: sharing, CRUD and FLS of the running user apply.
 */
public inherited sharing virtual class ShipmentSelector {
    /**
     * Shipments the running user can read, locked for update, with their tracking summary. A
     * shipment the user cannot see is simply absent from the map.
     */
    public virtual Map<Id, Shipment__c> selectTrackingSummaryForUpdate(Set<Id> shipmentIds) {
        if (shipmentIds == null || shipmentIds.isEmpty()) {
            return new Map<Id, Shipment__c>();
        }
        return new Map<Id, Shipment__c>(
            [
                SELECT Id, Status__c, Latest_Location__c, Latest_Tracking_Timestamp__c
                FROM Shipment__c
                WHERE Id IN :shipmentIds
                WITH USER_MODE
                FOR UPDATE
            ]
        );
    }
}
