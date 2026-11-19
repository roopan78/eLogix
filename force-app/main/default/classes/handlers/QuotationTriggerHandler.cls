/**
 * Routes Quotation__c trigger contexts to QuotationDomain. No business rules here.
 *
 * before insert / update: validate new quotations; lock, transitions, approval stamp, threshold.
 * after insert / update:  move the shipment request status (QuotationDomain reads the trigger itself).
 *
 * Saves without a relevant change (for example a roll-up recalculation on a Draft quotation) cost
 * no SOQL and no DML.
 */
public with sharing class QuotationTriggerHandler extends TriggerHandler {
    public QuotationTriggerHandler() {
        super();
    }

    @TestVisible
    private QuotationTriggerHandler(System.TriggerOperation operation, List<SObject> newList, Map<Id, SObject> oldMap) {
        super(operation, newList, oldMap);
    }

    protected override void beforeInsert() {
        new QuotationDomain().validateNew((List<Quotation__c>) newList);
    }

    protected override void beforeUpdate() {
        new QuotationDomain().validateChanges((List<Quotation__c>) newList, (Map<Id, Quotation__c>) oldMap);
    }

    protected override void afterInsert() {
        new QuotationDomain().syncRequestStatuses();
    }

    protected override void afterUpdate() {
        new QuotationDomain().syncRequestStatuses();
    }
}
