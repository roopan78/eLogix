/**
 * Phase 7 LWC controller for quotationBuilder. Thin: every action delegates to QuotationService, which
 * owns pricing (FreightCalculationService), the approval threshold, the approval permission and
 * conversion. The quotation record itself is read by the component through Lightning Data Service.
 */
public with sharing class QuotationConsoleController {
    private static final String LOG_CONTEXT = 'QuotationConsoleController';

    /** The quotation's charge lines, in display order, as the user may read them. */
    @AuraEnabled(cacheable=true)
    public static List<Quotation_Line__c> getLines(Id quotationId) {
        try {
            return [
                SELECT Id, Name, Charge_Type__c, Description__c, Quantity__c, Unit_Price__c, Amount__c, Is_Taxable__c, Sort_Order__c
                FROM Quotation_Line__c
                WHERE Quotation__c = :quotationId
                WITH USER_MODE
                ORDER BY Sort_Order__c NULLS LAST, Name
            ];
        } catch (Exception e) {
            throw toAura(e);
        }
    }

    @AuraEnabled
    public static ServiceResult createFromRequest(Id shipmentRequestId) {
        try {
            return new QuotationService().createFromRequests(new List<Id>{ shipmentRequestId });
        } catch (Exception e) {
            throw toAura(e);
        }
    }

    @AuraEnabled
    public static ServiceResult recalculate(Id quotationId) {
        try {
            return new QuotationService().recalculate(new List<Id>{ quotationId });
        } catch (Exception e) {
            throw toAura(e);
        }
    }

    @AuraEnabled
    public static ServiceResult submitForApproval(Id quotationId) {
        try {
            return new QuotationService().submitForApproval(new List<Id>{ quotationId });
        } catch (Exception e) {
            throw toAura(e);
        }
    }

    @AuraEnabled
    public static ServiceResult approve(Id quotationId) {
        try {
            return new QuotationService().approve(new List<Id>{ quotationId });
        } catch (Exception e) {
            throw toAura(e);
        }
    }

    @AuraEnabled
    public static ServiceResult reject(Id quotationId, String reason) {
        try {
            return new QuotationService().reject(new List<Id>{ quotationId }, reason);
        } catch (Exception e) {
            throw toAura(e);
        }
    }

    @AuraEnabled
    public static ServiceResult convertToShipment(Id quotationId) {
        try {
            return new QuotationService().convertToShipment(new List<Id>{ quotationId });
        } catch (Exception e) {
            throw toAura(e);
        }
    }

    private static AuraHandledException toAura(Exception e) {
        String message = ExceptionHandler.toUserMessage(e, LOG_CONTEXT);
        AuraHandledException error = new AuraHandledException(message);
        error.setMessage(message);
        return error;
    }
}
