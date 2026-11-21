/**
 * QuotationDomain through direct DML, as a user, the API or Data Loader would save, without going
 * through QuotationService. Proves that the transition rules, the discount and line locks, the
 * approval stamp and the threshold cannot be bypassed.
 *
 * Two layers are proven. (1) Field-level security: a Sales user cannot even write the protected
 * fields (price components, rate card, approval stamp); in this org that is enforced on DML too.
 * (2) The trigger: an administrator-level user, who does have edit access to those fields, is
 * still stopped by QuotationDomain, with its own messages.
 */
@IsTest
private class QuotationTriggerHandlerTest {
    private static final String SALES = 'Domain Sales Tester';
    private static final String MANAGER = 'Domain Manager Tester';
    private static final String ADMIN = 'Domain Admin Tester';
    private static final Decimal ABOVE_THRESHOLD = 2000; // > 10% of 9,745

    @TestSetup
    static void setup() {
        Business_Unit__c businessUnit = TestDataFactory.createBusinessUnit('BU-QD');
        TestDataFactory.createCustomer('CUST-QD', businessUnit.Id);
        TestDataFactory.createRoute('RT-QD', 350);
        insert TestDataFactory.buildRateCard('RC-QD-LCV', 'LCV');
        TestDataFactory.createUser(SALES, TestDataFactory.SALES);
        TestDataFactory.createUser(MANAGER, TestDataFactory.LOGISTICS_MANAGER);
        TestDataFactory.createUser(ADMIN, 'eLogix_Administrator');
    }

    private static List<Shipment_Request__c> newRequests(Integer count) {
        Account customer = [SELECT Id, Business_Unit__c FROM Account WHERE Customer_Code__c = 'CUST-QD'];
        Route__c route = [SELECT Id FROM Route__c WHERE Route_Code__c = 'RT-QD'];
        List<Shipment_Request__c> requests = TestDataFactory.buildShipmentRequests(count, customer.Id, customer.Business_Unit__c, route.Id, 'Submitted');
        insert requests;
        return requests;
    }

    /** As the running user: a Draft quotation through the service, with an optional discount. */
    private static Quotation__c draft(Decimal discount) {
        Shipment_Request__c request = newRequests(1)[0];
        ServiceResult result = new QuotationService().createFromRequests(new List<Id>{ request.Id });
        Assert.isTrue(result.isSuccess, String.valueOf(result.errors));
        Quotation__c quotation = new Quotation__c(Id = result.recordIds[0], Status__c = 'Draft');
        if (discount != null) {
            quotation.Discount__c = discount;
            update quotation;
        }
        return quotation;
    }

    private static String move(Quotation__c quotation, String status) {
        Database.SaveResult result = Database.update(new Quotation__c(Id = quotation.Id, Status__c = status), false);
        return result.isSuccess() ? null : result.getErrors()[0].getMessage();
    }

    private static String transitionMessage(String fromStatus, String toStatus) {
        return String.format(Label.eLogix_Quotation_Transition_Not_Allowed, new List<Object>{ fromStatus, toStatus });
    }

    private static String approvalMessage(String toStatus) {
        return String.format(Label.eLogix_Quotation_Approval_Required, new List<Object>{ Decimal.valueOf(10).format(), toStatus });
    }

    private static Quotation__c reload(Id quotationId) {
        return [SELECT Status__c, Discount__c, Approved_By__c, Approval_Date__c, Shipment_Request__r.Status__c FROM Quotation__c WHERE Id = :quotationId];
    }

    /* ---------------- insert ---------------- */

