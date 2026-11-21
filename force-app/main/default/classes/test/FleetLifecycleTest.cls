/**
 * Phase 5 assignment lifecycle: activation only through dispatch, completion only when the trip ends,
 * revalidation at Dispatched, Active trips holding their truck and driver until completed (D3), and
 * lock timeouts at the new lock points.
 */
@IsTest
private class FleetLifecycleTest {
    private static final String OPS = 'Lifecycle Ops Tester';
    private static final String FLEET = 'Lifecycle Fleet Tester';
    private static final String LOCK_TIMEOUT = 'Record Currently Unavailable: UNABLE_TO_LOCK_ROW';
    private static Integer sequence = 0;

    @TestSetup
    static void setup() {
        Business_Unit__c businessUnit = TestDataFactory.createBusinessUnit('BU-LC');
        TestDataFactory.createCustomer('CUST-LC', businessUnit.Id);
        TestDataFactory.createUser(OPS, TestDataFactory.OPERATIONS);
        TestDataFactory.createUser(FLEET, TestDataFactory.FLEET);
    }

    private static Account customer() {
        return [SELECT Id, Business_Unit__c FROM Account WHERE Customer_Code__c = 'CUST-LC'];
    }

    private static List<Shipment__c> confirmed(Integer count) {
        Account c = customer();
        List<Shipment__c> records;
        System.runAs(TestDataFactory.getUser(OPS)) {
            records = TestDataFactory.confirmedShipments(count, c.Id, c.Business_Unit__c);
        }
        return records;
    }

    private static Vehicle__c truck() {
        Vehicle__c record = TestDataFactory.buildVehicle('TN-LC-' + (++sequence), customer().Business_Unit__c);
        System.runAs(TestDataFactory.getUser(FLEET)) {
            insert record;
        }
        return record;
    }

    private static Driver__c driver() {
        Driver__c record = TestDataFactory.buildDriver('DL-LC-' + (++sequence), customer().Business_Unit__c);
        System.runAs(TestDataFactory.getUser(FLEET)) {
            insert record;
        }
        return record;
    }

    private static ServiceResult allocate(Id shipmentId, Id vehicleId, Id driverId) {
        ServiceResult result;
        System.runAs(TestDataFactory.getUser(FLEET)) {
            result = new FleetAllocationService().allocate(new List<AllocationRequest>{ new AllocationRequest(shipmentId, vehicleId, driverId) });
        }
        return result;
    }

    private static String move(Id shipmentId, String status) {
        Shipment__c change = new Shipment__c(Id = shipmentId, Status__c = status);
        if (status == 'On Hold') {
            change.Hold_Reason__c = 'Waiting for the customer.';
        }
        Database.SaveResult result;
        System.runAs(TestDataFactory.getUser(OPS)) {
            result = Database.update(change, false);
        }
        return result.isSuccess() ? null : result.getErrors()[0].getMessage();
    }

    private static String tripStatus(Id shipmentId) {
        return [SELECT Status__c FROM Vehicle_Assignment__c WHERE Shipment__c = :shipmentId].Status__c;
    }

    @IsTest
    static void dispatchRevalidatesAndActivatesTheTrip() {
        Shipment__c shipment = confirmed(1)[0];
        Vehicle__c vehicle = truck();
        allocate(shipment.Id, vehicle.Id, driver().Id);
        Assert.isNull(move(shipment.Id, 'Ready for Dispatch'));
        update new Vehicle__c(Id = vehicle.Id, Status__c = 'Inactive');

        String refused = move(shipment.Id, 'Dispatched');
        Assert.isTrue(refused != null && refused.contains('is inactive'), refused);
        Assert.areEqual('Planned', tripStatus(shipment.Id));

        update new Vehicle__c(Id = vehicle.Id, Status__c = 'Available');
        Assert.isNull(move(shipment.Id, 'Dispatched'));
        Assert.areEqual('Active', tripStatus(shipment.Id));
    }

    @IsTest
    static void theOnHoldToInTransitRouteActivatesAndDamagedCompletes() {
        Shipment__c shipment = confirmed(1)[0];
        allocate(shipment.Id, truck().Id, driver().Id);
        Assert.isNull(move(shipment.Id, 'On Hold'));
        Assert.isNull(move(shipment.Id, 'In Transit'));
        Assert.areEqual('Active', tripStatus(shipment.Id));
        Assert.isNull(move(shipment.Id, 'Damaged'));
        Assert.areEqual('Completed', tripStatus(shipment.Id));
    }

