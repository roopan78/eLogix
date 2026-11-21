/**
 * Output of FreightCalculationService.quote: the priced components for one FreightRequest, or the
 * reason it could not be priced. Components are rounded to 2 decimals (HALF_UP, decision Q15) and
 * are exactly what QuotationService writes to Quotation__c. Totals are never stored from Apex: the
 * Quotation__c formulas derive them, and FreightCalculationService.quotationTotals mirrors those
 * formulas for display and for tests.
 */
public inherited sharing class FreightBreakdown {
    public String key;
    public Boolean isPriced = false;
    public String errorCode;
    public String errorMessage;

    public Id rateCardId;
    /** Rate card base freight before the minimum-freight uplift. */
    public Decimal rateCardBaseFreight;
    /** Amount added so that base + weight + distance reaches Minimum_Freight__c (decision Q7). */
    public Decimal minimumUplift;
    /** Base freight including the uplift; stored in Quotation__c.Base_Freight__c. */
    public Decimal baseFreight;
    public Decimal weightCharge;
    public Decimal distanceCharge;
    public Decimal fuelSurcharge;
    public Decimal insuranceCharge;
    /** Tax rate in percent (12 means 12%), from the Default_Tax_Percent setting (decision Q16). */
    public Decimal taxPercent;

    /** Base + weight + distance + fuel + insurance: the freight components before lines, discount and tax. */
    public Decimal freightCharges() {
        return baseFreight + weightCharge + distanceCharge + fuelSurcharge + insuranceCharge;
    }

    public static FreightBreakdown failure(String key, String errorCode, String errorMessage) {
        FreightBreakdown breakdown = new FreightBreakdown();
        breakdown.key = key;
        breakdown.errorCode = errorCode;
        breakdown.errorMessage = errorMessage;
        return breakdown;
    }
}
