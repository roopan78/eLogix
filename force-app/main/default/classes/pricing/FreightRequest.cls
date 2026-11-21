/**
 * Input to FreightCalculationService.quote: what is being moved, how far, and on which date.
 * Built by QuotationService from a shipment request; usable by any future caller (LWC, Flow).
 */
public inherited sharing class FreightRequest {
    /** Caller's correlation key, echoed on the breakdown (for example the shipment request Id). */
    public String key;
    /** A Rate_Card__c.Vehicle_Type__c value. Required. */
    public String vehicleType;
    /** Chargeable weight in kilograms. Must be greater than zero. */
    public Decimal weightKg;
    /** Route distance in kilometres. Must be greater than zero. */
    public Decimal distanceKm;
    /** Cargo value; the base for insurance (decision Q6). Blank means no insurance. */
    public Decimal declaredValue;
    /** The date the rate card must be effective on: the requested pickup date (decision Q9). Required. */
    public Date pricingDate;
    /** Used for rate card specificity (decision Q10). Optional. */
    public Id businessUnitId;
    /** The business unit's region, used for rate card specificity. Optional. */
    public String region;
}
