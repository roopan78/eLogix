/**
 * Audit round 3, issue 1: controlled recovery of a dispatched allocation. The Q9 lock stays the
 * default; only a user with eLogix_Correct_Dispatched_Allocation (and eLogix_Allocate_Fleet) can
 * correct the allocation, only while the shipment is On Hold, only with a new reason, always fully
 * revalidated, and always written to tracking history.
 */
@IsTest
private class FleetCorrectionTest {
    private static final String FLEET = 'Correction Fleet Tester';
    private static final String OPS = 'Correction Ops Tester';
    private static final String MANAGER = 'Correction LM Tester';
    private static final String RFD = 'Ready for Dispatch';
    private static Integer sequence = 0;

    @TestSetup
    static void setup() {
        Business_Unit__c businessUnit = TestDataFactory.createBusinessUnit('BU-CR');
        TestDataFactory.createCustomer('CUST-CR', businessUnit.Id);
        TestDataFactory.createUser(FLEET, TestDataFactory.FLEET);
        TestDataFactory.createUser(OPS, TestDataFactory.OPERATIONS);
        TestDataFactory.createUser(MANAGER, TestDataFactory.LOGISTICS_MANAGER);
    }

    /* ---------------- helpers ---------------- */

    private static Account customer() {
        return [SELECT Id, Business_Unit__c FROM Account WHERE Customer_Code__c = 'CUST-CR'];
    }

    private static List<Shipment__c> confirmed(Integer count) {
        List<Shipment__c> shipments;
        System.runAs(TestDataFactory.getUser(OPS)) {
            Account c = customer();
            shipments = TestDataFactory.confirmedShipments(count, c.Id, c.Business_Unit__c);
        }
        return shipments;
    }

    private static List<Vehicle__c> trucks(Integer count) {
        Id businessUnitId = customer().Business_Unit__c;
        List<Vehicle__c> records = new List<Vehicle__c>();
        for (Integer i = 0; i < count; i++) {
            records.add(TestDataFactory.buildVehicle('TN-CR-' + (++sequence), businessUnitId));
        }
        System.runAs(TestDataFactory.getUser(FLEET)) {
            insert records;
        }
        return records;
    }

    private static List<Driver__c> crew(Integer count) {
        Id businessUnitId = customer().Business_Unit__c;
        List<Driver__c> records = new List<Driver__c>();
        for (Integer i = 0; i < count; i++) {
            records.add(TestDataFactory.buildDriver('DL-CR-' + (++sequence), businessUnitId));
        }
        System.runAs(TestDataFactory.getUser(FLEET)) {
            insert records;
        }
        return records;
    }

    private static List<Id> allocateEach(List<Shipment__c> shipments, List<Vehicle__c> vehicles, List<Driver__c> drivers) {
        List<AllocationRequest> requests = new List<AllocationRequest>();
        for (Integer i = 0; i < shipments.size(); i++) {
            requests.add(new AllocationRequest(shipments[i].Id, vehicles[i].Id, drivers[i].Id));
        }
        ServiceResult result;
        System.runAs(TestDataFactory.getUser(FLEET)) {
            result = new FleetAllocationService().allocate(requests);
        }
        Assert.isTrue(result.isSuccess, String.valueOf(result.errors));
        return result.recordIds;
    }

    private static void walk(Id shipmentId, List<String> statuses) {
        for (String status : statuses) {
            Shipment__c change = new Shipment__c(Id = shipmentId, Status__c = status);
            if (status == 'On Hold') {
                change.Hold_Reason__c = 'Vehicle problem reported.';
            }
            Database.SaveResult result;
            System.runAs(TestDataFactory.getUser(OPS)) {
                result = Database.update(change, false);
            }
            Assert.isTrue(result.isSuccess(), 'Move to ' + status + ': ' + result.getErrors());
        }
    }

    /** Moves the shipments at the given positions to one status in a single save, as Operations. */
    private static void step(List<Shipment__c> shipments, List<Integer> positions, String status) {
        List<Shipment__c> changes = new List<Shipment__c>();
        for (Integer position : positions) {
            Shipment__c change = new Shipment__c(Id = shipments[position].Id, Status__c = status);
            if (status == 'On Hold') {
                change.Hold_Reason__c = 'Vehicle problem reported.';
            }
            changes.add(change);
        }
        List<Database.SaveResult> results;
        System.runAs(TestDataFactory.getUser(OPS)) {
            results = Database.update(changes, false);
        }
        for (Database.SaveResult result : results) {
            Assert.isTrue(result.isSuccess(), 'Move to ' + status + ': ' + result.getErrors());
        }
    }

