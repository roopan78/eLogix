/**
 * Input to FleetAllocationService.allocate, reallocate and correctDispatchedAllocation: which vehicle
 * and driver should carry a shipment. The assignment window is always derived from the shipment
 * (decision Q3).
 */
public inherited sharing class AllocationRequest {
    @AuraEnabled
    public Id shipmentId { get; set; }
    @AuraEnabled
    public Id vehicleId { get; set; }
    @AuraEnabled
    public Id driverId { get; set; }
    @AuraEnabled
    public String remarks { get; set; }
    /** correctDispatchedAllocation only: why a dispatched allocation is being corrected. Required. */
    @AuraEnabled
    public String correctionReason { get; set; }

    public AllocationRequest() {
    }

    public AllocationRequest(Id shipmentId, Id vehicleId, Id driverId) {
        this.shipmentId = shipmentId;
        this.vehicleId = vehicleId;
        this.driverId = driverId;
    }
}
