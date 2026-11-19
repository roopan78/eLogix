/**
 * Input for TrackingService.recordEvents: one operational tracking event such as a location
 * update or hub arrival. Status events are not accepted here; they come only from status changes.
 */
public inherited sharing class TrackingEventRequest {
    @AuraEnabled
    public Id shipmentId { get; set; }
    /** A Tracking_Event__c.Event_Type__c value that is not a shipment status, for example Location Update. */
    @AuraEnabled
    public String eventType { get; set; }
    /** Defaults to now. */
    @AuraEnabled
    public Datetime eventTimestamp { get; set; }
    @AuraEnabled
    public String location { get; set; }
    @AuraEnabled
    public Decimal latitude { get; set; }
    @AuraEnabled
    public Decimal longitude { get; set; }
    /** A Tracking_Event__c.Source__c value. Defaults to Apex Service. */
    @AuraEnabled
    public String source { get; set; }
    @AuraEnabled
    public String remarks { get; set; }
    /** Optional identifier from the sending system. Makes replays idempotent through Event_Key__c. */
    @AuraEnabled
    public String externalEventId { get; set; }

    public TrackingEventRequest() {
    }

    public TrackingEventRequest(Id shipmentId, String eventType, String location) {
        this.shipmentId = shipmentId;
        this.eventType = eventType;
        this.location = location;
    }
}
