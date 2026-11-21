/**
 * SOQL for Shipment_Request__c. User mode: a request the user cannot read is simply absent.
 */
public inherited sharing class ShipmentRequestSelector {
    /** Requests with everything pricing and quoting need, including route, customer and business unit. */
    public Map<Id, Shipment_Request__c> selectForQuotation(Set<Id> requestIds) {
        if (requestIds == null || requestIds.isEmpty()) {
            return new Map<Id, Shipment_Request__c>();
        }
        return new Map<Id, Shipment_Request__c>(
            [
                SELECT
                    Id,
                    Name,
                    Status__c,
                    Customer__c,
                    Customer__r.Is_Active_Customer__c,
                    Business_Unit__c,
                    Business_Unit__r.Region__c,
                    Route__c,
                    Route__r.Distance__c,
                    Total_Weight__c,
                    Declared_Value__c,
                    Requested_Vehicle_Type__c,
                    Requested_Pickup_Date__c
                FROM Shipment_Request__c
                WHERE Id IN :requestIds
                WITH USER_MODE
            ]
        );
    }

    /**
     * Current status of requests the running user can read, locked for update (follow-up A3). A
     * request the user cannot read is absent, and conversion treats it as not Approved.
     */
    public Map<Id, Shipment_Request__c> selectStatusForUpdate(Set<Id> requestIds) {
        if (requestIds == null || requestIds.isEmpty()) {
            return new Map<Id, Shipment_Request__c>();
        }
        return new Map<Id, Shipment_Request__c>(
            [SELECT Id, Status__c FROM Shipment_Request__c WHERE Id IN :requestIds WITH USER_MODE FOR UPDATE]
        );
    }
}
