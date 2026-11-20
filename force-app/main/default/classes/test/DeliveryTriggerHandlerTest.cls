/**
 * Phase 5 rules through direct DML, as the UI, the API or Data Loader would save, without
 * DeliveryService: attempt numbering, keys, limits and transitions, proof of delivery rules, the
 * shipment delivery guards, deletion refusals, and the trigger-only entry points.
 */
@IsTest
private class DeliveryTriggerHandlerTest {
    private static final String OPS = 'Rules Ops Tester';
    private static final String FLEET = 'Rules Fleet Tester';
    private static final String MANAGER = 'Rules LM Tester';
    private static Integer sequence = 0;

    @TestSetup
    static void setup() {
        Business_Unit__c businessUnit = TestDataFactory.createBusinessUnit('BU-DT');
        TestDataFactory.createCustomer('CUST-DT', businessUnit.Id);
        TestDataFactory.createUser(OPS, TestDataFactory.OPERATIONS);
        TestDataFactory.createUser(FLEET, TestDataFactory.FLEET);
        TestDataFactory.createUser(MANAGER, TestDataFactory.LOGISTICS_MANAGER);
    }

    private static Account customer() {
        return [SELECT Id, Business_Unit__c FROM Account WHERE Customer_Code__c = 'CUST-DT'];
    }

    /** Operations shipments: count confirmed; the first `onTheRoad` of them allocated and taken to In Transit. */
    private static List<Shipment__c> shipments(Integer count, Integer onTheRoad) {
        Account c = customer();
        List<Shipment__c> records;
        System.runAs(TestDataFactory.getUser(OPS)) {
            records = TestDataFactory.confirmedShipments(count, c.Id, c.Business_Unit__c);
            List<Shipment__c> today = new List<Shipment__c>();
            for (Shipment__c shipment : records) {
                today.add(new Shipment__c(Id = shipment.Id, Pickup_Date__c = Date.today()));
            }
            update today;
        }
        if (onTheRoad == 0) {
            return records;
        }
        List<Vehicle__c> vehicles = new List<Vehicle__c>();
        List<Driver__c> drivers = new List<Driver__c>();
        for (Integer i = 0; i < onTheRoad; i++) {
            vehicles.add(TestDataFactory.buildVehicle('TN-DT-' + (++sequence), c.Business_Unit__c));
            drivers.add(TestDataFactory.buildDriver('DL-DT-' + (++sequence), c.Business_Unit__c));
        }
        List<Shipment__c> moves = new List<Shipment__c>();
        System.runAs(TestDataFactory.getUser(FLEET)) {
            insert vehicles;
            insert drivers;
            List<AllocationRequest> requests = new List<AllocationRequest>();
            for (Integer i = 0; i < onTheRoad; i++) {
                requests.add(new AllocationRequest(records[i].Id, vehicles[i].Id, drivers[i].Id));
                moves.add(new Shipment__c(Id = records[i].Id));
            }
            Assert.isTrue(new FleetAllocationService().allocate(requests).isSuccess);
        }
        System.runAs(TestDataFactory.getUser(OPS)) {
            TestDataFactory.advance(moves, new List<String>{ 'Ready for Dispatch', 'Dispatched', 'In Transit' });
        }
        return records;
    }

    private static String firstError(Database.SaveResult result) {
        return result.isSuccess() ? null : result.getErrors()[0].getMessage();
    }

    private static String nameOf(Id shipmentId) {
        return [SELECT Name FROM Shipment__c WHERE Id = :shipmentId].Name;
    }

    /* ---------------- attempts ---------------- */

