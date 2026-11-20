/**
 * Phase 5 delivery use cases through DeliveryService: the attempt / proof / evidence / confirmation
 * sequence, failed attempts and retries on the same assignment, the attempt limit (D4), duplicate and
 * repeated confirmations, the evidence requirement (D5), transactional consistency with partial
 * success, access, and cancellation after dispatch (D2).
 */
@IsTest
private class DeliveryServiceTest {
    private static final String OPS = 'Delivery Ops Tester';
    private static final String FLEET = 'Delivery Fleet Tester';
    private static final String MANAGER = 'Delivery LM Tester';
    private static Integer sequence = 0;

    @TestSetup
    static void setup() {
        Business_Unit__c businessUnit = TestDataFactory.createBusinessUnit('BU-DS');
        TestDataFactory.createCustomer('CUST-DS', businessUnit.Id);
        TestDataFactory.createUser(OPS, TestDataFactory.OPERATIONS);
        TestDataFactory.createUser(FLEET, TestDataFactory.FLEET);
        TestDataFactory.createUser(MANAGER, TestDataFactory.LOGISTICS_MANAGER);
    }

    /* ---------------- helpers ---------------- */

    private static Account customer() {
        return [SELECT Id, Business_Unit__c FROM Account WHERE Customer_Code__c = 'CUST-DS'];
    }

    /** Operations shipments, allocated by the Fleet Manager and taken to In Transit (pickup today). */
    private static List<Shipment__c> inTransit(Integer count) {
        Account c = customer();
        List<Shipment__c> shipments;
        System.runAs(TestDataFactory.getUser(OPS)) {
            shipments = TestDataFactory.confirmedShipments(count, c.Id, c.Business_Unit__c);
            List<Shipment__c> today = new List<Shipment__c>();
            for (Shipment__c shipment : shipments) {
                today.add(new Shipment__c(Id = shipment.Id, Pickup_Date__c = Date.today()));
            }
            update today;
        }
        List<Vehicle__c> vehicles = new List<Vehicle__c>();
        List<Driver__c> drivers = new List<Driver__c>();
        for (Integer i = 0; i < count; i++) {
            vehicles.add(TestDataFactory.buildVehicle('TN-DS-' + (++sequence), c.Business_Unit__c));
            drivers.add(TestDataFactory.buildDriver('DL-DS-' + (++sequence), c.Business_Unit__c));
        }
        System.runAs(TestDataFactory.getUser(FLEET)) {
            insert vehicles;
            insert drivers;
            List<AllocationRequest> requests = new List<AllocationRequest>();
            for (Integer i = 0; i < count; i++) {
                requests.add(new AllocationRequest(shipments[i].Id, vehicles[i].Id, drivers[i].Id));
            }
            ServiceResult allocated = new FleetAllocationService().allocate(requests);
            Assert.isTrue(allocated.isSuccess, String.valueOf(allocated.errors));
        }
        System.runAs(TestDataFactory.getUser(OPS)) {
            List<Shipment__c> moves = new List<Shipment__c>();
            for (Shipment__c shipment : shipments) {
                moves.add(new Shipment__c(Id = shipment.Id));
            }
            TestDataFactory.advance(moves, new List<String>{ 'Ready for Dispatch', 'Dispatched', 'In Transit' });
        }
        return shipments;
    }

    private static DeliveryService service() {
        return new DeliveryService();
    }

    private static Delivery__c attemptOf(Id shipmentId, Integer attemptNumber) {
        return [
            SELECT Id, Delivery_Status__c, Attempt_Number__c, Attempt_Key__c, Receiver_Name__c, Delivery_Date__c, Failure_Reason__c, Failure_Notes__c, Delivered_By__c
            FROM Delivery__c
            WHERE Shipment__c = :shipmentId AND Attempt_Number__c = :attemptNumber
        ];
    }

    private static String statusOf(Id shipmentId) {
        return [SELECT Status__c FROM Shipment__c WHERE Id = :shipmentId].Status__c;
    }

    private static Vehicle_Assignment__c tripOf(Id shipmentId) {
        return [SELECT Id, Status__c, Assignment_End__c FROM Vehicle_Assignment__c WHERE Shipment__c = :shipmentId];
    }

    /* ---------------- the delivery sequence ---------------- */