    private static ServiceResult correct(String userName, Id shipmentId, Id vehicleId, Id driverId, String reason) {
        AllocationRequest request = new AllocationRequest(shipmentId, vehicleId, driverId);
        request.correctionReason = reason;
        ServiceResult result;
        System.runAs(TestDataFactory.getUser(userName)) {
            result = new FleetAllocationService().correctDispatchedAllocation(new List<AllocationRequest>{ request });
        }
        return result;
    }

    private static Vehicle_Assignment__c reload(Id assignmentId) {
        return [
            SELECT Name, Status__c, Vehicle__c, Driver__c, Correction_Reason__c, Assignment_End__c
            FROM Vehicle_Assignment__c
            WHERE Id = :assignmentId
        ];
    }

    private static List<Tracking_Event__c> corrections(Id shipmentId) {
        return [
            SELECT Remarks__c, Source__c, CreatedById
            FROM Tracking_Event__c
            WHERE Shipment__c = :shipmentId AND Event_Type__c = :VehicleAssignmentDomain.CORRECTION_EVENT_TYPE AND To_Status__c = NULL
        ];
    }

    /* ---------------- the recovery path ---------------- */

    @IsTest
    static void aManagerCorrectsAnOnHoldDispatchedAllocationWithHistory() {
        Shipment__c shipment = confirmed(1)[0];
        List<Vehicle__c> vehicles = trucks(2);
        List<Driver__c> drivers = crew(2);
        Id assignmentId = allocateEach(new List<Shipment__c>{ shipment }, vehicles, drivers)[0];
        walk(shipment.Id, new List<String>{ RFD, 'On Hold' });
        String reason = 'Truck broke down at the Chennai depot.';

        ServiceResult result = correct(MANAGER, shipment.Id, vehicles[1].Id, drivers[1].Id, reason);

        Assert.isTrue(result.isSuccess, String.valueOf(result.errors));
        Vehicle_Assignment__c corrected = reload(assignmentId);
        Assert.areEqual('Planned', corrected.Status__c);
        Assert.areEqual(vehicles[1].Id, corrected.Vehicle__c);
        Assert.areEqual(drivers[1].Id, corrected.Driver__c);
        Assert.areEqual(reason, corrected.Correction_Reason__c);
        Shipment__c mirrored = [SELECT Vehicle__c, Driver__c FROM Shipment__c WHERE Id = :shipment.Id];
        Assert.areEqual(vehicles[1].Id, mirrored.Vehicle__c);
        Assert.areEqual(drivers[1].Id, mirrored.Driver__c);

        List<Tracking_Event__c> history = corrections(shipment.Id);
        Assert.areEqual(1, history.size(), 'Exactly one correction event.');
        String remarks = history[0].Remarks__c;
        for (String expected : new List<String>{ corrected.Name, reason, vehicles[0].Vehicle_Number__c, vehicles[1].Vehicle_Number__c, drivers[1].Name }) {
            Assert.isTrue(remarks.contains(expected), 'Remarks must identify the correction: ' + expected + ' in ' + remarks);
        }
        Assert.areEqual(TrackingService.SOURCE_APEX, history[0].Source__c);
        Assert.areEqual(TestDataFactory.getUser(MANAGER).Id, history[0].CreatedById, 'The correcting user is recorded.');

        walk(shipment.Id, new List<String>{ RFD }); // the corrected allocation passes the guard
    }

