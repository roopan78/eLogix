/**
 * QuotationService.convertToShipment (decisions Q1, Q4, Q20) and its integration with the Phase 2
 * shipment core: the new shipment starts as Quoted through ShipmentStatusPolicy and gets its
 * Created tracking event from TrackingService, with no Phase 2 code change.
 */
@IsTest
private class QuotationConversionTest {
    private static final String SALES = 'Convert Sales Tester';
    private static final String MANAGER = 'Convert Manager Tester';
    private static final String MIGRATION = 'Convert Migration Tester';

    @TestSetup
    static void setup() {
        Business_Unit__c businessUnit = TestDataFactory.createBusinessUnit('BU-QC');
        TestDataFactory.createCustomer('CUST-QC', businessUnit.Id);
        TestDataFactory.createRoute('RT-QC', 350);
        insert TestDataFactory.buildRateCard('RC-QC-LCV', 'LCV');
        TestDataFactory.createUser(SALES, TestDataFactory.SALES);
        TestDataFactory.createUser(MANAGER, TestDataFactory.LOGISTICS_MANAGER);
        TestDataFactory.createUser(MIGRATION, new List<String>{ TestDataFactory.SALES, TestDataFactory.DATA_MIGRATION });
    }

    /** As the running user: requests quoted, approved automatically (no discount), sent and accepted. */
    private static List<Id> acceptedQuotations(Integer count) {
        Account customer = [SELECT Id, Business_Unit__c FROM Account WHERE Customer_Code__c = 'CUST-QC'];
        Route__c route = [SELECT Id FROM Route__c WHERE Route_Code__c = 'RT-QC'];
        List<Shipment_Request__c> requests = TestDataFactory.buildShipmentRequests(count, customer.Id, customer.Business_Unit__c, route.Id, 'Submitted');
        insert requests;
        QuotationService service = new QuotationService();
        ServiceResult created = service.createFromRequests(TestDataFactory.idsOf(requests));
        Assert.isTrue(created.isSuccess, String.valueOf(created.errors));
        Assert.isTrue(service.submitForApproval(created.recordIds).isSuccess);
        for (String status : new List<String>{ 'Sent', 'Accepted' }) {
            List<Quotation__c> moves = new List<Quotation__c>();
            for (Id quotationId : created.recordIds) {
                moves.add(new Quotation__c(Id = quotationId, Status__c = status));
            }
            update moves;
        }
        return created.recordIds;
    }

    private static ServiceResult convertAs(String persona, List<Id> quotationIds) {
        ServiceResult result;
        System.runAs(TestDataFactory.getUser(persona)) {
            result = new QuotationService().convertToShipment(quotationIds);
        }
        return result;
    }

    @IsTest
    static void convertsAnAcceptedQuotationIntoAQuotedShipment() {
        Id quotationId;
        System.runAs(TestDataFactory.getUser(SALES)) {
            quotationId = acceptedQuotations(1)[0];
        }

        ServiceResult result = convertAs(MANAGER, new List<Id>{ quotationId });

        Assert.isTrue(result.isSuccess, String.valueOf(result.errors));
        Shipment__c shipment = [
            SELECT Status__c, Freight_Amount__c, Origin__c, Destination__c, Distance__c, Weight__c, Pickup_Date__c,
                Customer__c, Business_Unit__c, Route__c, Shipment_Request__c, Quotation__c, Quotation__r.Total_Amount__c,
                Shipment_Request__r.Status__c, Shipment_Request__r.Requested_Pickup_Date__c
            FROM Shipment__c
            WHERE Id = :result.recordIds[0]
        ];
        Assert.areEqual('Quoted', shipment.Status__c, 'Allowed initial status for a shipment from an accepted quotation.');
        Assert.areEqual(10914.40, shipment.Freight_Amount__c);
        Assert.areEqual(shipment.Quotation__r.Total_Amount__c, shipment.Freight_Amount__c);
        Assert.areEqual(quotationId, shipment.Quotation__c);
        Assert.areEqual('Chennai', shipment.Origin__c, 'The lane comes from the route that priced the quotation.');
        Assert.areEqual('Bangalore', shipment.Destination__c);
        Assert.areEqual(350, shipment.Distance__c);
        Assert.areEqual(500, shipment.Weight__c);
        Assert.areEqual(shipment.Shipment_Request__r.Requested_Pickup_Date__c, shipment.Pickup_Date__c);
        Assert.areEqual('Converted', shipment.Shipment_Request__r.Status__c);
        Tracking_Event__c created = [SELECT Event_Type__c, To_Status__c FROM Tracking_Event__c WHERE Shipment__c = :shipment.Id];
        Assert.areEqual('Created', created.Event_Type__c, 'Phase 2 tracking runs unchanged.');
        Assert.areEqual('Quoted', created.To_Status__c);
    }