    @IsTest
    static void aDeliveryWithProofAndEvidenceCompletesTheTrip() {
        Shipment__c shipment = inTransit(1)[0];
        Assert.areEqual('Active', tripOf(shipment.Id).Status__c, 'Dispatch activated the trip.');

        System.runAs(TestDataFactory.getUser(OPS)) {
            ServiceResult started = service().startAttempts(new List<Id>{ shipment.Id });
            Assert.isTrue(started.isSuccess, String.valueOf(started.errors));
            Delivery__c attempt = attemptOf(shipment.Id, 1);
            Assert.areEqual(started.recordIds[0], attempt.Id);
            Assert.areEqual(DeliveryDomain.attemptKey(shipment.Id, 1), attempt.Attempt_Key__c);
            Assert.isNotNull(attempt.Delivered_By__c, 'The allocated driver.');
            Assert.areEqual('Out for Delivery', statusOf(shipment.Id));

            ProofOfDeliveryRequest proof = new ProofOfDeliveryRequest(shipment.Id, 'Ms Lakshmi, stores');
            proof.deliveryNotes = 'Two crates, seals intact.';
            Id proofId = service().recordProofs(new List<ProofOfDeliveryRequest>{ proof }).recordIds[0];
            TestDataFactory.attachEvidence(proofId);

            ServiceResult confirmed = service().confirmDeliveries(new List<Id>{ shipment.Id });
            Assert.isTrue(confirmed.isSuccess, String.valueOf(confirmed.errors));

            // Requirement: a repeated confirmation changes nothing and records no event.
            ServiceResult again = service().confirmDeliveries(new List<Id>{ shipment.Id });
            Assert.areEqual(DeliveryService.ALREADY_DELIVERED, again.errors[0].code);
        }

        Delivery__c delivered = attemptOf(shipment.Id, 1);
        Proof_of_Delivery__c pod = [SELECT Received_Date__c, Shipment__c FROM Proof_of_Delivery__c WHERE Delivery__c = :delivered.Id];
        Assert.areEqual('Delivered', delivered.Delivery_Status__c);
        Assert.areEqual('Ms Lakshmi, stores', delivered.Receiver_Name__c);
        Assert.areEqual(pod.Received_Date__c, delivered.Delivery_Date__c);
        Assert.areEqual(shipment.Id, pod.Shipment__c, 'Derived from the attempt.');
        Shipment__c saved = [SELECT Status__c, Actual_Delivery_Date__c FROM Shipment__c WHERE Id = :shipment.Id];
        Assert.areEqual('Delivered', saved.Status__c);
        Assert.areEqual(pod.Received_Date__c.date(), saved.Actual_Delivery_Date__c);
        Assert.areEqual('Completed', tripOf(shipment.Id).Status__c, 'Delivery completes the trip.');
        Assert.areEqual(1, [SELECT COUNT() FROM Tracking_Event__c WHERE Shipment__c = :shipment.Id AND To_Status__c = 'Delivered']);
        Assert.areEqual(1, [SELECT COUNT() FROM Tracking_Event__c WHERE Shipment__c = :shipment.Id AND To_Status__c = 'Out for Delivery']);
    }

