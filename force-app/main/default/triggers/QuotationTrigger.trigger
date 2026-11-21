/**
 * The single Quotation__c trigger. All logic lives in QuotationTriggerHandler and QuotationDomain.
 */
trigger QuotationTrigger on Quotation__c(before insert, before update, after insert, after update) {
    new QuotationTriggerHandler().run();
}