    @IsTest
    static void newQuotationsMustStartAsPricedUnapprovedDrafts() {
        Id rateCardId = [SELECT Id FROM Rate_Card__c WHERE Rate_Card_Code__c = 'RC-QD-LCV'].Id;
        System.runAs(TestDataFactory.getUser(SALES)) {
            Shipment_Request__c request = newRequests(1)[0];
            Database.SaveResult blocked = Database.insert(
                new Quotation__c(Shipment_Request__c = request.Id, Rate_Card__c = rateCardId, Status__c = 'Draft'),
                false
            );
            Assert.isFalse(blocked.isSuccess(), 'Sales cannot set the protected rate card or components directly.');
        }
        System.runAs(TestDataFactory.getUser(ADMIN)) {
            List<Shipment_Request__c> requests = newRequests(4);
            List<Quotation__c> attempts = new List<Quotation__c>{
                new Quotation__c(Shipment_Request__c = requests[0].Id, Rate_Card__c = rateCardId, Status__c = 'Approved'),
                new Quotation__c(Shipment_Request__c = requests[1].Id, Rate_Card__c = rateCardId, Status__c = 'Draft', Approved_By__c = UserInfo.getUserId()),
                new Quotation__c(Shipment_Request__c = requests[2].Id, Status__c = 'Draft'),
                new Quotation__c(Shipment_Request__c = requests[3].Id, Rate_Card__c = rateCardId, Status__c = 'Draft', Tax_Percent__c = 12)
            };

            List<Database.SaveResult> results = Database.insert(attempts, false);

            Assert.areEqual(Label.eLogix_Quotation_Must_Start_Draft, results[0].getErrors()[0].getMessage());
            Assert.areEqual(Label.eLogix_Quotation_Must_Start_Draft, results[1].getErrors()[0].getMessage());
            Assert.areEqual(Label.eLogix_Quotation_Not_Priced, results[2].getErrors()[0].getMessage());
            Assert.isTrue(results[3].isSuccess(), 'A priced Draft saved directly is accepted.');
            Assert.areEqual('Quoted', [SELECT Status__c FROM Shipment_Request__c WHERE Id = :requests[3].Id].Status__c, 'Request sync runs on every entry path.');
            Assert.areEqual('Submitted', [SELECT Status__c FROM Shipment_Request__c WHERE Id = :requests[0].Id].Status__c);
        }
    }

    /* ---------------- transitions (decision Q2) ---------------- */

    @IsTest
    static void onlyTheApprovedTransitionsAreAllowed() {
        System.runAs(TestDataFactory.getUser(SALES)) {
            Quotation__c quotation = draft(0);
            for (String target : new List<String>{ 'Sent', 'Accepted', 'Rejected', 'Expired', 'Superseded' }) {
                Assert.areEqual(transitionMessage('Draft', target), move(quotation, target), 'Draft -> ' + target);
            }
            Assert.isNull(move(quotation, 'Approved'), 'Draft -> Approved within the threshold (automatic path).');
            Assert.areEqual(transitionMessage('Approved', 'Draft'), move(quotation, 'Draft'));
            Assert.areEqual(transitionMessage('Approved', 'Accepted'), move(quotation, 'Accepted'));
            Assert.isNull(move(quotation, 'Sent'));
            Assert.areEqual(transitionMessage('Sent', 'Approved'), move(quotation, 'Approved'));
            Assert.isNull(move(quotation, 'Accepted'));
            Assert.areEqual(transitionMessage('Accepted', 'Sent'), move(quotation, 'Sent'), 'Accepted is terminal.');

            Quotation__c refused = draft(0);
            move(refused, 'Approved');
            move(refused, 'Sent');
            Assert.isNull(move(refused, 'Rejected'), 'Customer rejection.');
            Assert.areEqual(transitionMessage('Rejected', 'Sent'), move(refused, 'Sent'), 'Rejected is terminal.');
        }
    }

    @IsTest
    static void pendingToDraftIsForApproversOnly() {
        System.runAs(TestDataFactory.getUser(SALES)) {
            Quotation__c quotation = draft(ABOVE_THRESHOLD);
            Assert.isNull(move(quotation, 'Pending Approval'));
            Assert.areEqual(Label.eLogix_Quotation_Approver_Only, move(quotation, 'Draft'));
        }
    }

    /* ---------------- threshold and stamp ---------------- */