    @IsTest
    static void correctionNeedsThePermissionAReasonAndANewReason() {
        Shipment__c shipment = confirmed(1)[0];
        List<Vehicle__c> vehicles = trucks(3);
        List<Driver__c> drivers = crew(1);
        Id assignmentId = allocateEach(new List<Shipment__c>{ shipment }, vehicles, drivers)[0];
        walk(shipment.Id, new List<String>{ RFD, 'On Hold' });

        // The Fleet Manager allocates but cannot correct: service and direct DML.
        try {
            correct(FLEET, shipment.Id, vehicles[1].Id, drivers[0].Id, 'Trying.');
            Assert.fail('The service requires the correction permission.');
        } catch (AuthorizationException e) {
            Assert.areEqual(AuthorizationException.ACCESS_DENIED, e.code);
        }
        System.runAs(TestDataFactory.getUser(FLEET)) {
            Assert.isFalse(
                Database.update(new Vehicle_Assignment__c(Id = assignmentId, Vehicle__c = vehicles[1].Id, Correction_Reason__c = 'Trying.'), false).isSuccess()
            );
        }

        // A reason is required, and must be new.
        Assert.areEqual(FleetAllocationService.CORRECTION_REASON_REQUIRED, correct(MANAGER, shipment.Id, vehicles[1].Id, drivers[0].Id, '  ').errors[0].code);
        Assert.isTrue(correct(MANAGER, shipment.Id, vehicles[1].Id, drivers[0].Id, 'First breakdown.').isSuccess);
        Assert.areEqual(FleetAllocationService.CORRECTION_REASON_REQUIRED, correct(MANAGER, shipment.Id, vehicles[2].Id, drivers[0].Id, 'First breakdown.').errors[0].code);

        // Without a reason, an authorised user is still held by the Q9 lock; a release is never a correction.
        String name = [SELECT Name FROM Shipment__c WHERE Id = :shipment.Id].Name;
        System.runAs(TestDataFactory.getUser(MANAGER)) {
            Database.SaveResult unexplained = Database.update(new Vehicle_Assignment__c(Id = assignmentId, Vehicle__c = vehicles[2].Id), false);
            Assert.areEqual(String.format(Label.eLogix_Fleet_Locked_After_Dispatch, new List<Object>{ name }), unexplained.getErrors()[0].getMessage());
            Database.SaveResult release = Database.update(new Vehicle_Assignment__c(Id = assignmentId, Status__c = 'Cancelled', Correction_Reason__c = 'Release it.'), false);
            Assert.areEqual(Label.eLogix_Fleet_Correction_Not_Allowed, release.getErrors()[0].getMessage());
        }

        Vehicle_Assignment__c kept = reload(assignmentId);
        Assert.areEqual(vehicles[1].Id, kept.Vehicle__c, 'Only the one valid correction applied.');
        Assert.areEqual('Planned', kept.Status__c);
        Assert.areEqual(1, corrections(shipment.Id).size());
    }

    @IsTest
    static void correctionIsOnlyAllowedOnHold() {
        List<Shipment__c> shipments = confirmed(6);
        List<Vehicle__c> vehicles = trucks(7);
        List<Driver__c> drivers = crew(6);
        allocateEach(shipments, vehicles, drivers);
        // One save per step, in bulk. End states: 0 Ready for Dispatch, 1 Dispatched, 2 In Transit,
        // 3 Delayed, 4 Failed Delivery, 5 Confirmed again after Ready for Dispatch and On Hold.
        step(shipments, new List<Integer>{ 0, 1, 2, 3, 4, 5 }, RFD);
        step(shipments, new List<Integer>{ 1, 2, 3, 4 }, 'Dispatched');
        step(shipments, new List<Integer>{ 5 }, 'On Hold');
        step(shipments, new List<Integer>{ 2, 3, 4 }, 'In Transit');
        step(shipments, new List<Integer>{ 5 }, 'Confirmed');
        step(shipments, new List<Integer>{ 3 }, 'Delayed');
        // Phase 5: Out for Delivery and Failed Delivery go through a delivery attempt.
        System.runAs(TestDataFactory.getUser(OPS)) {
            DeliveryService deliveries = new DeliveryService();
            Assert.isTrue(deliveries.startAttempts(new List<Id>{ shipments[4].Id }).isSuccess);
            Assert.isTrue(
                deliveries.recordFailures(new List<DeliveryFailureRequest>{ new DeliveryFailureRequest(shipments[4].Id, 'Consignee Unavailable') }).isSuccess
            );
        }

        Test.startTest();
        for (Integer i = 0; i < 6; i++) {
            ServiceResult result = correct(MANAGER, shipments[i].Id, vehicles[6].Id, drivers[i].Id, 'Replacement truck ' + i + '.');
            Assert.isFalse(result.isSuccess, 'Shipment ' + i + ' is not On Hold.');
        }
        Assert.areEqual(Label.eLogix_Fleet_Correction_Not_Allowed, correct(MANAGER, shipments[5].Id, vehicles[6].Id, drivers[5].Id, 'Again.').errors[0].message);
        Test.stopTest();
        Assert.areEqual(0, [SELECT COUNT() FROM Vehicle_Assignment__c WHERE Vehicle__c = :vehicles[6].Id]);
        Assert.areEqual(0, [SELECT COUNT() FROM Tracking_Event__c WHERE Event_Type__c = :VehicleAssignmentDomain.CORRECTION_EVENT_TYPE AND To_Status__c = NULL]);
    }

