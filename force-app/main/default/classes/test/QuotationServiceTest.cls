/**
 * QuotationService through real role users: create, recalculate, submit, approve and reject.
 * Conversion is covered in QuotationConversionTest; direct-DML rules in QuotationTriggerHandlerTest.
 * Reference lane totals: charges 9,745.00, tax 1,169.40, total 10,914.40 (see FreightCalculationServiceTest).
 */
@IsTest
private class QuotationServiceTest {
    private static final String SALES = 'Quote Sales Tester';
    private static final String SALES_B = 'Quote Sales B Tester';
    private static final String MANAGER = 'Quote Manager Tester';
    private static final String OPS = 'Quote Ops Tester';
    private static final String SERVICE = 'Quote CS Tester';
    private static final String MIGRATION = 'Quote Migration Tester';
    /** 10% of the 9,745.00 reference gross freight. */
    private static final Decimal DISCOUNT_AT_THRESHOLD = 974.50;

    @TestSetup
    static void setup() {
        Business_Unit__c businessUnit = TestDataFactory.createBusinessUnit('BU-QS');
        TestDataFactory.createCustomer('CUST-QS', businessUnit.Id);
        TestDataFactory.createRoute('RT-QS', 350);
        insert TestDataFactory.buildRateCard('RC-QS-LCV', 'LCV');
        TestDataFactory.createUser(SALES, TestDataFactory.SALES);
        TestDataFactory.createUser(SALES_B, TestDataFactory.SALES);
        TestDataFactory.createUser(MANAGER, TestDataFactory.LOGISTICS_MANAGER);
        TestDataFactory.createUser(OPS, TestDataFactory.OPERATIONS);
        TestDataFactory.createUser(SERVICE, TestDataFactory.CUSTOMER_SERVICE);
        TestDataFactory.createUser(MIGRATION, new List<String>{ TestDataFactory.SALES, TestDataFactory.DATA_MIGRATION });
    }

    private static List<Shipment_Request__c> newRequests(Integer count, String status) {
        Account customer = [SELECT Id, Business_Unit__c FROM Account WHERE Customer_Code__c = 'CUST-QS'];
        Route__c route = [SELECT Id FROM Route__c WHERE Route_Code__c = 'RT-QS'];
        List<Shipment_Request__c> requests = TestDataFactory.buildShipmentRequests(count, customer.Id, customer.Business_Unit__c, route.Id, status);
        insert requests;
        return requests;
    }

    /** As the running user: a Submitted request, quoted, optionally discounted while Draft. */
    private static Id draftQuotation(Decimal discount) {
        Shipment_Request__c request = newRequests(1, 'Submitted')[0];
        ServiceResult result = new QuotationService().createFromRequests(new List<Id>{ request.Id });
        Assert.isTrue(result.isSuccess, String.valueOf(result.errors));
        Id quotationId = result.recordIds[0];
        if (discount != null && discount != 0) {
            update new Quotation__c(Id = quotationId, Discount__c = discount);
        }
        return quotationId;
    }

    private static Quotation__c reload(Id quotationId) {
        return [
            SELECT
                Status__c,
                Rate_Card__c,
                Base_Freight__c,
                Weight_Charge__c,
                Distance_Charge__c,
                Fuel_Surcharge__c,
                Insurance_Charge__c,
                Tax_Percent__c,
                Discount__c,
                Valid_Until__c,
                Subtotal__c,
                Tax_Amount__c,
                Total_Amount__c,
                Approved_By__c,
                Approval_Date__c,
                Notes__c,
                Shipment_Request__r.Status__c
            FROM Quotation__c
            WHERE Id = :quotationId
        ];
    }

    /* ---------------- create ---------------- */