    @IsTest
    static void aboveThresholdCannotBeApprovedSentOrAcceptedWithoutAStamp() {
        System.runAs(TestDataFactory.getUser(SALES)) {
            Quotation__c quotation = draft(ABOVE_THRESHOLD);
            Assert.areEqual(approvalMessage('Approved'), move(quotation, 'Approved'), 'No automatic approval above 10%.');
            Assert.isNull(move(quotation, 'Pending Approval'));
            Assert.areEqual(approvalMessage('Approved'), move(quotation, 'Approved'), 'Changing the status label alone does not approve.');
            Assert.areEqual('Pending Approval', reload(quotation.Id).Status__c);
        }
    }

    @IsTest
    static void theStampCannotBeFabricated() {
        User manager = TestDataFactory.getUser(MANAGER);
        User admin = TestDataFactory.getUser(ADMIN);
        Quotation__c quotation;
        System.runAs(TestDataFactory.getUser(SALES)) {
            quotation = draft(ABOVE_THRESHOLD);
            move(quotation, 'Pending Approval');
            Database.SaveResult forged = Database.update(
                new Quotation__c(Id = quotation.Id, Status__c = 'Approved', Approved_By__c = manager.Id, Approval_Date__c = System.now()),
                false
            );
            Assert.isFalse(forged.isSuccess(), 'Layer 1: Sales cannot write the protected stamp at all.');
        }
        System.runAs(admin) {
            // Layer 2: an administrator with edit access to the stamp still cannot name someone else...
            Database.SaveResult otherApprover = Database.update(
                new Quotation__c(Id = quotation.Id, Status__c = 'Approved', Approved_By__c = manager.Id),
                false
            );
            Assert.areEqual(Label.eLogix_Quotation_Stamp_Invalid, otherApprover.getErrors()[0].getMessage());
            // ...nor stamp without the Pending Approval -> Approved transition...
            Database.SaveResult noTransition = Database.update(new Quotation__c(Id = quotation.Id, Approved_By__c = admin.Id), false);
            Assert.areEqual(Label.eLogix_Quotation_Stamp_Invalid, noTransition.getErrors()[0].getMessage());
            // ...nor approve a quotation they own (decision Q17), even holding the permission.
            Quotation__c own = draft(ABOVE_THRESHOLD);
            move(own, 'Pending Approval');
            Database.SaveResult selfApproval = Database.update(
                new Quotation__c(Id = own.Id, Status__c = 'Approved', Approved_By__c = admin.Id),
                false
            );
            Assert.areEqual(Label.eLogix_Quotation_Stamp_Invalid, selfApproval.getErrors()[0].getMessage());
        }
        System.runAs(manager) {
            Assert.isTrue(new QuotationService().approve(new List<Id>{ quotation.Id }).isSuccess);
        }
        System.runAs(admin) {
            Database.SaveResult backdate = Database.update(new Quotation__c(Id = quotation.Id, Approval_Date__c = System.now().addDays(-30)), false);
            Assert.areEqual(Label.eLogix_Quotation_Stamp_Invalid, backdate.getErrors()[0].getMessage());
            Database.SaveResult cleared = Database.update(new Quotation__c(Id = quotation.Id, Approved_By__c = null), false);
            Assert.areEqual(Label.eLogix_Quotation_Stamp_Invalid, cleared.getErrors()[0].getMessage());
        }
        Quotation__c saved = reload(quotation.Id);
        Assert.areEqual(manager.Id, saved.Approved_By__c);
        Assert.isTrue(saved.Approval_Date__c > System.now().addMinutes(-5), 'The approval time is set by the trigger, not the caller.');
    }

    @IsTest
    static void aboveThresholdWithAValidStampCanBeSentAndAccepted() {
        Quotation__c quotation;
        System.runAs(TestDataFactory.getUser(SALES)) {
            quotation = draft(ABOVE_THRESHOLD);
            move(quotation, 'Pending Approval');
        }
        System.runAs(TestDataFactory.getUser(MANAGER)) {
            Assert.isTrue(new QuotationService().approve(new List<Id>{ quotation.Id }).isSuccess);
        }
        System.runAs(TestDataFactory.getUser(SALES)) {
            Assert.isNull(move(quotation, 'Sent'));
            Assert.isNull(move(quotation, 'Accepted'));
        }
        Quotation__c saved = reload(quotation.Id);
        Assert.areEqual('Accepted', saved.Status__c);
        Assert.areEqual('Approved', saved.Shipment_Request__r.Status__c, 'Customer acceptance approves the request (decision Q4).');
    }