    @IsTest
    static void aCorrectionIsRevalidatedInFullAndCanRenewTheWindow() {
        Shipment__c shipment = confirmed(1)[0];
        List<Vehicle__c> vehicles = trucks(2);
        List<Driver__c> drivers = crew(1);
        Id assignmentId = allocateEach(new List<Shipment__c>{ shipment }, vehicles, drivers)[0];
        walk(shipment.Id, new List<String>{ RFD, 'On Hold' });

        // An ineligible replacement is refused like any allocation.
        update new Vehicle__c(Id = vehicles[1].Id, Insurance_Expiry__c = Date.today().addDays(2));
        ServiceResult refused = correct(MANAGER, shipment.Id, vehicles[1].Id, drivers[0].Id, 'Swap to the spare truck.');
        Assert.isTrue(refused.errors[0].message.contains('must be on or after'), refused.errors[0].message);
        Assert.areEqual(vehicles[0].Id, reload(assignmentId).Vehicle__c);

        // The delivery date moves while On Hold: the stale booking is refused, and a correction with the
        // same vehicle and driver renews it.
        Date newDelivery = Date.today().addDays(5);
        update new Shipment__c(Id = shipment.Id, Expected_Delivery_Date__c = newDelivery);
        Database.SaveResult stale;
        System.runAs(TestDataFactory.getUser(OPS)) {
            stale = Database.update(new Shipment__c(Id = shipment.Id, Status__c = RFD), false);
        }
        Assert.isTrue(stale.getErrors()[0].getMessage().contains('changed after its vehicle was allocated'));

        ServiceResult renewed = correct(MANAGER, shipment.Id, vehicles[0].Id, drivers[0].Id, 'Customer moved the delivery date.');
        Assert.isTrue(renewed.isSuccess, String.valueOf(renewed.errors));
        Assert.areEqual(AssignmentWindow.endOf(newDelivery), reload(assignmentId).Assignment_End__c);
        walk(shipment.Id, new List<String>{ RFD });
    }

    @IsTest
    static void aCorrectionThatCannotBeRecordedIsNotSaved() {
        Shipment__c shipment = confirmed(1)[0];
        List<Vehicle__c> vehicles = trucks(2);
        List<Driver__c> drivers = crew(1);
        Id assignmentId = allocateEach(new List<Shipment__c>{ shipment }, vehicles, drivers)[0];
        walk(shipment.Id, new List<String>{ RFD, 'On Hold' });

        // A Fleet Manager forced to hold the correction permission still cannot create tracking
        // events (or edit the protected reason field): the correction must not be saved unrecorded.
        PermissionService.testOverrides.put(VehicleAssignmentDomain.CORRECT_PERMISSION, true);
        Database.SaveResult result;
        System.runAs(TestDataFactory.getUser(FLEET)) {
            result = Database.update(new Vehicle_Assignment__c(Id = assignmentId, Vehicle__c = vehicles[1].Id, Correction_Reason__c = 'Unrecorded.'), false);
        }

        Assert.isFalse(result.isSuccess());
        Assert.areEqual(vehicles[0].Id, reload(assignmentId).Vehicle__c);
        Assert.areEqual(0, corrections(shipment.Id).size());
    }

    @IsTest
    static void aFirstAllocationCannotCarryACorrectionReason() {
        Shipment__c shipment = confirmed(1)[0];
        Vehicle_Assignment__c assignment = new Vehicle_Assignment__c(
            Shipment__c = shipment.Id,
            Vehicle__c = trucks(1)[0].Id,
            Driver__c = crew(1)[0].Id,
            Status__c = 'Planned',
            Assignment_Start__c = System.now(),
            Correction_Reason__c = 'Not a correction.'
        );
        Database.SaveResult result;
        System.runAs(TestDataFactory.getUser(MANAGER)) {
            result = Database.insert(assignment, false);
        }
        Assert.areEqual(Label.eLogix_Fleet_Correction_Not_Allowed, result.getErrors()[0].getMessage());
    }

    @IsTest
    static void correctionHistoryOnlyRunsInItsTrigger() {
        try {
            new VehicleAssignmentDomain().recordCorrections();
            Assert.fail('Expected a refusal.');
        } catch (AuthorizationException e) {
            Assert.areEqual(VehicleAssignmentDomain.CORRECTION_TRIGGER_ONLY, e.code);
        }
    }
}