    @IsTest
    static void aQuotationConvertsOnlyOnce() {
        Id quotationId;
        System.runAs(TestDataFactory.getUser(SALES)) {
            quotationId = acceptedQuotations(1)[0];
        }
        Assert.isTrue(convertAs(MANAGER, new List<Id>{ quotationId }).isSuccess);

        ServiceResult again = convertAs(MANAGER, new List<Id>{ quotationId });

        Assert.areEqual(QuotationService.QUOTATION_ALREADY_CONVERTED, again.errors[0].code);
        Assert.areEqual(1, [SELECT COUNT() FROM Shipment__c WHERE Quotation__c = :quotationId]);
    }

    @IsTest
    static void duplicateIdsInOneCallConvertOnce() {
        Id quotationId;
        System.runAs(TestDataFactory.getUser(SALES)) {
            quotationId = acceptedQuotations(1)[0];
        }

        ServiceResult result = convertAs(MANAGER, new List<Id>{ quotationId, quotationId });

        Assert.areEqual(1, result.recordIds.size());
        Assert.areEqual(QuotationService.QUOTATION_ALREADY_CONVERTED, result.errorsFor(1)[0].code);
        Assert.areEqual(1, [SELECT COUNT() FROM Shipment__c]);
    }

    /**
     * Only Accepted quotations convert. An accepted quotation can expire only with the passage of
     * time: since A4 its validity date is locked after Draft, so it cannot be back-dated (or extended)
     * to change the outcome. The expiry branch of convertToShipment therefore guards real elapsed
     * time, which a single Apex test cannot produce.
     */
    @IsTest
    static void onlyAcceptedValidQuotationsConvert() {
        Id sentId;
        System.runAs(TestDataFactory.getUser(SALES)) {
            Id acceptedId = acceptedQuotations(1)[0];
            Database.SaveResult backdate = Database.update(new Quotation__c(Id = acceptedId, Valid_Until__c = Date.today().addDays(-1)), false);
            Assert.areEqual(Label.eLogix_Quotation_Locked, backdate.getErrors()[0].getMessage(), 'Validity cannot be manipulated after Draft (A4).');

            Account customer = [SELECT Id, Business_Unit__c FROM Account WHERE Customer_Code__c = 'CUST-QC'];
            Shipment_Request__c request = TestDataFactory.buildShipmentRequest(
                customer.Id,
                customer.Business_Unit__c,
                [SELECT Id FROM Route__c WHERE Route_Code__c = 'RT-QC'].Id,
                'Submitted'
            );
            insert request;
            sentId = new QuotationService().createFromRequests(new List<Id>{ request.Id }).recordIds[0];
            new QuotationService().submitForApproval(new List<Id>{ sentId });
            update new Quotation__c(Id = sentId, Status__c = 'Sent');
        }

        ServiceResult result = convertAs(MANAGER, new List<Id>{ sentId });

        Assert.areEqual(QuotationService.QUOTATION_NOT_CONVERTIBLE, result.errorsFor(0)[0].code, 'Sent, not yet accepted.');
        Assert.areEqual(0, [SELECT COUNT() FROM Shipment__c]);
    }

    @IsTest
    static void usersWhoCannotCreateShipmentsAreDenied() {
        System.runAs(TestDataFactory.getUser(SALES)) {
            Id quotationId = acceptedQuotations(1)[0];
            try {
                new QuotationService().convertToShipment(new List<Id>{ quotationId });
                Assert.fail('Sales Executives have read-only shipment access.');
            } catch (AuthorizationException e) {
                Assert.areEqual(AuthorizationException.ACCESS_DENIED, e.code);
            }
        }
        Assert.areEqual(0, [SELECT COUNT() FROM Shipment__c]);
    }

