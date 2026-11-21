/**
 * One GPS position report from a provider (Phase 6). The vehicle is identified by its unique
 * Vehicle_Number__c; messageId is the provider's message id and makes every ping idempotent
 * (TrackingService event key EXT:GPSIntegration:{messageId}).
 */
public inherited sharing class GpsPing {
    public String messageId;
    public String vehicleNumber;
    public Decimal latitude;
    public Decimal longitude;
    public Datetime recordedAt;
    /** Optional place name from the provider; otherwise the location is shown as "lat, long". */
    public String location;

    public GpsPing() {
    }

    public GpsPing(String messageId, String vehicleNumber, Decimal latitude, Decimal longitude, Datetime recordedAt) {
        this.messageId = messageId;
        this.vehicleNumber = vehicleNumber;
        this.latitude = latitude;
        this.longitude = longitude;
        this.recordedAt = recordedAt;
    }
}