    @IsTest
    static void createsPricedDraftQuotationAndMovesRequestToQuoted() {
        Id quotationId;
        System.runAs(TestDataFactory.getUser(SALES)) {
            quotationId = draftQuotation(0);
        }
        Quotation__c quotation = reload(quotationId);
        Assert.areEqual('Draft', quotation.Status__c);
        Assert.areEqual([SELECT Id FROM Rate_Card__c WHERE Rate_Card_Code__c = 'RC-QS-LCV'].Id, quotation.Rate_Card__c);
        Assert.areEqual(2000.00, quotation.Base_Freight__c);
        Assert.areEqual(1750.00, quotation.Weight_Charge__c);
        Assert.areEqual(4200.00, quotation.Distance_Charge__c);
        Assert.areEqual(795.00, quotation.Fuel_Surcharge__c);
        Assert.areEqual(1000.00, quotation.Insurance_Charge__c);
        Assert.areEqual(12, quotation.Tax_Percent__c, 'From the Default_Tax_Percent setting.');
        Assert.areEqual(0, quotation.Discount__c);
        Assert.areEqual(Date.today().addDays(15), quotation.Valid_Until__c, 'From the Quotation_Validity_Days setting.');
        Assert.areEqual(9745.00, quotation.Subtotal__c);
        Assert.areEqual(1169.40, quotation.Tax_Amount__c);
        Assert.areEqual(10914.40, quotation.Total_Amount__c);
        Assert.areEqual('Quoted', quotation.Shipment_Request__r.Status__c);
    }

    @IsTest
    static void createFromTwoHundredRequestsIsBulkSafe() {
        System.runAs(TestDataFactory.getUser(SALES)) {
            List<Shipment_Request__c> requests = newRequests(200, 'Submitted');

            Test.startTest();
            Integer queriesBefore = Limits.getQueries();
            Integer dmlBefore = Limits.getDmlStatements();
            ServiceResult result = new QuotationService().createFromRequests(TestDataFactory.idsOf(requests));
            Integer queries = Limits.getQueries() - queriesBefore;
            Integer dml = Limits.getDmlStatements() - dmlBefore;
            Test.stopTest();

            Assert.isTrue(result.isSuccess, String.valueOf(result.errors));
            Assert.areEqual(200, result.recordIds.size());
            Assert.areEqual(3, queries, 'Requests, rate cards, and the request lock in the trigger.');
            Assert.areEqual(2, dml, 'The quotation insert and the request status update.');
        }
        Assert.areEqual(200, [SELECT COUNT() FROM Shipment_Request__c WHERE Status__c = 'Quoted']);
        Assert.areEqual(200, [SELECT COUNT() FROM Quotation__c WHERE Total_Amount__c = 10914.40]);
    }

    @IsTest
    static void requestProblemsAreReportedPerRecord() {
        // Distinct name, address and phone: the org's standard duplicate rules would block a look-alike account.
        Account inactiveCustomer = new Account(
            Name = 'Madurai Handloom Exports',
            Customer_Code__c = 'CUST-QS-OFF',
            BillingStreet = '4 West Masi Street',
            BillingCity = 'Madurai',
            BillingPostalCode = '625001',
            Phone = '+91 452 234 5678',
            Is_Active_Customer__c = true
        );
        insert inactiveCustomer;
        List<Id> ids = new List<Id>();
        System.runAs(TestDataFactory.getUser(SALES)) {
            List<Shipment_Request__c> requests = TestDataFactory.buildShipmentRequests(
                6,
                [SELECT Id FROM Account WHERE Customer_Code__c = 'CUST-QS'].Id,
                [SELECT Id FROM Business_Unit__c WHERE Business_Unit_Code__c = 'BU-QS'].Id,
                [SELECT Id FROM Route__c WHERE Route_Code__c = 'RT-QS'].Id,
                'Submitted'
            );
            requests[1].Status__c = 'Draft';
            requests[2].Route__c = null;
            requests[3].Requested_Vehicle_Type__c = null;
            requests[4].Requested_Vehicle_Type__c = 'Tanker'; // no Tanker rate card
            requests[5].Customer__c = inactiveCustomer.Id;
            insert requests;
            ids = TestDataFactory.idsOf(requests);
        }
        inactiveCustomer.Is_Active_Customer__c = false;
        update inactiveCustomer;
        ids.add(ids[0]); // duplicate
        ids.add(null);

        ServiceResult result;
        System.runAs(TestDataFactory.getUser(SALES)) {
            result = new QuotationService().createFromRequests(ids);
        }

        Map<Id, Shipment_Request__c> byId = new Map<Id, Shipment_Request__c>([SELECT Name, Status__c FROM Shipment_Request__c]);
        Assert.areEqual(1, result.recordIds.size());
        Assert.isTrue(result.errorsFor(0).isEmpty());
        Assert.areEqual(
            String.format(Label.eLogix_Request_Not_Quotable, new List<Object>{ byId.get(ids[1]).Name, 'Draft' }),
            result.errorsFor(1)[0].message,
            'Request eligibility is enforced by the quotation trigger.'
        );
        Assert.areEqual(QuotationService.ROUTE_REQUIRED, result.errorsFor(2)[0].code);
        Assert.areEqual(QuotationService.VEHICLE_TYPE_REQUIRED, result.errorsFor(3)[0].code);
        Assert.areEqual(FreightCalculationService.RATE_CARD_NOT_FOUND, result.errorsFor(4)[0].code);
        Assert.areEqual(QuotationService.CUSTOMER_INACTIVE, result.errorsFor(5)[0].code);
        Assert.areEqual(QuotationService.REQUEST_INVALID, result.errorsFor(6)[0].code);
        Assert.areEqual(QuotationService.REQUEST_INVALID, result.errorsFor(7)[0].code);
        Assert.areEqual('Quoted', byId.get(ids[0]).Status__c);
        Assert.areEqual('Draft', byId.get(ids[1]).Status__c);
        Assert.areEqual(1, [SELECT COUNT() FROM Quotation__c]);
    }