    /**
     * Per-record failure handling: the legacy request breaks a validation rule (loaded under the
     * validation bypass after acceptance), so its move to Converted fails for the manager. That
     * shipment is removed again in the same transaction; the other quotation converts normally.
     */
    @IsTest
    static void aFailedRequestUpdateRemovesOnlyItsOwnShipment() {
        Id legacyQuotationId;
        System.runAs(TestDataFactory.getUser(MIGRATION)) {
            legacyQuotationId = acceptedQuotations(1)[0];
            Shipment_Request__c request = [SELECT Id, Origin__c FROM Shipment_Request__c WHERE Id IN (SELECT Shipment_Request__c FROM Quotation__c WHERE Id = :legacyQuotationId)];
            request.Destination__c = request.Origin__c; // breaks SR_Origin_Differs_From_Destination
            update request;
        }
        Id validQuotationId;
        System.runAs(TestDataFactory.getUser(SALES)) {
            validQuotationId = acceptedQuotations(1)[0];
        }

        ServiceResult result = convertAs(MANAGER, new List<Id>{ legacyQuotationId, validQuotationId });

        Assert.areEqual(1, result.recordIds.size());
        Assert.areEqual('FIELD_CUSTOM_VALIDATION_EXCEPTION', result.errorsFor(0)[0].code);
        Assert.isTrue(result.errorsFor(1).isEmpty(), String.valueOf(result.errors));
        Assert.areEqual(0, [SELECT COUNT() FROM Shipment__c WHERE Quotation__c = :legacyQuotationId], 'The orphan shipment was removed.');
        Assert.areEqual(1, [SELECT COUNT() FROM Shipment__c WHERE Quotation__c = :validQuotationId]);
        Assert.areEqual(1, [SELECT COUNT() FROM Tracking_Event__c], 'Only the surviving shipment keeps its Created event.');
        Assert.areEqual(
            'Approved',
            [SELECT Shipment_Request__r.Status__c FROM Quotation__c WHERE Id = :legacyQuotationId].Shipment_Request__r.Status__c
        );
    }

    @IsTest
    static void twoHundredQuotationsConvertInBulk() {
        List<Id> quotationIds;
        System.runAs(TestDataFactory.getUser(SALES)) {
            quotationIds = acceptedQuotations(200);
        }

        ServiceResult result;
        Integer queries;
        Integer dml;
        System.runAs(TestDataFactory.getUser(MANAGER)) {
            Test.startTest();
            Integer queriesBefore = Limits.getQueries();
            Integer dmlBefore = Limits.getDmlStatements();
            result = new QuotationService().convertToShipment(quotationIds);
            queries = Limits.getQueries() - queriesBefore;
            dml = Limits.getDmlStatements() - dmlBefore;
            Test.stopTest();
        }

        Assert.isTrue(result.isSuccess, String.valueOf(result.errors));
        Assert.areEqual(200, result.recordIds.size());
        Assert.areEqual(5, queries, 'Quotations, existing shipments, the request lock (A3), and the two tracking-key queries in ShipmentTrigger (Phase 5 sequence).');
        Assert.areEqual(3, dml, 'Shipment insert, tracking insert, request update.');
        Assert.areEqual(200, [SELECT COUNT() FROM Shipment__c WHERE Status__c = 'Quoted']);
        Assert.areEqual(200, [SELECT COUNT() FROM Tracking_Event__c WHERE Event_Type__c = 'Created']);
        Assert.areEqual(200, [SELECT COUNT() FROM Shipment_Request__c WHERE Status__c = 'Converted']);
    }

    /**
     * A3: the request's status is re-read under a row lock before conversion. A request that changed
     * after acceptance (here Cancelled) is reported and not overwritten with Converted; the other
     * quotation in the same call converts normally. (A true concurrent change cannot be produced in a
     * single-threaded Apex test; this proves the check runs on the locked, current status.)
     */
    @IsTest
    static void aRequestChangedBeforeConversionIsNotOverwritten() {
        List<Id> quotationIds;
        System.runAs(TestDataFactory.getUser(SALES)) {
            quotationIds = acceptedQuotations(2);
        }
        Shipment_Request__c changed = [
            SELECT Id, Name FROM Shipment_Request__c
            WHERE Id IN (SELECT Shipment_Request__c FROM Quotation__c WHERE Id = :quotationIds[0])
        ];
        update new Shipment_Request__c(Id = changed.Id, Status__c = 'Cancelled');

        ServiceResult result = convertAs(MANAGER, quotationIds);

        Assert.areEqual(QuotationService.REQUEST_NOT_APPROVED, result.errorsFor(0)[0].code);
        Assert.areEqual(
            String.format(Label.eLogix_Request_Not_Approved, new List<Object>{ changed.Name, 'Cancelled' }),
            result.errorsFor(0)[0].message
        );
        Assert.isTrue(result.errorsFor(1).isEmpty(), String.valueOf(result.errors));
        Assert.areEqual(1, result.recordIds.size());
        Assert.areEqual('Cancelled', [SELECT Status__c FROM Shipment_Request__c WHERE Id = :changed.Id].Status__c, 'Not overwritten.');
        Assert.areEqual(0, [SELECT COUNT() FROM Shipment__c WHERE Quotation__c = :quotationIds[0]]);
        Assert.areEqual(1, [SELECT COUNT() FROM Shipment__c WHERE Quotation__c = :quotationIds[1]]);
    }
}