    @IsTest
    static void directAttemptsAreNumberedKeyedAndChecked() {
        List<Shipment__c> records = shipments(2, 1); // 0 In Transit, 1 Confirmed
        Assert.isTrue(Delivery__c.Attempt_Key__c.getDescribe().isUnique(), 'Requirement 2: a database-level unique key.');
        Delivery__c attempt = new Delivery__c(Shipment__c = records[0].Id, Delivery_Status__c = 'Scheduled');
        System.runAs(TestDataFactory.getUser(OPS)) {
            insert attempt;
            Delivery__c saved = [SELECT Attempt_Number__c, Attempt_Key__c FROM Delivery__c WHERE Id = :attempt.Id];
            Assert.areEqual(1, saved.Attempt_Number__c);
            Assert.areEqual(DeliveryDomain.attemptKey(records[0].Id, 1), saved.Attempt_Key__c);

            String name0 = nameOf(records[0].Id);
            String name1 = nameOf(records[1].Id);
            Assert.areEqual(
                String.format(Label.eLogix_Delivery_Attempt_Open, new List<Object>{ name0 }),
                firstError(Database.insert(new Delivery__c(Shipment__c = records[0].Id, Delivery_Status__c = 'Scheduled'), false))
            );
            Assert.areEqual(
                String.format(Label.eLogix_Delivery_Attempt_Not_Allowed, new List<Object>{ name1 }),
                firstError(Database.insert(new Delivery__c(Shipment__c = records[1].Id, Delivery_Status__c = 'Scheduled'), false))
            );
            Assert.areEqual(
                String.format(Label.eLogix_Delivery_Status_Not_Supported, new List<Object>{ 'Returned' }),
                firstError(Database.update(new Delivery__c(Id = attempt.Id, Delivery_Status__c = 'Returned'), false))
            );
            Assert.areEqual(
                String.format(Label.eLogix_Delivery_Transition_Not_Allowed, new List<Object>{ 'Scheduled', 'Delivered' }),
                firstError(Database.update(new Delivery__c(Id = attempt.Id, Delivery_Status__c = 'Delivered', Receiver_Name__c = 'X', Delivery_Date__c = System.now()), false))
            );
            Assert.isNull(firstError(Database.update(new Delivery__c(Id = attempt.Id, Delivery_Status__c = 'Out for Delivery'), false)), 'Scheduled -> Out for Delivery.');
            // Layer 1: the attempt key is a protected field.
            Assert.isFalse(Database.update(new Delivery__c(Id = attempt.Id, Attempt_Key__c = 'forged'), false).isSuccess());
        }
        // Layer 2: even with field access (the running administrator), the trigger refuses.
        Assert.areEqual(
            Label.eLogix_Delivery_Attempt_Immutable,
            firstError(Database.update(new Delivery__c(Id = attempt.Id, Attempt_Key__c = 'forged'), false))
        );
    }

    @IsTest
    static void deliveredAttemptsNeedTheShipmentOutForDeliveryAndAProof() {
        Shipment__c shipment = shipments(1, 1)[0];
        Delivery__c attempt = new Delivery__c(Shipment__c = shipment.Id, Delivery_Status__c = 'Out for Delivery');
        System.runAs(TestDataFactory.getUser(OPS)) {
            insert attempt;
            // The shipment is still In Transit: not deliverable yet.
            Delivery__c deliver = new Delivery__c(Id = attempt.Id, Delivery_Status__c = 'Delivered', Receiver_Name__c = 'Mr Ravi', Delivery_Date__c = System.now());
            Assert.areEqual(String.format(Label.eLogix_Delivery_Confirm_Status, new List<Object>{ nameOf(shipment.Id) }), firstError(Database.update(deliver, false)));

            update new Shipment__c(Id = shipment.Id, Status__c = 'Out for Delivery'); // the open attempt satisfies the guard
            Assert.areEqual(Label.eLogix_Delivery_Pod_Required, firstError(Database.update(deliver, false)));

            Proof_of_Delivery__c proof = new Proof_of_Delivery__c(Delivery__c = attempt.Id, Receiver_Name__c = 'Mr Ravi');
            insert proof;
            Assert.areEqual(Label.eLogix_Delivery_Evidence_Required, firstError(Database.update(deliver, false)));
            TestDataFactory.attachEvidence(proof.Id);
            Assert.isNull(firstError(Database.update(deliver, false)));

            // Delivered is history.
            Assert.areEqual(
                String.format(Label.eLogix_Delivery_Attempt_Locked, new List<Object>{ 'Delivered' }),
                firstError(Database.update(new Delivery__c(Id = attempt.Id, Receiver_Name__c = 'Someone else'), false))
            );
        }
        Assert.areEqual(
            Label.eLogix_Delivery_Attempt_Immutable,
            firstError(Database.update(new Delivery__c(Id = attempt.Id, Attempt_Number__c = 5), false)),
            'Even with field access, the attempt number cannot change.'
        );
        // Even an administrator cannot delete delivery history.
        Assert.areEqual(Label.eLogix_Delivery_Delete_Not_Allowed, Database.delete(attempt.Id, false).getErrors()[0].getMessage());
    }

    /* ---------------- shipment delivery guards (direct DML) ---------------- */