    @IsTest
    static void aQuotedRequestCannotBeQuotedAgain() {
        System.runAs(TestDataFactory.getUser(SALES)) {
            Shipment_Request__c request = newRequests(1, 'Submitted')[0];
            QuotationService service = new QuotationService();
            Assert.isTrue(service.createFromRequests(new List<Id>{ request.Id }).isSuccess);

            ServiceResult again = service.createFromRequests(new List<Id>{ request.Id });

            Assert.isFalse(again.isSuccess);
            Shipment_Request__c saved = [SELECT Name FROM Shipment_Request__c WHERE Id = :request.Id];
            Assert.areEqual(String.format(Label.eLogix_Request_Not_Quotable, new List<Object>{ saved.Name, 'Quoted' }), again.errors[0].message);
            Assert.areEqual(1, [SELECT COUNT() FROM Quotation__c], 'Re-quoting is deferred (decision Q21).');
        }
    }

    @IsTest
    static void usersWithoutQuotationCreateAccessAreDenied() {
        Shipment_Request__c request;
        System.runAs(TestDataFactory.getUser(SALES)) {
            request = newRequests(1, 'Submitted')[0];
        }
        for (String persona : new List<String>{ OPS, SERVICE }) {
            System.runAs(TestDataFactory.getUser(persona)) {
                try {
                    new QuotationService().createFromRequests(new List<Id>{ request.Id });
                    Assert.fail(persona + ' must not create quotations.');
                } catch (AuthorizationException e) {
                    Assert.areEqual(AuthorizationException.ACCESS_DENIED, e.code);
                }
            }
        }
        Assert.areEqual(0, [SELECT COUNT() FROM Quotation__c]);
    }

    @IsTest
    static void anotherUsersPrivateRequestIsNotFound() {
        Shipment_Request__c request;
        System.runAs(TestDataFactory.getUser(SALES)) {
            request = newRequests(1, 'Submitted')[0];
        }
        System.runAs(TestDataFactory.getUser(SALES_B)) {
            ServiceResult result = new QuotationService().createFromRequests(new List<Id>{ request.Id });
            Assert.areEqual(QuotationService.REQUEST_NOT_FOUND, result.errors[0].code);
        }
    }

    @IsTest
    static void aRequestThatCannotMoveFailsOnlyItsOwnQuotation() {
        Shipment_Request__c legacy;
        System.runAs(TestDataFactory.getUser(MIGRATION)) {
            // Loaded under the validation bypass: expected delivery before pickup breaks SR_Delivery_After_Pickup.
            legacy = newRequests(1, 'Submitted')[0];
            legacy.Expected_Delivery_Date__c = legacy.Requested_Pickup_Date__c.addDays(-1);
            update legacy;
        }
        Shipment_Request__c valid;
        System.runAs(TestDataFactory.getUser(SALES)) {
            valid = newRequests(1, 'Submitted')[0];
        }

        ServiceResult result;
        System.runAs(TestDataFactory.getUser(MANAGER)) {
            result = new QuotationService().createFromRequests(new List<Id>{ legacy.Id, valid.Id });
        }

        Assert.areEqual(1, result.recordIds.size());
        Assert.areEqual(1, result.errorsFor(0).size());
        String legacyName = [SELECT Name FROM Shipment_Request__c WHERE Id = :legacy.Id].Name;
        Assert.isTrue(
            result.errorsFor(0)[0].message.startsWith(
                String.format(Label.eLogix_Request_Update_Failed, new List<Object>{ legacyName, '' }).trim()
            ),
            result.errorsFor(0)[0].message
        );
        Assert.isTrue(result.errorsFor(1).isEmpty());
        Assert.areEqual('Submitted', [SELECT Status__c FROM Shipment_Request__c WHERE Id = :legacy.Id].Status__c);
        Assert.areEqual('Quoted', [SELECT Status__c FROM Shipment_Request__c WHERE Id = :valid.Id].Status__c);
        Assert.areEqual(0, [SELECT COUNT() FROM Quotation__c WHERE Shipment_Request__c = :legacy.Id]);
    }