    /** D3: an Active trip blocks its truck and driver beyond its planned window, until completed. */
    @IsTest
    static void anActiveTripHoldsItsTruckUntilCompleted() {
        List<Shipment__c> shipments = confirmed(2);
        // The second shipment starts after the first one's planned window ends.
        System.runAs(TestDataFactory.getUser(OPS)) {
            update new Shipment__c(Id = shipments[1].Id, Pickup_Date__c = Date.today().addDays(6), Expected_Delivery_Date__c = Date.today().addDays(8));
        }
        Vehicle__c vehicle = truck();
        Driver__c person = driver();
        Driver__c relief = driver();
        allocate(shipments[0].Id, vehicle.Id, person.Id);
        Assert.isNull(move(shipments[0].Id, 'Ready for Dispatch'));
        Assert.isNull(move(shipments[0].Id, 'Dispatched'));

        ServiceResult blocked = allocate(shipments[1].Id, vehicle.Id, relief.Id);
        Assert.isTrue(blocked.errors[0].message.contains('already has an assignment that overlaps'), blocked.errors[0].message);

        // A delay that moves the delivery date does not make the Active trip stale (D3).
        Assert.isNull(move(shipments[0].Id, 'Delayed'));
        update new Shipment__c(Id = shipments[0].Id, Expected_Delivery_Date__c = Date.today().addDays(10));
        Assert.isNull(move(shipments[0].Id, 'In Transit'));

        Assert.isNull(move(shipments[0].Id, 'Lost'));
        Assert.areEqual('Completed', tripStatus(shipments[0].Id));
        Assert.isTrue(allocate(shipments[1].Id, vehicle.Id, relief.Id).isSuccess, 'Free again once the trip is completed.');
    }

    /* ---------------- lock timeouts at the Phase 5 lock points ---------------- */

    private class TimeoutFleetSelector extends FleetSelector {
        public override List<Vehicle_Assignment__c> lockOpenAssignmentsOfShipments(Set<Id> ids) {
            throw new QueryException(LOCK_TIMEOUT);
        }
    }

    private class TimeoutDeliverySelector extends DeliverySelector {
        public override Map<Id, Shipment__c> shipmentsForDelivery(Set<Id> ids) {
            throw new QueryException(LOCK_TIMEOUT);
        }

        public override Map<Id, Shipment__c> lockShipmentsForAttempts(Set<Id> ids) {
            throw new QueryException(LOCK_TIMEOUT);
        }
    }

    @IsTest
    static void lockTimeoutsAreRetryableAndSaveNothing() {
        Shipment__c shipment = confirmed(1)[0];
        allocate(shipment.Id, truck().Id, driver().Id);
        Assert.isNull(move(shipment.Id, 'Ready for Dispatch'));

        FleetAllocationService.selector = new TimeoutFleetSelector();
        Assert.areEqual(Label.eLogix_Fleet_Busy, move(shipment.Id, 'Dispatched'));
        Assert.areEqual('Planned', tripStatus(shipment.Id));
        FleetAllocationService.selector = new FleetSelector();
        Assert.isNull(move(shipment.Id, 'Dispatched'));
        Assert.isNull(move(shipment.Id, 'In Transit'));

        DeliveryService.selector = new TimeoutDeliverySelector();
        System.runAs(TestDataFactory.getUser(OPS)) {
            ServiceResult busy = new DeliveryService().startAttempts(new List<Id>{ shipment.Id });
            Assert.areEqual(DeliveryService.DELIVERY_BUSY, busy.errors[0].code);
            Assert.areEqual(Label.eLogix_Delivery_Busy, busy.errors[0].message);
        }
        DeliveryService.selector = new DeliverySelector();
        DeliveryDomain.selector = new TimeoutDeliverySelector();
        System.runAs(TestDataFactory.getUser(OPS)) {
            Database.SaveResult direct = Database.insert(new Delivery__c(Shipment__c = shipment.Id, Delivery_Status__c = 'Scheduled'), false);
            Assert.areEqual(Label.eLogix_Delivery_Busy, direct.getErrors()[0].getMessage());
        }
        Assert.areEqual(0, [SELECT COUNT() FROM Delivery__c WHERE Shipment__c = :shipment.Id]);
    }
}