    /* ---------------- locks (decision Q18) ---------------- */

    @IsTest
    static void discountAndChargesAreLockedAfterDraft() {
        Quotation__c quotation;
        System.runAs(TestDataFactory.getUser(SALES)) {
            quotation = draft(ABOVE_THRESHOLD);
            move(quotation, 'Pending Approval');

            Database.SaveResult discount = Database.update(new Quotation__c(Id = quotation.Id, Discount__c = 100), false);
            Assert.areEqual(Label.eLogix_Quotation_Locked, discount.getErrors()[0].getMessage(), 'Not even while pending approval.');

            Database.SaveResult charge = Database.update(new Quotation__c(Id = quotation.Id, Base_Freight__c = 1), false);
            Assert.isFalse(charge.isSuccess(), 'Layer 1: price components are protected fields.');

            Database.SaveResult harmless = Database.update(new Quotation__c(Id = quotation.Id, Notes__c = 'Customer called.'), false);
            Assert.isTrue(harmless.isSuccess(), 'Fields that do not affect the price stay editable.');
        }
        System.runAs(TestDataFactory.getUser(ADMIN)) {
            Database.SaveResult charge = Database.update(new Quotation__c(Id = quotation.Id, Base_Freight__c = 1), false);
            Assert.areEqual(Label.eLogix_Quotation_Locked, charge.getErrors()[0].getMessage(), 'Layer 2: locked even for administrators.');
        }
    }

    @IsTest
    static void linesAreLockedAfterDraftIncludingDeletes() {
        Quotation__c quotation;
        Quotation_Line__c toll;
        System.runAs(TestDataFactory.getUser(SALES)) {
            quotation = draft(0);
            toll = new Quotation_Line__c(Quotation__c = quotation.Id, Charge_Type__c = 'Toll', Amount__c = 450, Description__c = 'Krishnagiri toll');
            insert toll;
            Assert.isNull(move(quotation, 'Approved'));

            Database.SaveResult added = Database.insert(new Quotation_Line__c(Quotation__c = quotation.Id, Charge_Type__c = 'Loading', Amount__c = 300), false);
            Assert.isFalse(added.isSuccess(), 'Sales cannot add a line after Draft.');
        }
        System.runAs(TestDataFactory.getUser(ADMIN)) {
            Database.SaveResult added = Database.insert(new Quotation_Line__c(Quotation__c = quotation.Id, Charge_Type__c = 'Loading', Amount__c = 300), false);
            Assert.areEqual('Quotation lines can only be added or changed while the quotation is in Draft.', added.getErrors()[0].getMessage());
            Database.SaveResult changed = Database.update(new Quotation_Line__c(Id = toll.Id, Amount__c = 1), false);
            Assert.areEqual('Quotation lines can only be added or changed while the quotation is in Draft.', changed.getErrors()[0].getMessage());
        }
        System.runAs(TestDataFactory.getUser(SALES)) {
            Database.DeleteResult removed = Database.delete(toll.Id, false);
            Assert.isFalse(removed.isSuccess(), 'Deleting a line would change the approved price.');
            Assert.areEqual(Label.eLogix_Quotation_Locked, removed.getErrors()[0].getMessage());
        }
        Assert.areEqual(1, [SELECT COUNT() FROM Quotation_Line__c]);
        Assert.areEqual(450, [SELECT Amount__c FROM Quotation_Line__c].Amount__c);
    }

    /* ---------------- request side effects ---------------- */

    @IsTest
    static void acceptanceFailsWhenTheRequestIsNoLongerQuoted() {
        Quotation__c quotation;
        System.runAs(TestDataFactory.getUser(SALES)) {
            quotation = draft(0);
            move(quotation, 'Approved');
            move(quotation, 'Sent');
        }
        Shipment_Request__c request = [SELECT Id, Name FROM Shipment_Request__c LIMIT 1];
        update new Shipment_Request__c(Id = request.Id, Status__c = 'Cancelled');

        System.runAs(TestDataFactory.getUser(SALES)) {
            Assert.areEqual(
                String.format(Label.eLogix_Request_Not_Quoted, new List<Object>{ request.Name, 'Cancelled' }),
                move(quotation, 'Accepted')
            );
        }
        Assert.areEqual('Sent', reload(quotation.Id).Status__c);
    }