    /* ---------------- recalculate ---------------- */

    @IsTest
    static void recalculateRepricesDraftQuotationsOnly() {
        Id quotationId;
        System.runAs(TestDataFactory.getUser(SALES)) {
            quotationId = draftQuotation(0);
        }
        Rate_Card__c rateCard = [SELECT Id FROM Rate_Card__c WHERE Rate_Card_Code__c = 'RC-QS-LCV'];
        rateCard.Rate_Per_KG__c = 4;
        update rateCard;

        System.runAs(TestDataFactory.getUser(SALES)) {
            QuotationService service = new QuotationService();
            ServiceResult result = service.recalculate(new List<Id>{ quotationId, TestDataFactory.fakeId(Quotation__c.SObjectType, 1) });
            Assert.isTrue(result.errorsFor(0).isEmpty(), String.valueOf(result.errors));
            Assert.areEqual(QuotationService.QUOTATION_NOT_FOUND, result.errorsFor(1)[0].code);

            Quotation__c repriced = reload(quotationId);
            Assert.areEqual(2000.00, repriced.Weight_Charge__c, '500 kg at the new 4.00 per kg.');
            Assert.areEqual(820.00, repriced.Fuel_Surcharge__c, '10% of 8,200.');

            Assert.isTrue(service.submitForApproval(new List<Id>{ quotationId }).isSuccess);
            ServiceResult locked = service.recalculate(new List<Id>{ quotationId });
            Assert.areEqual(QuotationService.QUOTATION_NOT_DRAFT, locked.errors[0].code);
        }
    }

    /* ---------------- submit, approve, reject ---------------- */

    @IsTest
    static void submitWithinThresholdApprovesAutomatically() {
        System.runAs(TestDataFactory.getUser(SALES)) {
            Id quotationId = draftQuotation(DISCOUNT_AT_THRESHOLD);
            ServiceResult result = new QuotationService().submitForApproval(new List<Id>{ quotationId });
            Assert.isTrue(result.isSuccess, String.valueOf(result.errors));
            Quotation__c quotation = reload(quotationId);
            Assert.areEqual('Approved', quotation.Status__c, 'Exactly 10% needs no manual approval (decision Q19).');
            Assert.isNull(quotation.Approved_By__c, 'The automatic path writes no stamp.');
        }
    }

    @IsTest
    static void submitAboveThresholdWaitsForApproval() {
        System.runAs(TestDataFactory.getUser(SALES)) {
            Id quotationId = draftQuotation(DISCOUNT_AT_THRESHOLD + 0.01);
            Assert.isTrue(new QuotationService().submitForApproval(new List<Id>{ quotationId }).isSuccess);
            Assert.areEqual('Pending Approval', reload(quotationId).Status__c);
        }
    }

    @IsTest
    static void managerApprovalWritesAVerifiedStamp() {
        Id quotationId;
        System.runAs(TestDataFactory.getUser(SALES)) {
            quotationId = draftQuotation(2000);
            new QuotationService().submitForApproval(new List<Id>{ quotationId });
        }
        User manager = TestDataFactory.getUser(MANAGER);
        System.runAs(manager) {
            ServiceResult result = new QuotationService().approve(new List<Id>{ quotationId });
            Assert.isTrue(result.isSuccess, String.valueOf(result.errors));
        }
        Quotation__c quotation = reload(quotationId);
        Assert.areEqual('Approved', quotation.Status__c);
        Assert.areEqual(manager.Id, quotation.Approved_By__c);
        Assert.isTrue(Math.abs(quotation.Approval_Date__c.getTime() - System.now().getTime()) < 120000, 'Stamped with the current time.');
    }

