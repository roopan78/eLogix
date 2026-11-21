/**
 * Input to DeliveryService.recordProofs: the proof of delivery for a shipment's open attempt. Evidence
 * files are uploaded to the proof record it creates, before the delivery is confirmed.
 */
public inherited sharing class ProofOfDeliveryRequest {
    @AuraEnabled
    public Id shipmentId { get; set; }
    @AuraEnabled
    public String receiverName { get; set; }
    /** When the goods were received; defaults to now. */
    @AuraEnabled
    public Datetime receivedAt { get; set; }
    @AuraEnabled
    public String signatureReference { get; set; }
    @AuraEnabled
    public String deliveryNotes { get; set; }
    @AuraEnabled
    public Boolean hasException { get; set; }
    @AuraEnabled
    public String exceptionNotes { get; set; }

    public ProofOfDeliveryRequest() {
    }

    public ProofOfDeliveryRequest(Id shipmentId, String receiverName) {
        this.shipmentId = shipmentId;
        this.receiverName = receiverName;
    }
}