    @IsTest
    static void failedAttemptsRetryOnTheSameTripUpToTheLimit() {
        Shipment__c shipment = inTransit(1)[0];
        Id tripId = tripOf(shipment.Id).Id;
        Integer limitValue = SettingsService.getNumber(DeliveryDomain.MAX_ATTEMPTS_SETTING).intValue();
        Assert.areEqual(3, limitValue, 'D4 default.');

        Test.startTest(); // the loop runs many saves; give it its own limits
        System.runAs(TestDataFactory.getUser(OPS)) {
            for (Integer attempt = 1; attempt <= limitValue; attempt++) {
                Assert.isTrue(service().startAttempts(new List<Id>{ shipment.Id }).isSuccess, 'Attempt ' + attempt);
                DeliveryFailureRequest failure = new DeliveryFailureRequest(shipment.Id, 'Consignee Unavailable');
                failure.notes = 'Gate closed, attempt ' + attempt + '.';
                Assert.isTrue(service().recordFailures(new List<DeliveryFailureRequest>{ failure }).isSuccess, 'Failure ' + attempt);
                Assert.areEqual('Failed Delivery', statusOf(shipment.Id));
                Assert.areEqual('Active', tripOf(shipment.Id).Status__c, 'A failed delivery keeps the trip Active.');
            }
            ServiceResult beyond = service().startAttempts(new List<Id>{ shipment.Id });
            Assert.isTrue(beyond.errors[0].message.contains('used all 3 delivery attempts'), beyond.errors[0].message);
        }
        Test.stopTest();

        Assert.areEqual(3, [SELECT COUNT() FROM Delivery__c WHERE Shipment__c = :shipment.Id AND Delivery_Status__c = 'Failed']);
        Assert.areEqual(1, [SELECT COUNT() FROM Vehicle_Assignment__c WHERE Shipment__c = :shipment.Id], 'Retries reuse the one assignment.');
        Assert.areEqual(tripId, tripOf(shipment.Id).Id);
        Assert.areEqual('Failed Delivery', statusOf(shipment.Id), 'The refused fourth attempt changed nothing.');

        // Every retry keeps its own history: one attempt record per try, numbered and keyed in order,
        // each with its own reason and notes.
        List<Delivery__c> attempts = [
            SELECT Attempt_Number__c, Attempt_Key__c, Delivery_Status__c, Failure_Notes__c
            FROM Delivery__c
            WHERE Shipment__c = :shipment.Id
            ORDER BY Attempt_Number__c
        ];
        for (Integer i = 0; i < attempts.size(); i++) {
            Assert.areEqual(i + 1, attempts[i].Attempt_Number__c);
            Assert.areEqual(DeliveryDomain.attemptKey(shipment.Id, i + 1), attempts[i].Attempt_Key__c);
            Assert.areEqual('Gate closed, attempt ' + (i + 1) + '.', attempts[i].Failure_Notes__c);
        }
        // Every retry's status events are recorded, even though the whole test runs within a second or
        // two: three Out for Delivery and three Failed Delivery, alternating, with unique keys whose
        // per-shipment sequence increases (requirement 7, event key fix).
        List<Tracking_Event__c> events = [
            SELECT To_Status__c, Event_Key__c
            FROM Tracking_Event__c
            WHERE Shipment__c = :shipment.Id AND To_Status__c IN ('Out for Delivery', 'Failed Delivery')
            ORDER BY Event_Timestamp__c, CreatedDate, Id
        ];
        Assert.areEqual(6, events.size());
        Set<String> keys = new Set<String>();
        Integer lastSequence = 0;
        for (Integer i = 0; i < events.size(); i++) {
            Assert.isTrue(keys.add(events[i].Event_Key__c), 'No duplicate status events.');
            Assert.areEqual(Math.mod(i, 2) == 0 ? 'Out for Delivery' : 'Failed Delivery', events[i].To_Status__c, 'Event ' + i);
            Integer sequence = Integer.valueOf(events[i].Event_Key__c.substringAfterLast(':'));
            Assert.isTrue(sequence > lastSequence, 'Sequences increase with the history.');
            lastSequence = sequence;
        }

        // After the last failure only On Hold or Return Initiated remain.
        System.runAs(TestDataFactory.getUser(OPS)) {
            update new Shipment__c(Id = shipment.Id, Status__c = 'On Hold', Hold_Reason__c = 'Customer to collect.');
        }
        Assert.areEqual('On Hold', statusOf(shipment.Id));
    }

    @IsTest
    static void confirmationNeedsAProofAndEvidenceAndIsAllOrNothing() {
        Shipment__c shipment = inTransit(1)[0];
        System.runAs(TestDataFactory.getUser(OPS)) {
            service().startAttempts(new List<Id>{ shipment.Id });

            ServiceResult noProof = service().confirmDeliveries(new List<Id>{ shipment.Id });
            Assert.areEqual(Label.eLogix_Delivery_Pod_Required, noProof.errors[0].message);

            Id proofId = service().recordProofs(new List<ProofOfDeliveryRequest>{ new ProofOfDeliveryRequest(shipment.Id, 'Mr Arun') }).recordIds[0];
            ServiceResult noFile = service().confirmDeliveries(new List<Id>{ shipment.Id });
            Assert.areEqual(Label.eLogix_Delivery_Evidence_Required, noFile.errors[0].message);

            // Nothing was half-saved by the refused confirmations.
            Assert.areEqual('Out for Delivery', attemptOf(shipment.Id, 1).Delivery_Status__c);
            Assert.areEqual('Out for Delivery', statusOf(shipment.Id));

            TestDataFactory.attachEvidence(proofId);
            Assert.isTrue(service().confirmDeliveries(new List<Id>{ shipment.Id }).isSuccess);
        }
    }