    @IsTest
    static void shipmentDeliveryStatusesFollowTheAttempts() {
        Shipment__c shipment = shipments(1, 1)[0];
        System.runAs(TestDataFactory.getUser(OPS)) {
            Assert.areEqual(
                Label.eLogix_Delivery_Guard_Open_Attempt,
                firstError(Database.update(new Shipment__c(Id = shipment.Id, Status__c = 'Out for Delivery'), false))
            );
            insert new Delivery__c(Shipment__c = shipment.Id, Delivery_Status__c = 'Out for Delivery');
            update new Shipment__c(Id = shipment.Id, Status__c = 'Out for Delivery');
            Assert.areEqual(
                Label.eLogix_Delivery_Guard_Delivered,
                firstError(Database.update(new Shipment__c(Id = shipment.Id, Status__c = 'Delivered', Actual_Delivery_Date__c = Date.today()), false))
            );
            Assert.areEqual(
                Label.eLogix_Delivery_Guard_Failed,
                firstError(Database.update(new Shipment__c(Id = shipment.Id, Status__c = 'Failed Delivery'), false))
            );
        }
        // Not even the status override skips the guard.
        Assert.areEqual(
            Label.eLogix_Delivery_Guard_Delivered,
            firstError(Database.update(new Shipment__c(Id = shipment.Id, Status__c = 'Delivered', Actual_Delivery_Date__c = Date.today()), false))
        );
        Assert.areEqual('Out for Delivery', [SELECT Status__c FROM Shipment__c WHERE Id = :shipment.Id].Status__c);
    }

    @IsTest
    static void theDeliveryGuardFailsClosedOutsideTheShipmentTrigger() {
        Shipment__c record = TestDataFactory.shipmentInMemory(TestDataFactory.fakeId(Shipment__c.SObjectType, 1), 'Delivered', 1);
        Map<Integer, ShipmentStatusPolicy.Violation> violations = new ShipmentDeliveryGuard()
            .check(new List<ShipmentStatusPolicy.StatusChange>{ new ShipmentStatusPolicy.StatusChange(0, record, 'Out for Delivery', 'Delivered') });
        Assert.areEqual(ShipmentDeliveryGuard.DELIVERY_REQUIRED, violations.get(0).code);
    }

    /* ---------------- proofs of delivery ---------------- */

    @IsTest
    static void proofsFollowTheirAttempt() {
        Shipment__c shipment = shipments(1, 1)[0];
        Id managerId = TestDataFactory.getUser(MANAGER).Id;
        Proof_of_Delivery__c proof;
        System.runAs(TestDataFactory.getUser(OPS)) {
            Delivery__c attempt = new Delivery__c(Shipment__c = shipment.Id, Delivery_Status__c = 'Out for Delivery');
            insert attempt;
            proof = new Proof_of_Delivery__c(Delivery__c = attempt.Id, Receiver_Name__c = 'Mrs Devi');
            insert proof;
            Assert.areEqual(shipment.Id, [SELECT Shipment__c FROM Proof_of_Delivery__c WHERE Id = :proof.Id].Shipment__c);
            Assert.areEqual(
                Label.eLogix_Delivery_Pod_Exists,
                firstError(Database.insert(new Proof_of_Delivery__c(Delivery__c = attempt.Id, Receiver_Name__c = 'Again'), false))
            );
            // Correctable while the attempt is open.
            Assert.isNull(firstError(Database.update(new Proof_of_Delivery__c(Id = proof.Id, Receiver_Name__c = 'Mrs Devi R'), false)));

            update new Shipment__c(Id = shipment.Id, Status__c = 'Out for Delivery');
            update new Delivery__c(Id = attempt.Id, Delivery_Status__c = 'Failed', Failure_Reason__c = 'Refused by Consignee');
            Assert.areEqual(
                Label.eLogix_Delivery_Pod_Locked,
                firstError(Database.update(new Proof_of_Delivery__c(Id = proof.Id, Receiver_Name__c = 'Changed'), false))
            );
            Assert.areEqual(
                Label.eLogix_Delivery_Pod_Attempt_Closed,
                firstError(Database.insert(new Proof_of_Delivery__c(Delivery__c = attempt.Id, Receiver_Name__c = 'Late'), false))
            );
        }
        // Verification only after a delivery, in the verifier's own name.
        Assert.areEqual(
            Label.eLogix_Delivery_Pod_Verification,
            firstError(Database.update(new Proof_of_Delivery__c(Id = proof.Id, Verified_By__c = managerId), false))
        );
        Assert.areEqual(Label.eLogix_Delivery_Delete_Not_Allowed, Database.delete(proof.Id, false).getErrors()[0].getMessage());
    }

