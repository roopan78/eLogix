/**
 * Phase 4 audit fixes 2 and 3: the allocation stays locked once a shipment has ever reached Ready for
 * Dispatch (Q9, decided from tracking history, not the current status), and Ready for Dispatch
 * revalidates the allocation against current data (Q10), excluding the assignment itself.
 */
@IsTest
private class FleetDispatchRulesTest {
    private static final String FLEET = 'Dispatch Fleet Tester';
    private static final String OPS = 'Dispatch Ops Tester';
    private static final String RFD = 'Ready for Dispatch';
    private static Integer sequence = 0;

    @TestSetup
    static void setup() {
        Business_Unit__c businessUnit = TestDataFactory.createBusinessUnit('BU-DR');
        TestDataFactory.createBusinessUnit('BU-DR2');
        TestDataFactory.createCustomer('CUST-DR', businessUnit.Id);
        TestDataFactory.createUser(FLEET, TestDataFactory.FLEET);
        TestDataFactory.createUser(OPS, TestDataFactory.OPERATIONS);
    }

    /* ---------------- helpers ---------------- */

    private static Account customer() {
        return [SELECT Id, Business_Unit__c FROM Account WHERE Customer_Code__c = 'CUST-DR'];
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
            records.add(TestDataFactory.buildVehicle('TN-DR-' + (++sequence), businessUnitId));
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
            records.add(TestDataFactory.buildDriver('DL-DR-' + (++sequence), businessUnitId));
        }
        System.runAs(TestDataFactory.getUser(FLEET)) {
            insert records;
        }
        return records;
    }

    /** One fresh vehicle and driver per shipment; returns the assignment Ids in shipment order. */
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

    private static String move(Id shipmentId, String status) {
        Shipment__c change = new Shipment__c(Id = shipmentId, Status__c = status);
        if (status == 'On Hold') {
            change.Hold_Reason__c = 'Customer asked to wait.';
        }
        Database.SaveResult result;
        System.runAs(TestDataFactory.getUser(OPS)) {
            result = Database.update(change, false);
        }
        return result.isSuccess() ? null : result.getErrors()[0].getMessage();
    }

    private static void walk(Id shipmentId, List<String> statuses) {
        for (String status : statuses) {
            String error = move(shipmentId, status);
            Assert.isNull(error, 'Move to ' + status + ': ' + error);
        }
    }

    private static ServiceResult reallocate(Id shipmentId, Id vehicleId, Id driverId) {
        ServiceResult result;
        System.runAs(TestDataFactory.getUser(FLEET)) {
            result = new FleetAllocationService().reallocate(new List<AllocationRequest>{ new AllocationRequest(shipmentId, vehicleId, driverId) });
        }
        return result;
    }

    private static ServiceResult release(Id assignmentId) {
        ServiceResult result;
        System.runAs(TestDataFactory.getUser(FLEET)) {
            result = new FleetAllocationService().release(new List<Id>{ assignmentId });
        }
        return result;
    }

    private static String lockedMessage(Id shipmentId) {
        String name = [SELECT Name FROM Shipment__c WHERE Id = :shipmentId].Name;
        return String.format(Label.eLogix_Fleet_Locked_After_Dispatch, new List<Object>{ name });
    }

    /* ---------------- Q9: locked after the first Ready for Dispatch ---------------- */

    @IsTest
    static void readyForDispatchThenOnHoldKeepsTheAllocation() {
        Shipment__c shipment = confirmed(1)[0];
        List<Vehicle__c> vehicles = trucks(2);
        List<Driver__c> drivers = crew(2);
        Id assignmentId = allocateEach(new List<Shipment__c>{ shipment }, vehicles, drivers)[0];
        walk(shipment.Id, new List<String>{ RFD, 'On Hold' });

        ServiceResult moved = reallocate(shipment.Id, vehicles[1].Id, drivers[0].Id);
        ServiceResult released = release(assignmentId);
        Database.SaveResult direct;
        System.runAs(TestDataFactory.getUser(FLEET)) {
            direct = Database.update(new Vehicle_Assignment__c(Id = assignmentId, Driver__c = drivers[1].Id), false);
        }

        String expected = lockedMessage(shipment.Id);
        Assert.areEqual(expected, moved.errors[0].message, 'Service reallocation.');
        Assert.areEqual(expected, released.errors[0].message, 'Service release.');
        Assert.areEqual(expected, direct.getErrors()[0].getMessage(), 'Direct DML.');

        // Returning to Confirmed does not reset the restriction either.
        walk(shipment.Id, new List<String>{ 'Confirmed' });
        Assert.areEqual(expected, reallocate(shipment.Id, vehicles[1].Id, drivers[0].Id).errors[0].message);

        Vehicle_Assignment__c kept = [SELECT Status__c, Vehicle__c, Driver__c FROM Vehicle_Assignment__c WHERE Id = :assignmentId];
        Assert.areEqual('Planned', kept.Status__c);
        Assert.areEqual(vehicles[0].Id, kept.Vehicle__c);
        Assert.areEqual(drivers[0].Id, kept.Driver__c);
    }

    @IsTest
    static void dispatchedOrInTransitThenOnHoldKeepsTheAllocation() {
        List<Shipment__c> shipments = confirmed(2);
        List<Vehicle__c> vehicles = trucks(3);
        List<Driver__c> drivers = crew(2);
        allocateEach(shipments, vehicles, drivers);
        walk(shipments[0].Id, new List<String>{ RFD, 'Dispatched', 'In Transit', 'On Hold' });
        // The configured On Hold -> In Transit transition skips Ready for Dispatch entirely; the
        // In Transit event still locks the allocation.
        walk(shipments[1].Id, new List<String>{ 'On Hold', 'In Transit', 'On Hold' });

        // Phase 5: once on the road (Dispatched or In Transit) the trip is Active, so there is no
        // Planned assignment left to reallocate or release, and the Active one is frozen.
        for (Integer i = 0; i < 2; i++) {
            ServiceResult moved = reallocate(shipments[i].Id, vehicles[2].Id, drivers[i].Id);
            Assert.areEqual(FleetAllocationService.NO_OPEN_ASSIGNMENT, moved.errors[0].code);
        }
        Assert.areEqual(2, [SELECT COUNT() FROM Vehicle_Assignment__c WHERE Status__c = 'Active' AND Vehicle__c != :vehicles[2].Id]);
    }

    @IsTest
    static void onHoldBeforeDispatchStillAllowsChanges() {
        Shipment__c shipment = confirmed(1)[0];
        List<Vehicle__c> vehicles = trucks(2);
        List<Driver__c> drivers = crew(1);
        Id assignmentId = allocateEach(new List<Shipment__c>{ shipment }, vehicles, drivers)[0];
        walk(shipment.Id, new List<String>{ 'On Hold' });

        ServiceResult moved = reallocate(shipment.Id, vehicles[1].Id, drivers[0].Id);
        Assert.isTrue(moved.isSuccess, String.valueOf(moved.errors));
        Assert.areEqual(vehicles[1].Id, [SELECT Vehicle__c FROM Shipment__c WHERE Id = :shipment.Id].Vehicle__c);

        ServiceResult released = release(assignmentId);
        Assert.isTrue(released.isSuccess, String.valueOf(released.errors));
        Assert.isNull([SELECT Vehicle__c FROM Shipment__c WHERE Id = :shipment.Id].Vehicle__c);
    }

    @IsTest
    static void cancellationStillReleasesAfterDispatch() {
        Shipment__c shipment = confirmed(1)[0];
        Id assignmentId = allocateEach(new List<Shipment__c>{ shipment }, trucks(1), crew(1))[0];
        walk(shipment.Id, new List<String>{ RFD, 'On Hold' });

        // An administrator holds eLogix_Cancel_Confirmed_Shipment.
        update new Shipment__c(Id = shipment.Id, Status__c = 'Cancelled', Cancellation_Reason__c = 'Order withdrawn.');

        Assert.areEqual('Cancelled', [SELECT Status__c FROM Vehicle_Assignment__c WHERE Id = :assignmentId].Status__c);
        Shipment__c saved = [SELECT Vehicle__c, Driver__c FROM Shipment__c WHERE Id = :shipment.Id];
        Assert.isNull(saved.Vehicle__c);
        Assert.isNull(saved.Driver__c);
    }

    /* ---------------- Q10: Ready for Dispatch revalidates the allocation ---------------- */

    @IsTest
    static void readyForDispatchRevalidatesAgainstCurrentData() {
        List<Shipment__c> shipments = confirmed(10);
        List<Vehicle__c> vehicles = trucks(10);
        List<Driver__c> drivers = crew(10);
        List<Id> assignmentIds = allocateEach(shipments, vehicles, drivers);
        Id otherUnit = [SELECT Id FROM Business_Unit__c WHERE Business_Unit_Code__c = 'BU-DR2'].Id;

        // After allocation, each shipment except the first is made ineligible in one way.
        update new List<Shipment__c>{
            new Shipment__c(Id = shipments[1].Id, Weight__c = 1500),
            new Shipment__c(Id = shipments[2].Id, Business_Unit__c = otherUnit),
            new Shipment__c(Id = shipments[9].Id, Expected_Delivery_Date__c = Date.today().addDays(5))
        };
        update new List<Vehicle__c>{
            new Vehicle__c(Id = vehicles[3].Id, Capacity__c = 400),
            new Vehicle__c(Id = vehicles[4].Id, Status__c = 'Inactive'),
            new Vehicle__c(Id = vehicles[5].Id, Insurance_Expiry__c = Date.today().addDays(2))
        };
        update new List<Driver__c>{
            new Driver__c(Id = drivers[6].Id, License_Expiry__c = Date.today().addDays(1)),
            new Driver__c(Id = drivers[7].Id, Status__c = 'On Leave')
        };
        insert new Vehicle_Maintenance__c(
            Vehicle__c = vehicles[8].Id,
            Maintenance_Type__c = 'Preventive',
            Scheduled_Date__c = Date.today().addDays(2),
            Status__c = 'Scheduled'
        );

        List<Shipment__c> moves = new List<Shipment__c>();
        for (Shipment__c shipment : shipments) {
            moves.add(new Shipment__c(Id = shipment.Id, Status__c = RFD));
        }
        List<Database.SaveResult> results;
        System.runAs(TestDataFactory.getUser(OPS)) {
            results = Database.update(moves, false);
        }

        Assert.isTrue(results[0].isSuccess(), 'The unchanged allocation proceeds: ' + results[0].getErrors());
        String prefix = Label.eLogix_Fleet_Allocation_Invalid.substringBefore('{0}');
        Map<Integer, String> expected = new Map<Integer, String>{
            1 => 'carries up to',
            2 => 'same business unit',
            3 => 'carries up to',
            4 => 'is inactive',
            5 => 'must be on or after',
            6 => 'licence must be valid',
            7 => 'is On Leave',
            8 => 'maintenance in progress or scheduled'
        };
        for (Integer i : expected.keySet()) {
            Assert.isFalse(results[i].isSuccess(), 'Shipment ' + i + ' must be refused.');
            String message = results[i].getErrors()[0].getMessage();
            Assert.isTrue(message.startsWith(prefix) && message.contains(expected.get(i)), i + ': ' + message);
        }
        String name9 = [SELECT Name FROM Shipment__c WHERE Id = :shipments[9].Id].Name;
        Assert.areEqual(String.format(Label.eLogix_Fleet_Window_Changed, new List<Object>{ name9 }), results[9].getErrors()[0].getMessage());

        // Validation only: no assignment was written.
        Assert.areEqual(
            10,
            [SELECT COUNT() FROM Vehicle_Assignment__c WHERE Id IN :assignmentIds AND Status__c = 'Planned' AND Vehicle__c IN :vehicles]
        );
        Assert.areEqual(9, [SELECT COUNT() FROM Shipment__c WHERE Id IN :shipments AND Status__c = 'Confirmed']);
    }

    /** The assignment being checked never conflicts with itself, nor with a later booking of the same pair. */
    @IsTest
    static void aValidAllocationIsNotRejectedByItself() {
        List<Shipment__c> shipments = confirmed(2);
        update new Shipment__c(Id = shipments[1].Id, Pickup_Date__c = Date.today().addDays(4), Expected_Delivery_Date__c = Date.today().addDays(6));
        Vehicle__c truck = trucks(1)[0];
        Driver__c driver = crew(1)[0];
        allocateEach(shipments, new List<Vehicle__c>{ truck, truck }, new List<Driver__c>{ driver, driver });

        Assert.isNull(move(shipments[0].Id, RFD));
        Assert.isNull(move(shipments[1].Id, RFD));
    }

    @IsTest
    static void reallocatingRenewsAStaleWindow() {
        Shipment__c shipment = confirmed(1)[0];
        Vehicle__c truck = trucks(1)[0];
        Driver__c driver = crew(1)[0];
        Id assignmentId = allocateEach(new List<Shipment__c>{ shipment }, new List<Vehicle__c>{ truck }, new List<Driver__c>{ driver })[0];
        Date newDelivery = Date.today().addDays(4);
        update new Shipment__c(Id = shipment.Id, Expected_Delivery_Date__c = newDelivery);

        Assert.isTrue(move(shipment.Id, RFD).contains('changed after its vehicle was allocated'));
        ServiceResult renewed = reallocate(shipment.Id, truck.Id, driver.Id);
        Assert.isTrue(renewed.isSuccess, String.valueOf(renewed.errors));
        Assert.areEqual(AssignmentWindow.endOf(newDelivery), [SELECT Assignment_End__c FROM Vehicle_Assignment__c WHERE Id = :assignmentId].Assignment_End__c);
        Assert.isNull(move(shipment.Id, RFD));
    }

    /* ---------------- round 3, issue 2: In Transit needs a valid allocation ---------------- */

    /** The configured On Hold -> In Transit transition skips Ready for Dispatch; the guard covers it. */
    @IsTest
    static void onHoldToInTransitNeedsAValidMatchingAllocation() {
        List<Shipment__c> shipments = confirmed(4);
        List<Vehicle__c> vehicles = trucks(4);
        List<Driver__c> drivers = crew(3);
        // 0: no assignment. 1: valid. 2: vehicle made inactive afterwards. 3: shipment points elsewhere.
        allocateEach(
            new List<Shipment__c>{ shipments[1], shipments[2], shipments[3] },
            new List<Vehicle__c>{ vehicles[1], vehicles[2], vehicles[3] },
            drivers
        );
        update new Vehicle__c(Id = vehicles[2].Id, Status__c = 'Inactive');
        update new Shipment__c(Id = shipments[3].Id, Vehicle__c = vehicles[0].Id); // an administrator edits the mirror
        for (Shipment__c shipment : shipments) {
            walk(shipment.Id, new List<String>{ 'On Hold' });
        }

        List<Shipment__c> moves = new List<Shipment__c>();
        for (Shipment__c shipment : shipments) {
            moves.add(new Shipment__c(Id = shipment.Id, Status__c = 'In Transit'));
        }
        List<Database.SaveResult> results;
        System.runAs(TestDataFactory.getUser(OPS)) {
            results = Database.update(moves, false);
        }

        Assert.areEqual(Label.eLogix_Fleet_Allocation_Required, results[0].getErrors()[0].getMessage(), 'No assignment.');
        Assert.isTrue(results[1].isSuccess(), 'A valid allocation proceeds: ' + results[1].getErrors());
        String invalid = results[2].getErrors()[0].getMessage();
        Assert.isTrue(
            invalid.startsWith(Label.eLogix_Fleet_Allocation_Invalid.substringBefore('{0}')) && invalid.contains('is inactive'),
            invalid
        );
        Assert.areEqual(Label.eLogix_Fleet_Allocation_Required, results[3].getErrors()[0].getMessage(), 'Mismatched assignment.');
        Assert.areEqual(3, [SELECT COUNT() FROM Shipment__c WHERE Id IN :shipments AND Status__c = 'On Hold']);
    }

    @IsTest
    static void dispatchedToInTransitIsRevalidatedToo() {
        Shipment__c shipment = confirmed(1)[0];
        Driver__c driver = crew(1)[0];
        allocateEach(new List<Shipment__c>{ shipment }, trucks(1), new List<Driver__c>{ driver });
        walk(shipment.Id, new List<String>{ RFD, 'Dispatched' });
        update new Driver__c(Id = driver.Id, Status__c = 'On Leave');

        String refused = move(shipment.Id, 'In Transit');
        Assert.isTrue(refused != null && refused.contains('is On Leave'), refused);

        update new Driver__c(Id = driver.Id, Status__c = 'Available');
        Assert.isNull(move(shipment.Id, 'In Transit'));
    }

    /** Outside the shipment trigger the guard cannot verify an allocation, so it fails closed. */
    @IsTest
    static void theGuardFailsClosedOutsideTheShipmentTrigger() {
        Shipment__c record = TestDataFactory.shipmentInMemory(TestDataFactory.fakeId(Shipment__c.SObjectType, 1), RFD, 1);
        Map<Integer, ShipmentStatusPolicy.Violation> violations = new ShipmentAllocationGuard()
            .check(new List<ShipmentStatusPolicy.StatusChange>{ new ShipmentStatusPolicy.StatusChange(0, record, 'Confirmed', RFD) });
        Assert.areEqual(ShipmentAllocationGuard.ALLOCATION_REQUIRED, violations.get(0).code);
    }
}