    @IsTest
    static void duplicateRequestsAreRefused() {
        Shipment__c shipment = inTransit(1)[0];
        System.runAs(TestDataFactory.getUser(OPS)) {
            ServiceResult twice = service().startAttempts(new List<Id>{ shipment.Id, shipment.Id });
            Assert.areEqual(1, twice.recordIds.size());
            Assert.areEqual(DeliveryService.DUPLICATE_REQUEST, twice.errorsFor(1)[0].code);

            ServiceResult again = service().startAttempts(new List<Id>{ shipment.Id });
            Assert.isTrue(again.errors[0].message.contains('already has an open delivery attempt'), again.errors[0].message);

            ProofOfDeliveryRequest proof = new ProofOfDeliveryRequest(shipment.Id, 'Mr Arun');
            Id proofId = service().recordProofs(new List<ProofOfDeliveryRequest>{ proof }).recordIds[0];
            Assert.areEqual(Label.eLogix_Delivery_Pod_Exists, service().recordProofs(new List<ProofOfDeliveryRequest>{ proof }).errors[0].message);
            TestDataFactory.attachEvidence(proofId);

            ServiceResult confirmTwice = service().confirmDeliveries(new List<Id>{ shipment.Id, shipment.Id });
            Assert.areEqual(1, confirmTwice.recordIds.size());
            Assert.areEqual(DeliveryService.DUPLICATE_REQUEST, confirmTwice.errorsFor(1)[0].code);
        }
        Assert.areEqual(1, [SELECT COUNT() FROM Delivery__c WHERE Shipment__c = :shipment.Id]);
        Assert.areEqual(1, [SELECT COUNT() FROM Tracking_Event__c WHERE Shipment__c = :shipment.Id AND To_Status__c = 'Delivered']);
    }

    /** Requirement 3 and 4: a second-step failure rolls back that record's first step; the others are saved. */
    @IsTest
    static void aFailureInTheShipmentStepLeavesNoPartialUpdate() {
        List<Shipment__c> shipments = inTransit(2);
        System.runAs(TestDataFactory.getUser(OPS)) {
            service().startAttempts(new List<Id>{ shipments[0].Id, shipments[1].Id });
            ProofOfDeliveryRequest good = new ProofOfDeliveryRequest(shipments[0].Id, 'Receiver A');
            // Received yesterday, before today's pickup: the shipment rejects that actual delivery date.
            ProofOfDeliveryRequest bad = new ProofOfDeliveryRequest(shipments[1].Id, 'Receiver B');
            bad.receivedAt = System.now().addDays(-1);
            List<Id> proofIds = service().recordProofs(new List<ProofOfDeliveryRequest>{ good, bad }).recordIds;
            TestDataFactory.attachEvidence(proofIds[0]);
            TestDataFactory.attachEvidence(proofIds[1]);

            ServiceResult result = service().confirmDeliveries(new List<Id>{ shipments[0].Id, shipments[1].Id });

            Assert.areEqual(new List<Id>{ shipments[0].Id }, result.recordIds);
            Assert.isFalse(result.errorsFor(1).isEmpty());
        }
        Assert.areEqual('Delivered', attemptOf(shipments[0].Id, 1).Delivery_Status__c);
        Assert.areEqual('Delivered', statusOf(shipments[0].Id));
        Assert.areEqual('Out for Delivery', attemptOf(shipments[1].Id, 1).Delivery_Status__c, 'The attempt step was rolled back.');
        Assert.areEqual('Out for Delivery', statusOf(shipments[1].Id));
        Assert.areEqual('Active', tripOf(shipments[1].Id).Status__c);
        Assert.areEqual(0, [SELECT COUNT() FROM Tracking_Event__c WHERE Shipment__c = :shipments[1].Id AND To_Status__c = 'Delivered']);
    }