    @IsTest
    static void approvalNeedsThePermission() {
        System.runAs(TestDataFactory.getUser(SALES)) {
            Id quotationId = draftQuotation(2000);
            new QuotationService().submitForApproval(new List<Id>{ quotationId });
            try {
                new QuotationService().approve(new List<Id>{ quotationId });
                Assert.fail('Sales Executives cannot approve.');
            } catch (AuthorizationException e) {
                Assert.areEqual(AuthorizationException.ACCESS_DENIED, e.code);
            }
            Assert.areEqual('Pending Approval', reload(quotationId).Status__c);
        }
    }

    @IsTest
    static void ownersCannotApproveTheirOwnQuotation() {
        System.runAs(TestDataFactory.getUser(MANAGER)) {
            Id quotationId = draftQuotation(2000);
            new QuotationService().submitForApproval(new List<Id>{ quotationId });

            ServiceResult result = new QuotationService().approve(new List<Id>{ quotationId });

            Assert.areEqual(QuotationService.SELF_APPROVAL, result.errors[0].code);
            Assert.areEqual('Pending Approval', reload(quotationId).Status__c);
        }
    }

    @IsTest
    static void onlyPendingQuotationsCanBeDecided() {
        Id quotationId;
        System.runAs(TestDataFactory.getUser(SALES)) {
            quotationId = draftQuotation(0);
        }
        System.runAs(TestDataFactory.getUser(MANAGER)) {
            Assert.areEqual(QuotationService.QUOTATION_NOT_PENDING, new QuotationService().approve(new List<Id>{ quotationId }).errors[0].code);
            Assert.areEqual(
                QuotationService.QUOTATION_NOT_PENDING,
                new QuotationService().reject(new List<Id>{ quotationId }, 'Too low.').errors[0].code
            );
        }
    }

    @IsTest
    static void rejectionReturnsToDraftWithTheReason() {
        Id quotationId;
        System.runAs(TestDataFactory.getUser(SALES)) {
            quotationId = draftQuotation(2000);
            new QuotationService().submitForApproval(new List<Id>{ quotationId });
        }
        System.runAs(TestDataFactory.getUser(MANAGER)) {
            ServiceResult blank = new QuotationService().reject(new List<Id>{ quotationId }, '  ');
            Assert.areEqual(QuotationService.REASON_REQUIRED, blank.errors[0].code);

            ServiceResult result = new QuotationService().reject(new List<Id>{ quotationId }, 'Discount too high for this lane.');
            Assert.isTrue(result.isSuccess, String.valueOf(result.errors));
        }
        Quotation__c quotation = reload(quotationId);
        Assert.areEqual('Draft', quotation.Status__c, 'Rejected approval returns to Draft (decision Q22).');
        Assert.areEqual(
            String.format(Label.eLogix_Quotation_Rejection_Note, new List<Object>{ 'Discount too high for this lane.' }),
            quotation.Notes__c
        );
        Assert.isNull(quotation.Approved_By__c);
    }

    @IsTest
    static void emptyInputsAreNoOps() {
        QuotationService service = new QuotationService();
        Assert.isTrue(service.createFromRequests(null).isSuccess);
        Assert.isTrue(service.recalculate(new List<Id>()).isSuccess);
        Assert.isTrue(service.submitForApproval(null).isSuccess);
        Assert.isTrue(service.approve(new List<Id>()).isSuccess);
        Assert.isTrue(service.reject(null, 'x').isSuccess);
        Assert.isTrue(service.convertToShipment(null).isSuccess);
    }

    @IsTest
    static void selectorsReturnEmptyResultsForEmptyInput() {
        Integer queriesBefore = Limits.getQueries();
        Assert.isTrue(new ShipmentRequestSelector().selectForQuotation(null).isEmpty());
        Assert.isTrue(new ShipmentRequestSelector().selectForQuotation(new Set<Id>()).isEmpty());
        Assert.isTrue(new QuotationSelector().selectForUpdate(null).isEmpty());
        Assert.isTrue(new QuotationSelector().sumDiscountLines(new Set<Id>()).isEmpty());
        Assert.isTrue(new QuotationSelector().selectConvertedQuotationIds(null).isEmpty());
        Assert.isTrue(new RateCardSelector().selectEffectiveCandidates(new Set<String>{ 'LCV' }, null, Date.today()).isEmpty());
        Assert.areEqual(queriesBefore, Limits.getQueries(), 'Empty input never queries.');
    }
}