    @IsTest
    static void requestSyncOnlyRunsInsideTheQuotationTrigger() {
        try {
            new QuotationDomain().syncRequestStatuses();
            Assert.fail('Request statuses must not be movable outside the quotation trigger.');
        } catch (AuthorizationException e) {
            Assert.areEqual(QuotationDomain.REQUEST_SYNC_TRIGGER_ONLY, e.code);
        }
    }

    @IsTest
    static void savesWithoutARelevantChangeCostNothing() {
        System.runAs(TestDataFactory.getUser(SALES)) {
            List<Shipment_Request__c> requests = newRequests(200);
            ServiceResult created = new QuotationService().createFromRequests(TestDataFactory.idsOf(requests));
            Assert.areEqual(200, created.recordIds.size(), String.valueOf(created.errors));
            List<Quotation__c> quotations = new List<Quotation__c>();
            for (Id quotationId : created.recordIds) {
                quotations.add(new Quotation__c(Id = quotationId, Notes__c = 'Reviewed.'));
            }

            Test.startTest();
            Integer queriesBefore = Limits.getQueries();
            Integer dmlBefore = Limits.getDmlStatements();
            update quotations;
            Integer queries = Limits.getQueries() - queriesBefore;
            Integer dml = Limits.getDmlStatements() - dmlBefore;
            Test.stopTest();

            Assert.areEqual(0, queries);
            Assert.areEqual(1, dml);
        }
    }

    @IsTest
    static void handlerRoutesBeforeInsertToTheDomain() {
        Quotation__c unpriced = new Quotation__c(Status__c = 'Draft');
        Quotation__c approved = new Quotation__c(Status__c = 'Approved');

        new QuotationTriggerHandler(System.TriggerOperation.BEFORE_INSERT, new List<Quotation__c>{ unpriced, approved }, null).run();

        Assert.areEqual(Label.eLogix_Quotation_Not_Priced, unpriced.getErrors()[0].getMessage());
        Assert.areEqual(Label.eLogix_Quotation_Must_Start_Draft, approved.getErrors()[0].getMessage());
    }

    /** A1: a quotation can never be re-pointed to another shipment request, in Draft or later. */
    @IsTest
    static void aQuotationCannotBeMovedToAnotherRequest() {
        System.runAs(TestDataFactory.getUser(SALES)) {
            Quotation__c quotation = draft(0);
            Id original = [SELECT Shipment_Request__c FROM Quotation__c WHERE Id = :quotation.Id].Shipment_Request__c;
            Shipment_Request__c other = newRequests(1)[0];

            Database.SaveResult inDraft = Database.update(new Quotation__c(Id = quotation.Id, Shipment_Request__c = other.Id), false);
            Assert.areEqual(Label.eLogix_Quotation_Request_Immutable, inDraft.getErrors()[0].getMessage(), 'Not even in Draft.');

            Assert.isNull(move(quotation, 'Approved'));
            Database.SaveResult afterDraft = Database.update(new Quotation__c(Id = quotation.Id, Shipment_Request__c = other.Id), false);
            Assert.areEqual(Label.eLogix_Quotation_Request_Immutable, afterDraft.getErrors()[0].getMessage());

            Assert.areEqual(original, [SELECT Shipment_Request__c FROM Quotation__c WHERE Id = :quotation.Id].Shipment_Request__c);
            Assert.areEqual('Submitted', [SELECT Status__c FROM Shipment_Request__c WHERE Id = :other.Id].Status__c, 'The other request is untouched.');
        }
        System.runAs(TestDataFactory.getUser(ADMIN)) {
            Quotation__c adminDraft = draft(0);
            Shipment_Request__c target = newRequests(1)[0];
            Database.SaveResult byAdmin = Database.update(new Quotation__c(Id = adminDraft.Id, Shipment_Request__c = target.Id), false);
            Assert.areEqual(Label.eLogix_Quotation_Request_Immutable, byAdmin.getErrors()[0].getMessage(), 'Applies to administrators too.');
        }
    }

