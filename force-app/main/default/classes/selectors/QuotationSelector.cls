/**
 * SOQL for Quotation__c and the quotation-related reads the quotation services need.
 */
public inherited sharing class QuotationSelector {
    /**
     * Quotations the running user can read (user mode), locked for update, with the request, route,
     * customer and business-unit fields that recalculation and conversion need.
     */
    public Map<Id, Quotation__c> selectForUpdate(Set<Id> quotationIds) {
        if (quotationIds == null || quotationIds.isEmpty()) {
            return new Map<Id, Quotation__c>();
        }
        return new Map<Id, Quotation__c>(
            [
                SELECT
                    Id,
                    Name,
                    OwnerId,
                    Status__c,
                    Shipment_Request__c,
                    Rate_Card__c,
                    Base_Freight__c,
                    Weight_Charge__c,
                    Distance_Charge__c,
                    Fuel_Surcharge__c,
                    Insurance_Charge__c,
                    Discount__c,
                    Tax_Percent__c,
                    Line_Total__c,
                    Taxable_Line_Total__c,
                    Total_Amount__c,
                    Valid_Until__c,
                    Is_Expired__c,
                    Approved_By__c,
                    Notes__c,
                    Shipment_Request__r.Name,
                    Shipment_Request__r.Status__c,
                    Shipment_Request__r.Customer__c,
                    Shipment_Request__r.Customer__r.Is_Active_Customer__c,
                    Shipment_Request__r.Business_Unit__c,
                    Shipment_Request__r.Business_Unit__r.Region__c,
                    Shipment_Request__r.Route__c,
                    Shipment_Request__r.Route__r.Distance__c,
                    Shipment_Request__r.Route__r.Origin__c,
                    Shipment_Request__r.Route__r.Destination__c,
                    Shipment_Request__r.Total_Weight__c,
                    Shipment_Request__r.Declared_Value__c,
                    Shipment_Request__r.Requested_Vehicle_Type__c,
                    Shipment_Request__r.Requested_Pickup_Date__c,
                    Shipment_Request__r.Expected_Delivery_Date__c,
                    Shipment_Request__r.Priority__c,
                    Shipment_Request__r.Special_Instructions__c
                FROM Quotation__c
                WHERE Id IN :quotationIds
                WITH USER_MODE
                FOR UPDATE
            ]
        );
    }

    /**
     * Sum of Discount-type lines per quotation (zero or negative). System mode on purpose: the
     * discount threshold is an enforcement check and must see every line whatever the running
     * user's field access; only aggregates leave this method. Sharing follows the caller.
     */
    public Map<Id, Decimal> sumDiscountLines(Set<Id> quotationIds) {
        Map<Id, Decimal> totals = new Map<Id, Decimal>();
        if (quotationIds == null || quotationIds.isEmpty()) {
            return totals;
        }
        for (AggregateResult row : [
            SELECT Quotation__c quotationId, SUM(Amount__c) total
            FROM Quotation_Line__c
            WHERE Quotation__c IN :quotationIds AND Charge_Type__c = 'Discount'
            WITH SYSTEM_MODE
            GROUP BY Quotation__c
        ]) {
            totals.put((Id) row.get('quotationId'), (Decimal) row.get('total'));
        }
        return totals;
    }

    /**
     * Quotations that already have a shipment. System mode on purpose: the one-shipment-per-quotation
     * check (decision Q20) must not miss a shipment because of field access; only Ids leave this method.
     */
    public Set<Id> selectConvertedQuotationIds(Set<Id> quotationIds) {
        Set<Id> converted = new Set<Id>();
        if (quotationIds == null || quotationIds.isEmpty()) {
            return converted;
        }
        for (Shipment__c shipment : [SELECT Quotation__c FROM Shipment__c WHERE Quotation__c IN :quotationIds WITH SYSTEM_MODE]) {
            converted.add(shipment.Quotation__c);
        }
        return converted;
    }
}
