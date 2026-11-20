/** Input to DeliveryService.recordFailures: why a shipment's open attempt failed. */
public inherited sharing class DeliveryFailureRequest {
    @AuraEnabled
    public Id shipmentId { get; set; }
    /** A Delivery__c.Failure_Reason__c value. */
    @AuraEnabled
    public String reason { get; set; }
    @AuraEnabled
    public String notes { get; set; }

    public DeliveryFailureRequest() {
    }

    public DeliveryFailureRequest(Id shipmentId, String reason) {
        this.shipmentId = shipmentId;
        this.reason = reason;
    }
}
