/**
 * Phase 7: QuotationConsoleController delegates every action to QuotationService, so role and
 * permission checks are the service's. Denials reach the component as AuraHandledException with the
 * service's user message.
 */
@IsTest
private class QuotationConsoleControllerTest {
    private static final String SALES = 'Quote Console Sales Tester';
    private static final String OPS = 'Quote Console Ops Tester';
    private static final String MANAGER = 'Quote Console Manager Tester';

    @TestSetup
    static void setup() {
        Business_Unit__c businessUnit = TestDataFactory.createBusinessUnit('BU-QCC');
        TestDataFactory.createCustomer('CUST-QCC', businessUnit.Id);
        TestDataFactory.createRoute('RT-QCC', 350);
        insert TestDataFactory.buildRateCard('RC-QCC-LCV', 'LCV');
        TestDataFactory.createUser(SALES, TestDataFactory.SALES);
        TestDataFactory.createUser(OPS, TestDataFactory.OPERATIONS);
        TestDataFactory.createUser(MANAGER, TestDataFactory.LOGISTICS_MANAGER);
    }

    /** As the running user: one Submitted shipment request. */
    private static Shipment_Request__c submittedRequest() {
        Account customer = [SELECT Id, Business_Unit__c FROM Account WHERE Customer_Code__c = 'CUST-QCC'];
        Route__c route = [SELECT Id FROM Route__c WHERE Route_Code__c = 'RT-QCC'];
        Shipment_Request__c request = TestDataFactory.buildShipmentRequest(customer.Id, customer.Business_Unit__c, route.Id, 'Submitted');
        insert request;
        return request;
    }

    private static String statusOf(Id quotationId) {
        return [SELECT Status__c FROM Quotation__c WHERE Id = :quotationId].Status__c;
    }

    @IsTest
    static void salesQuotesRecalculatesAndSubmitsWithinThreshold() {
        System.runAs(TestDataFactory.getUser(SALES)) {
            ServiceResult created = QuotationConsoleController.createFromRequest(submittedRequest().Id);
            Assert.isTrue(created.isSuccess, String.valueOf(created.errors));
            Id quotationId = created.recordIds[0];
            Assert.areEqual(Quotation__c.SObjectType, quotationId.getSObjectType());
            Assert.areEqual([SELECT COUNT() FROM Quotation_Line__c WHERE Quotation__c = :quotationId], QuotationConsoleController.getLines(quotationId).size());

            Assert.isTrue(QuotationConsoleController.recalculate(quotationId).isSuccess);
            ServiceResult submitted = QuotationConsoleController.submitForApproval(quotationId);
            Assert.isTrue(submitted.isSuccess, String.valueOf(submitted.errors));
            Assert.areEqual('Approved', statusOf(quotationId), 'No discount: approved automatically.');
        }
    }

    @IsTest
    static void usersWithoutCreateAccessAreDenied() {
        Shipment_Request__c request;
        System.runAs(TestDataFactory.getUser(SALES)) {
            request = submittedRequest();
        }
        System.runAs(TestDataFactory.getUser(OPS)) {
            try {
                QuotationConsoleController.createFromRequest(request.Id);
                Assert.fail('Operations Executives cannot create quotations.');
            } catch (AuraHandledException e) {
                Assert.areEqual(Label.eLogix_Access_Denied, e.getMessage());
            }
        }
        Assert.areEqual(0, [SELECT COUNT() FROM Quotation__c]);
    }

    @IsTest
    static void approvalNeedsThePermissionAndManagersCanDecide() {
        Id approveId;
        Id rejectId;
        System.runAs(TestDataFactory.getUser(SALES)) {
            approveId = QuotationConsoleController.createFromRequest(submittedRequest().Id).recordIds[0];
            rejectId = QuotationConsoleController.createFromRequest(submittedRequest().Id).recordIds[0];
            update new List<Quotation__c>{ new Quotation__c(Id = approveId, Discount__c = 2000), new Quotation__c(Id = rejectId, Discount__c = 2000) };
            QuotationConsoleController.submitForApproval(approveId);
            QuotationConsoleController.submitForApproval(rejectId);
            Assert.areEqual('Pending Approval', statusOf(approveId));
            try {
                QuotationConsoleController.approve(approveId);
                Assert.fail('Sales Executives cannot approve.');
            } catch (AuraHandledException e) {
                Assert.areEqual(Label.eLogix_Access_Denied, e.getMessage());
            }
            Assert.areEqual('Pending Approval', statusOf(approveId));
        }
        System.runAs(TestDataFactory.getUser(MANAGER)) {
            Assert.isTrue(QuotationConsoleController.approve(approveId).isSuccess);
            ServiceResult rejected = QuotationConsoleController.reject(rejectId, 'Discount too deep for this lane.');
            Assert.isTrue(rejected.isSuccess, String.valueOf(rejected.errors));

            // Conversion rules stay in the service: an approved quotation the customer has not accepted is refused per record.
            ServiceResult converted = QuotationConsoleController.convertToShipment(approveId);
            Assert.isFalse(converted.isSuccess);
            Assert.areEqual(QuotationService.QUOTATION_NOT_CONVERTIBLE, converted.errorsFor(0)[0].code);
        }
        Assert.areEqual(0, [SELECT COUNT() FROM Shipment__c]);
        Assert.areEqual('Approved', statusOf(approveId));
        Assert.areEqual('Draft', statusOf(rejectId));
    }
}