    @IsTest
    static void accessIsEnforced() {
        Shipment__c shipment = inTransit(1)[0];
        System.runAs(TestDataFactory.getUser(FLEET)) {
            try {
                service().startAttempts(new List<Id>{ shipment.Id });
                Assert.fail('The Fleet Manager may only read deliveries.');
            } catch (AuthorizationException e) {
                Assert.areEqual(AuthorizationException.ACCESS_DENIED, e.code);
            }
        }
        System.runAs(TestDataFactory.getUser(OPS)) {
            try {
                service().verifyProofs(new List<Id>{ TestDataFactory.fakeId(Proof_of_Delivery__c.SObjectType, 1) });
                Assert.fail('Operations cannot verify proofs.');
            } catch (AuthorizationException e) {
                Assert.areEqual(AuthorizationException.ACCESS_DENIED, e.code);
            }
        }
    }

    @IsTest
    static void aManagerVerifiesADeliveredProofOnce() {
        Account c = customer();
        Vehicle__c vehicle = TestDataFactory.buildVehicle('TN-DS-V1', c.Business_Unit__c);
        Driver__c driver = TestDataFactory.buildDriver('DL-DS-V1', c.Business_Unit__c);
        insert vehicle;
        insert driver;
        Id managerId;
        Id verifiedProofId;
        System.runAs(TestDataFactory.getUser(MANAGER)) {
            Shipment__c shipment = TestDataFactory.deliveredShipment(c.Id, c.Business_Unit__c, vehicle.Id, driver.Id);
            Id proofId = [SELECT Id FROM Proof_of_Delivery__c WHERE Shipment__c = :shipment.Id].Id;

            Assert.isTrue(service().verifyProofs(new List<Id>{ proofId }).isSuccess);
            Assert.areEqual(UserInfo.getUserId(), [SELECT Verified_By__c FROM Proof_of_Delivery__c WHERE Id = :proofId].Verified_By__c);
            Assert.isTrue(service().verifyProofs(new List<Id>{ proofId }).isSuccess, 'Repeating the same verification changes nothing.');
            managerId = UserInfo.getUserId();
            verifiedProofId = proofId;
        }
        // Once verified, nobody else (here the running administrator) can re-verify in their name.
        ServiceResult other = service().verifyProofs(new List<Id>{ verifiedProofId });
        Assert.areEqual(Label.eLogix_Delivery_Pod_Verification, other.errors[0].message);
        Assert.areEqual(managerId, [SELECT Verified_By__c FROM Proof_of_Delivery__c WHERE Id = :verifiedProofId].Verified_By__c);
    }

    /* ---------------- D2: cancellation after dispatch ---------------- */

    @IsTest
    static void cancellationAfterDispatchClosesTheAttemptAndCompletesTheTrip() {
        Shipment__c shipment = inTransit(1)[0];
        System.runAs(TestDataFactory.getUser(OPS)) {
            service().startAttempts(new List<Id>{ shipment.Id });
            update new Shipment__c(Id = shipment.Id, Status__c = 'Delayed');
            update new Shipment__c(Id = shipment.Id, Status__c = 'On Hold', Hold_Reason__c = 'Customer dispute.');
        }
        // The running administrator holds eLogix_Cancel_Confirmed_Shipment.
        update new Shipment__c(Id = shipment.Id, Status__c = 'Cancelled', Cancellation_Reason__c = 'Order withdrawn after dispatch.');

        Delivery__c closed = attemptOf(shipment.Id, 1);
        Assert.areEqual('Failed', closed.Delivery_Status__c);
        Assert.areEqual('Other', closed.Failure_Reason__c);
        Assert.areEqual(Label.eLogix_Delivery_Cancelled_Notes, closed.Failure_Notes__c);
        Vehicle_Assignment__c trip = tripOf(shipment.Id);
        Assert.areEqual('Completed', trip.Status__c, 'The trip happened: Completed, not Cancelled.');
        Tracking_Event__c cancellation = [
            SELECT Remarks__c
            FROM Tracking_Event__c
            WHERE Shipment__c = :shipment.Id AND To_Status__c = 'Cancelled'
        ];
        Assert.isTrue(cancellation.Remarks__c.contains('Order withdrawn after dispatch.'));
        Assert.areEqual(1, [SELECT COUNT() FROM Delivery__c WHERE Shipment__c = :shipment.Id]);
        Assert.areEqual(0, [SELECT COUNT() FROM Delivery__c WHERE Shipment__c = :shipment.Id AND Delivery_Status__c IN ('Scheduled', 'Out for Delivery')]);
    }
}