    /** A2: an owner change in the same save cannot hide a self-approval. */
    @IsTest
    static void anOwnerChangeCannotHideASelfApproval() {
        User manager = TestDataFactory.getUser(MANAGER);
        User admin = TestDataFactory.getUser(ADMIN);
        System.runAs(admin) {
            Quotation__c own = draft(ABOVE_THRESHOLD);
            move(own, 'Pending Approval');

            Database.SaveResult disguised = Database.update(
                new Quotation__c(Id = own.Id, OwnerId = manager.Id, Status__c = 'Approved', Approved_By__c = admin.Id),
                false
            );
            Assert.areEqual(Label.eLogix_Quotation_Stamp_Invalid, disguised.getErrors()[0].getMessage());

            Quotation__c unchanged = [SELECT OwnerId, Status__c, Approved_By__c FROM Quotation__c WHERE Id = :own.Id];
            Assert.areEqual(admin.Id, unchanged.OwnerId, 'The whole save was rejected, including the owner change.');
            Assert.areEqual('Pending Approval', unchanged.Status__c);
            Assert.isNull(unchanged.Approved_By__c);

            // The rejection came from the stamp rule, not from transfer rights: the owner change alone is allowed.
            Database.SaveResult transferOnly = Database.update(new Quotation__c(Id = own.Id, OwnerId = manager.Id), false);
            Assert.isTrue(transferOnly.isSuccess(), String.valueOf(transferOnly.getErrors()));
        }
    }

    /**
     * A4: the validity date is editable only in Draft. It is locked in Pending Approval, Approved,
     * Sent and Accepted, and editable again when a rejected approval returns the quotation to Draft.
     */
    @IsTest
    static void validityIsLockedOnceTheQuotationLeavesDraft() {
        Date extended = Date.today().addDays(30);
        Quotation__c pending;
        System.runAs(TestDataFactory.getUser(SALES)) {
            Quotation__c quotation = draft(0);
            Assert.isTrue(Database.update(new Quotation__c(Id = quotation.Id, Valid_Until__c = Date.today().addDays(20)), false).isSuccess(), 'Editable in Draft.');

            for (String status : new List<String>{ 'Approved', 'Sent', 'Accepted' }) {
                Assert.isNull(move(quotation, status));
                Database.SaveResult locked = Database.update(new Quotation__c(Id = quotation.Id, Valid_Until__c = extended), false);
                Assert.areEqual(Label.eLogix_Quotation_Locked, locked.getErrors()[0].getMessage(), 'Locked in ' + status);
            }
            Assert.areEqual(Date.today().addDays(20), [SELECT Valid_Until__c FROM Quotation__c WHERE Id = :quotation.Id].Valid_Until__c);

            pending = draft(ABOVE_THRESHOLD);
            Assert.isNull(move(pending, 'Pending Approval'));
            Database.SaveResult whilePending = Database.update(new Quotation__c(Id = pending.Id, Valid_Until__c = extended), false);
            Assert.areEqual(Label.eLogix_Quotation_Locked, whilePending.getErrors()[0].getMessage(), 'Locked in Pending Approval');
        }
        System.runAs(TestDataFactory.getUser(MANAGER)) {
            Assert.isTrue(new QuotationService().reject(new List<Id>{ pending.Id }, 'Shorten the validity.').isSuccess);
        }
        System.runAs(TestDataFactory.getUser(SALES)) {
            Database.SaveResult backInDraft = Database.update(new Quotation__c(Id = pending.Id, Valid_Until__c = extended), false);
            Assert.isTrue(backInDraft.isSuccess(), 'Editable again after a rejected approval returns the quotation to Draft.');
        }
        Assert.areEqual(extended, [SELECT Valid_Until__c FROM Quotation__c WHERE Id = :pending.Id].Valid_Until__c);
    }
}