    @IsTest
    static void aShipmentWithProofOfDeliveryCannotBeDeleted() {
        Account c = customer();
        Vehicle__c vehicle = TestDataFactory.buildVehicle('TN-DT-DEL', c.Business_Unit__c);
        Driver__c driver = TestDataFactory.buildDriver('DL-DT-DEL', c.Business_Unit__c);
        insert vehicle;
        insert driver;
        Shipment__c delivered;
        System.runAs(TestDataFactory.getUser(MANAGER)) {
            delivered = TestDataFactory.deliveredShipment(c.Id, c.Business_Unit__c, vehicle.Id, driver.Id);
        }
        Database.DeleteResult result = Database.delete(delivered.Id, false);
        Assert.areEqual(String.format(Label.eLogix_Delivery_Shipment_Delete_Blocked, new List<Object>{ nameOf(delivered.Id) }), result.getErrors()[0].getMessage());
        // The Phase 2 hard rule still applies to a real delivery.
        Database.SaveResult reverse = Database.update(new Shipment__c(Id = delivered.Id, Status__c = 'Dispatched'), false);
        Assert.isTrue(firstError(reverse).contains('delivered shipment'), firstError(reverse));
    }

    /* ---------------- trigger-only entry points ---------------- */

    @IsTest
    static void triggerOnlyEntryPointsRefuseOtherCallers() {
        Map<String, String> codes = new Map<String, String>();
        try {
            new DeliveryService().closeAttemptsOfCancelledShipments();
        } catch (AuthorizationException e) {
            codes.put('close', e.code);
        }
        try {
            new DeliveryService().rejectDeletionWithProofOfDelivery();
        } catch (AuthorizationException e) {
            codes.put('delete', e.code);
        }
        try {
            new FleetAllocationService().advanceAssignmentLifecycle();
        } catch (AuthorizationException e) {
            codes.put('lifecycle', e.code);
        }
        Assert.areEqual(DeliveryService.CANCELLATION_TRIGGER_ONLY, codes.get('close'));
        Assert.areEqual(DeliveryService.DELETION_TRIGGER_ONLY, codes.get('delete'));
        Assert.areEqual(FleetAllocationService.LIFECYCLE_TRIGGER_ONLY, codes.get('lifecycle'));

        DeliverySelector selector = new DeliverySelector();
        Set<Id> none = new Set<Id>{ TestDataFactory.fakeId(Shipment__c.SObjectType, 1) };
        Integer refused = 0;
        for (Integer i = 0; i < 9; i++) {
            try {
                switch on i {
                    when 0 { selector.lockShipmentsForAttempts(none); }
                    when 1 { selector.shipmentStatuses(none); }
                    when 2 { selector.attemptsOfShipments(none); }
                    when 3 { selector.attempts(none); }
                    when 4 { selector.proofsOfAttempts(none); }
                    when 5 { selector.proofIdsWithFiles(none); }
                    when 6 { selector.lockOpenAttemptsOfShipments(none); }
                    when 7 { selector.shipmentIdsWithProofs(none); }
                    when 8 { selector.documentIdsLinkedToProofs(none); }
                }
            } catch (AuthorizationException e) {
                if (e.code == DeliverySelector.ENFORCEMENT_TRIGGER_ONLY) {
                    refused++;
                }
            }
        }
        Assert.areEqual(9, refused, 'Every sharing-ignoring delivery read refuses a caller outside its trigger.');
        Assert.isNull(TriggerContext.current());
    }

    @IsTest
    static void theHandlersRouteDeleteToARefusal() {
        Delivery__c attempt = new Delivery__c(Id = TestDataFactory.fakeId(Delivery__c.SObjectType, 1));
        new DeliveryTriggerHandler(System.TriggerOperation.BEFORE_DELETE, null, new Map<Id, SObject>{ attempt.Id => attempt }).run();
        Assert.areEqual(Label.eLogix_Delivery_Delete_Not_Allowed, attempt.getErrors()[0].getMessage());
        Proof_of_Delivery__c proof = new Proof_of_Delivery__c(Id = TestDataFactory.fakeId(Proof_of_Delivery__c.SObjectType, 1));
        new ProofOfDeliveryTriggerHandler(System.TriggerOperation.BEFORE_DELETE, null, new Map<Id, SObject>{ proof.Id => proof }).run();
        Assert.areEqual(Label.eLogix_Delivery_Delete_Not_Allowed, proof.getErrors()[0].getMessage());
    }
}
