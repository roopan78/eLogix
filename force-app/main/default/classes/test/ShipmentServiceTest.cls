@IsTest
private class ShipmentServiceTest {
    private static final String OPS = 'Service Ops Tester';
    private static final String SALES = 'Service Sales Tester';

    @TestSetup
    static void setup() {
        Business_Unit__c businessUnit = TestDataFactory.createBusinessUnit('BU-SVC');
        TestDataFactory.createCustomer('CUST-SVC', businessUnit.Id);
        TestDataFactory.createUser(OPS, TestDataFactory.OPERATIONS);
        TestDataFactory.createUser(SALES, TestDataFactory.SALES);
    }

    private static List<Shipment__c> drafts(Integer count) {
        Account customer = [SELECT Id, Business_Unit__c FROM Account WHERE Customer_Code__c = 'CUST-SVC'];
        List<Shipment__c> records = TestDataFactory.buildShipments(count, customer.Id, customer.Business_Unit__c, 'Draft');
        insert records;
        return records;
    }

    @IsTest
    static void changeStatusReportsResultsPerRequest() {
        System.runAs(TestDataFactory.getUser(OPS)) {
            List<Shipment__c> records = drafts(2);

            ServiceResult result = new ShipmentService()
                .changeStatus(
                    new List<ShipmentService.StatusChangeRequest>{
                        new ShipmentService.StatusChangeRequest(records[0].Id, 'Requested', null),
                        new ShipmentService.StatusChangeRequest(records[1].Id, 'Closed', null)
                    }
                );

            Assert.isFalse(result.isSuccess);
            Assert.areEqual(new List<Id>{ records[0].Id }, result.recordIds);
            ServiceResult.ServiceError error = result.errorsFor(1)[0];
            Assert.areEqual('FIELD_CUSTOM_VALIDATION_EXCEPTION', error.code);
            Assert.areEqual(String.format(Label.eLogix_Status_Transition_Not_Allowed, new List<Object>{ 'Draft', 'Closed' }), error.message);
            Assert.areEqual(records[1].Id, error.recordId);
            Assert.areEqual('Requested', [SELECT Status__c FROM Shipment__c WHERE Id = :records[0].Id].Status__c);
        }
    }

    @IsTest
    static void reasonFillsTheMatchingReasonField() {
        System.runAs(TestDataFactory.getUser(OPS)) {
            List<Shipment__c> records = drafts(1);

            ServiceResult result = new ShipmentService()
                .changeStatus(new List<ShipmentService.StatusChangeRequest>{ new ShipmentService.StatusChangeRequest(records[0].Id, 'Cancelled', 'Booked twice.') });

            Assert.isTrue(result.isSuccess, String.valueOf(result.errors));
            Shipment__c saved = [SELECT Status__c, Cancellation_Reason__c, Hold_Reason__c FROM Shipment__c WHERE Id = :records[0].Id];
            Assert.areEqual('Cancelled', saved.Status__c);
            Assert.areEqual('Booked twice.', saved.Cancellation_Reason__c);
            Assert.isNull(saved.Hold_Reason__c);
            Assert.areEqual('Booked twice.', [SELECT Remarks__c FROM Tracking_Event__c WHERE Shipment__c = :saved.Id AND Event_Type__c = 'Cancelled'].Remarks__c);
        }
    }

    @IsTest
    static void holdReasonFillsHoldReason() {
        System.runAs(TestDataFactory.getUser(OPS)) {
            List<Shipment__c> records = drafts(1);
            insert TestDataFactory.buildItems(records);
            TestDataFactory.advance(records, new List<String>{ 'Requested', 'Quoted', 'Confirmed' });

            ShipmentService.StatusChangeRequest request = new ShipmentService.StatusChangeRequest();
            request.shipmentId = records[0].Id;
            request.targetStatus = 'On Hold';
            request.reason = 'Consignee premises closed for Pongal.';
            ServiceResult result = new ShipmentService().changeStatus(new List<ShipmentService.StatusChangeRequest>{ request });

            Assert.isTrue(result.isSuccess, String.valueOf(result.errors));
            Shipment__c saved = [SELECT Status__c, Hold_Reason__c, Cancellation_Reason__c FROM Shipment__c WHERE Id = :records[0].Id];
            Assert.areEqual('On Hold', saved.Status__c);
            Assert.areEqual('Consignee premises closed for Pongal.', saved.Hold_Reason__c);
            Assert.isNull(saved.Cancellation_Reason__c);
        }
    }

    @IsTest
    static void missingReasonIsReportedByTheValidationRule() {
        System.runAs(TestDataFactory.getUser(OPS)) {
            List<Shipment__c> records = drafts(1);

            ServiceResult result = new ShipmentService()
                .changeStatus(new List<ShipmentService.StatusChangeRequest>{ new ShipmentService.StatusChangeRequest(records[0].Id, 'Cancelled', null) });

            Assert.isFalse(result.isSuccess);
            Assert.areEqual('FIELD_CUSTOM_VALIDATION_EXCEPTION', result.errors[0].code);
        }
    }

    @IsTest
    static void invalidRequestsAreRejectedWithoutDml() {
        System.runAs(TestDataFactory.getUser(OPS)) {
            Account customer = [SELECT Id FROM Account WHERE Customer_Code__c = 'CUST-SVC'];
            Integer dmlBefore = Limits.getDmlStatements();

            ServiceResult result = new ShipmentService()
                .changeStatus(
                    new List<ShipmentService.StatusChangeRequest>{
                        new ShipmentService.StatusChangeRequest(null, 'Requested', null),
                        new ShipmentService.StatusChangeRequest(TestDataFactory.fakeId(Shipment__c.SObjectType, 1), ' ', null),
                        new ShipmentService.StatusChangeRequest(customer.Id, 'Requested', null),
                        null
                    }
                );

            Assert.areEqual(4, result.errors.size());
            for (ServiceResult.ServiceError error : result.errors) {
                Assert.areEqual(ShipmentService.REQUEST_INVALID, error.code);
            }
            Assert.areEqual(dmlBefore, Limits.getDmlStatements());
        }
    }

    @IsTest
    static void userWithoutEditAccessCannotChangeStatus() {
        Shipment__c shipment;
        System.runAs(TestDataFactory.getUser(OPS)) {
            shipment = drafts(1)[0];
        }
        System.runAs(TestDataFactory.getUser(SALES)) {
            ServiceResult result = new ShipmentService()
                .changeStatus(new List<ShipmentService.StatusChangeRequest>{ new ShipmentService.StatusChangeRequest(shipment.Id, 'Requested', null) });

            Assert.isFalse(result.isSuccess);
            Assert.isTrue(result.recordIds.isEmpty());
        }
        Assert.areEqual('Draft', [SELECT Status__c FROM Shipment__c WHERE Id = :shipment.Id].Status__c);
    }

    @IsTest
    static void emptyInputIsANoOp() {
        Assert.isTrue(new ShipmentService().changeStatus(null).isSuccess);
        Assert.isTrue(new ShipmentService().changeStatus(new List<ShipmentService.StatusChangeRequest>()).isSuccess);
    }
}
