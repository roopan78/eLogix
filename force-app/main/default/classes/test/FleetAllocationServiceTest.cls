/**
 * FleetAllocationService end to end, as real role users: allocation, rules reported per record,
 * double booking, reallocation, release, the Ready for Dispatch guard, automatic release on
 * cancellation, the assignment lifecycle, access, bulk 200, lock timeouts and the quoted vehicle type.
 */
@IsTest
private class FleetAllocationServiceTest {
    private static final String FLEET = 'Alloc Fleet Tester';
    private static final String OPS = 'Alloc Ops Tester';
    private static final String MANAGER = 'Alloc LM Tester';
    private static Integer sequence = 0;

    @TestSetup
    static void setup() {
        Business_Unit__c businessUnit = TestDataFactory.createBusinessUnit('BU-FL');
        TestDataFactory.createBusinessUnit('BU-FL2');
        TestDataFactory.createCustomer('CUST-FL', businessUnit.Id);
        TestDataFactory.createUser(FLEET, TestDataFactory.FLEET);
        TestDataFactory.createUser(OPS, TestDataFactory.OPERATIONS);
        TestDataFactory.createUser(MANAGER, TestDataFactory.LOGISTICS_MANAGER);
    }

    private static Account customer() {
        return [SELECT Id, Business_Unit__c FROM Account WHERE Customer_Code__c = 'CUST-FL'];
    }

    private static Id otherUnit() {
        return [SELECT Id FROM Business_Unit__c WHERE Business_Unit_Code__c = 'BU-FL2'].Id;
    }

    private static List<Shipment__c> confirmed(Integer count) {
        List<Shipment__c> shipments;
        System.runAs(TestDataFactory.getUser(OPS)) {
            Account c = customer();
            shipments = TestDataFactory.confirmedShipments(count, c.Id, c.Business_Unit__c);
        }
        return shipments;
    }

    private static List<Vehicle__c> vehicles(Integer count) {
        List<Vehicle__c> records = new List<Vehicle__c>();
        Id businessUnitId = customer().Business_Unit__c;
        System.runAs(TestDataFactory.getUser(FLEET)) {
            for (Integer i = 0; i < count; i++) {
                records.add(TestDataFactory.buildVehicle('TN-FL-' + (++sequence), businessUnitId));
            }
            insert records;
        }
        return records;
    }

    private static List<Driver__c> drivers(Integer count) {
        List<Driver__c> records = new List<Driver__c>();
        Id businessUnitId = customer().Business_Unit__c;
        System.runAs(TestDataFactory.getUser(FLEET)) {
            for (Integer i = 0; i < count; i++) {
                records.add(TestDataFactory.buildDriver('DL-FL-' + (++sequence), businessUnitId));
            }
            insert records;
        }
        return records;
    }

    private static ServiceResult allocate(Id shipmentId, Id vehicleId, Id driverId) {
        return allocateAll(new List<AllocationRequest>{ new AllocationRequest(shipmentId, vehicleId, driverId) });
    }

    private static ServiceResult allocateAll(List<AllocationRequest> requests) {
        ServiceResult result;
        System.runAs(TestDataFactory.getUser(FLEET)) {
            result = new FleetAllocationService().allocate(requests);
        }
        return result;
    }

    private static Shipment__c reload(Id shipmentId) {
        return [SELECT Status__c, Vehicle__c, Driver__c, Pickup_Date__c, Expected_Delivery_Date__c, Business_Unit__c FROM Shipment__c WHERE Id = :shipmentId];
    }

    private static String move(Shipment__c shipment, String status) {
        Database.SaveResult result;
        System.runAs(TestDataFactory.getUser(OPS)) {
            result = Database.update(new Shipment__c(Id = shipment.Id, Status__c = status), false);
        }
        return result.isSuccess() ? null : result.getErrors()[0].getMessage();
    }

    /* ---------------- allocate ---------------- */

    @IsTest
    static void allocatesAndMirrorsTheShipment() {
        Shipment__c shipment = confirmed(1)[0];
        Vehicle__c vehicle = vehicles(1)[0];
        Driver__c driver = drivers(1)[0];

        ServiceResult result = allocate(shipment.Id, vehicle.Id, driver.Id);

        Assert.isTrue(result.isSuccess, String.valueOf(result.errors));
        Vehicle_Assignment__c assignment = [
            SELECT Status__c, Vehicle__c, Driver__c, Shipment__c, Assignment_Start__c, Assignment_End__c, Business_Unit__c
            FROM Vehicle_Assignment__c
            WHERE Id = :result.recordIds[0]
        ];
        Shipment__c saved = reload(shipment.Id);
        Assert.areEqual('Planned', assignment.Status__c);
        Assert.areEqual(AssignmentWindow.startOf(saved.Pickup_Date__c), assignment.Assignment_Start__c, 'Window from the pickup date (Q3).');
        Assert.areEqual(AssignmentWindow.endOf(saved.Expected_Delivery_Date__c), assignment.Assignment_End__c);
        Assert.areEqual(saved.Business_Unit__c, assignment.Business_Unit__c);
        Assert.areEqual(vehicle.Id, saved.Vehicle__c, 'Mirror set by the assignment trigger (Q18).');
        Assert.areEqual(driver.Id, saved.Driver__c);
        Assert.areEqual('Available', [SELECT Status__c FROM Vehicle__c WHERE Id = :vehicle.Id].Status__c, 'Allocation never changes vehicle status (Q2).');
        Assert.areEqual('Available', [SELECT Status__c FROM Driver__c WHERE Id = :driver.Id].Status__c);
    }

    @IsTest
    static void ruleViolationsAreReportedPerRecord() {
        List<Shipment__c> shipments = confirmed(3);
        List<Vehicle__c> trucks = vehicles(3);
        List<Driver__c> crew = drivers(3);
        System.runAs(TestDataFactory.getUser(FLEET)) {
            trucks[0].Capacity__c = 400; // the shipment weighs 500 kg
            trucks[1].Insurance_Expiry__c = Date.today().addDays(2); // window ends today + 3
            update new List<Vehicle__c>{ trucks[0], trucks[1] };
        }

        ServiceResult result = allocateAll(
            new List<AllocationRequest>{
                new AllocationRequest(shipments[0].Id, trucks[0].Id, crew[0].Id),
                new AllocationRequest(shipments[1].Id, trucks[1].Id, crew[1].Id),
                new AllocationRequest(shipments[2].Id, trucks[2].Id, crew[2].Id)
            }
        );

        Assert.isTrue(result.errorsFor(0)[0].message.contains('carries up to'), result.errorsFor(0)[0].message);
        Assert.isTrue(result.errorsFor(1)[0].message.contains(Vehicle__c.Insurance_Expiry__c.getDescribe().getLabel()), result.errorsFor(1)[0].message);
        Assert.isTrue(result.errorsFor(2).isEmpty(), 'The compliant request succeeds on its own.');
        Assert.areEqual(1, [SELECT COUNT() FROM Vehicle_Assignment__c]);
        Assert.isNull(reload(shipments[0].Id).Vehicle__c);
    }

    @IsTest
    static void aDoubleBookedDriverIsRejectedButALaterBookingIsAllowed() {
        List<Shipment__c> shipments = confirmed(3);
        System.runAs(TestDataFactory.getUser(OPS)) {
            update new Shipment__c(Id = shipments[2].Id, Pickup_Date__c = Date.today().addDays(5), Expected_Delivery_Date__c = Date.today().addDays(7));
        }
        List<Vehicle__c> trucks = vehicles(2);
        Driver__c driver = drivers(1)[0];

        Assert.isTrue(allocate(shipments[0].Id, trucks[0].Id, driver.Id).isSuccess);
        ServiceResult doubleBooked = allocate(shipments[1].Id, trucks[1].Id, driver.Id);
        ServiceResult later = allocate(shipments[2].Id, trucks[0].Id, driver.Id);

        Assert.isTrue(doubleBooked.errors[0].message.contains('already has an assignment that overlaps'), doubleBooked.errors[0].message);
        Assert.isTrue(later.isSuccess, 'Same vehicle and driver, non-overlapping later window (Q1): ' + later.errors);
        Assert.areEqual(2, [SELECT COUNT() FROM Vehicle_Assignment__c WHERE Driver__c = :driver.Id AND Status__c = 'Planned']);
    }

    @IsTest
    static void doubleBookingWithinOneCallIsRejected() {
        List<Shipment__c> shipments = confirmed(2);
        Vehicle__c vehicle = vehicles(1)[0];
        List<Driver__c> crew = drivers(2);

        ServiceResult result = allocateAll(
            new List<AllocationRequest>{
                new AllocationRequest(shipments[0].Id, vehicle.Id, crew[0].Id),
                new AllocationRequest(shipments[1].Id, vehicle.Id, crew[1].Id)
            }
        );

        Assert.isTrue(result.errorsFor(0).isEmpty());
        Assert.isTrue(result.errorsFor(1)[0].message.contains('Vehicle ' + vehicle.Vehicle_Number__c + ' already has'), result.errorsFor(1)[0].message);
        Assert.areEqual(1, [SELECT COUNT() FROM Vehicle_Assignment__c]);
    }

    @IsTest
    static void crossBusinessUnitAllocationIsRejected() {
        Shipment__c shipment = confirmed(1)[0];
        Vehicle__c foreign = TestDataFactory.buildVehicle('TN-FL-X1', otherUnit());
        System.runAs(TestDataFactory.getUser(FLEET)) {
            insert foreign;
        }

        ServiceResult result = allocate(shipment.Id, foreign.Id, drivers(1)[0].Id);

        Assert.isTrue(result.errors[0].message.contains('must belong to the same business unit'), result.errors[0].message);
    }

    @IsTest
    static void onlyConfirmedOrOnHoldShipmentsCanBeAllocated() {
        Shipment__c draft;
        System.runAs(TestDataFactory.getUser(OPS)) {
            Account c = customer();
            draft = TestDataFactory.buildShipment(c.Id, c.Business_Unit__c, 'Draft');
            insert draft;
        }
        ServiceResult result = allocate(draft.Id, vehicles(1)[0].Id, drivers(1)[0].Id);
        String name = [SELECT Name FROM Shipment__c WHERE Id = :draft.Id].Name;
        Assert.areEqual(String.format(Label.eLogix_Fleet_Shipment_Status, new List<Object>{ name, 'Draft' }), result.errors[0].message);

        Shipment__c onHold = confirmed(1)[0];
        System.runAs(TestDataFactory.getUser(OPS)) {
            update new Shipment__c(Id = onHold.Id, Status__c = 'On Hold', Hold_Reason__c = 'Customer asked to wait.');
        }
        Assert.isTrue(allocate(onHold.Id, vehicles(1)[0].Id, drivers(1)[0].Id).isSuccess, 'On Hold shipments can be allocated (Q9).');
    }

    /* ---------------- reallocate and release ---------------- */

    @IsTest
    static void reallocationChangesTheAssignmentInPlace() {
        List<Shipment__c> shipments = confirmed(3);
        List<Vehicle__c> trucks = vehicles(3);
        List<Driver__c> crew = drivers(2);
        Id assignmentId = allocate(shipments[0].Id, trucks[0].Id, crew[0].Id).recordIds[0];
        Assert.isTrue(allocate(shipments[1].Id, trucks[2].Id, crew[1].Id).isSuccess);

        ServiceResult moved;
        ServiceResult busy;
        ServiceResult nothing;
        System.runAs(TestDataFactory.getUser(FLEET)) {
            FleetAllocationService service = new FleetAllocationService();
            moved = service.reallocate(new List<AllocationRequest>{ new AllocationRequest(shipments[0].Id, trucks[1].Id, crew[0].Id) });
            busy = service.reallocate(new List<AllocationRequest>{ new AllocationRequest(shipments[0].Id, trucks[2].Id, crew[0].Id) });
            nothing = service.reallocate(new List<AllocationRequest>{ new AllocationRequest(shipments[2].Id, trucks[0].Id, crew[0].Id) });
        }

        Assert.isTrue(moved.isSuccess, String.valueOf(moved.errors));
        Assert.areEqual(assignmentId, moved.recordIds[0], 'The same assignment is updated.');
        Assert.isTrue(busy.errors[0].message.contains('already has an assignment that overlaps'), busy.errors[0].message);
        Assert.areEqual(FleetAllocationService.NO_OPEN_ASSIGNMENT, nothing.errors[0].code);
        Assert.areEqual(trucks[1].Id, reload(shipments[0].Id).Vehicle__c, 'A failed reallocation keeps the previous allocation.');
        Assert.areEqual(trucks[1].Id, [SELECT Vehicle__c FROM Vehicle_Assignment__c WHERE Id = :assignmentId].Vehicle__c);
    }

    @IsTest
    static void releaseFreesTheVehicleAndClearsTheShipment() {
        List<Shipment__c> shipments = confirmed(2);
        Vehicle__c vehicle = vehicles(1)[0];
        Driver__c driver = drivers(1)[0];
        Id assignmentId = allocate(shipments[0].Id, vehicle.Id, driver.Id).recordIds[0];

        ServiceResult released;
        ServiceResult again;
        System.runAs(TestDataFactory.getUser(FLEET)) {
            released = new FleetAllocationService().release(new List<Id>{ assignmentId });
            again = new FleetAllocationService().release(new List<Id>{ assignmentId });
        }

        Assert.isTrue(released.isSuccess, String.valueOf(released.errors));
        Assert.areEqual('Cancelled', [SELECT Status__c FROM Vehicle_Assignment__c WHERE Id = :assignmentId].Status__c);
        Assert.isNull(reload(shipments[0].Id).Vehicle__c);
        Assert.isNull(reload(shipments[0].Id).Driver__c);
        Assert.areEqual(FleetAllocationService.STATUS_NOT_ALLOWED, again.errors[0].code);
        Assert.isTrue(allocate(shipments[1].Id, vehicle.Id, driver.Id).isSuccess, 'The released vehicle is free for the same window.');
    }

    /* ---------------- Ready for Dispatch guard (Q10) ---------------- */

    @IsTest
    static void readyForDispatchNeedsAVerifiedAllocation() {
        List<Shipment__c> shipments = confirmed(2);
        Vehicle__c vehicle = vehicles(1)[0];
        Driver__c driver = drivers(1)[0];

        Assert.areEqual(Label.eLogix_Fleet_Allocation_Required, move(shipments[0], 'Ready for Dispatch'));

        Id assignmentId = allocate(shipments[0].Id, vehicle.Id, driver.Id).recordIds[0];
        Assert.isNull(move(shipments[0], 'Ready for Dispatch'));

        // No reallocation or release once Ready for Dispatch (Q9).
        System.runAs(TestDataFactory.getUser(FLEET)) {
            ServiceResult release = new FleetAllocationService().release(new List<Id>{ assignmentId });
            Assert.isTrue(release.errors[0].message.contains('only while a shipment is Confirmed or On Hold'), release.errors[0].message);
            ServiceResult change = new FleetAllocationService()
                .reallocate(new List<AllocationRequest>{ new AllocationRequest(shipments[0].Id, vehicle.Id, drivers(1)[0].Id) });
            Assert.isFalse(change.isSuccess);
        }

        // Setting the protected fields by hand (an administrator can) does not satisfy the guard.
        update new Shipment__c(Id = shipments[1].Id, Vehicle__c = vehicle.Id, Driver__c = driver.Id);
        Assert.areEqual(Label.eLogix_Fleet_Allocation_Required, move(shipments[1], 'Ready for Dispatch'));
    }

    /* ---------------- cancellation (Q11) ---------------- */

    @IsTest
    static void cancellingAShipmentReleasesItsAssignmentOnce() {
        List<Shipment__c> shipments = confirmed(2);
        Vehicle__c vehicle = vehicles(1)[0];
        Driver__c driver = drivers(1)[0];
        Id assignmentId = allocate(shipments[0].Id, vehicle.Id, driver.Id).recordIds[0];

        // An administrator (holding the cancel permission) cancels the confirmed shipment.
        update new Shipment__c(Id = shipments[0].Id, Status__c = 'Cancelled', Cancellation_Reason__c = 'Customer cancelled the order.');

        Shipment__c cancelled = reload(shipments[0].Id);
        Assert.areEqual('Cancelled', cancelled.Status__c);
        Assert.isNull(cancelled.Vehicle__c, 'Released vehicle reference cleared.');
        Assert.isNull(cancelled.Driver__c);
        Assert.areEqual('Cancelled', [SELECT Status__c FROM Vehicle_Assignment__c WHERE Id = :assignmentId].Status__c);
        Assert.isTrue(allocate(shipments[1].Id, vehicle.Id, driver.Id).isSuccess, 'The vehicle and driver are free again.');

        // A later save of the cancelled shipment releases nothing twice and touches no history.
        update new Shipment__c(Id = shipments[0].Id, Special_Instructions__c = 'Archived.');
        Assert.areEqual(1, [SELECT COUNT() FROM Vehicle_Assignment__c WHERE Status__c = 'Cancelled']);
        Assert.areEqual(1, [SELECT COUNT() FROM Vehicle_Assignment__c WHERE Status__c = 'Planned']);
    }

    /* ---------------- lifecycle (Q12) ---------------- */

    @IsTest
    static void lifecycleKeepsHistoryAfterCompletion() {
        Shipment__c shipment = confirmed(1)[0];
        Vehicle__c vehicle = vehicles(1)[0];
        Driver__c driver = drivers(1)[0];
        Id assignmentId = allocate(shipment.Id, vehicle.Id, driver.Id).recordIds[0];

        System.runAs(TestDataFactory.getUser(FLEET)) {
            ServiceResult early = new FleetAllocationService().activate(new List<Id>{ assignmentId });
            Assert.isTrue(early.errors[0].message.contains('Ready for Dispatch or Dispatched'), early.errors[0].message);
        }
        Assert.isNull(move(shipment, 'Ready for Dispatch'));
        System.runAs(TestDataFactory.getUser(FLEET)) {
            FleetAllocationService service = new FleetAllocationService();
            Assert.isTrue(service.activate(new List<Id>{ assignmentId }).isSuccess);
            Assert.areEqual(FleetAllocationService.STATUS_NOT_ALLOWED, service.release(new List<Id>{ assignmentId }).errors[0].code, 'Active cannot be released.');
            Assert.isTrue(service.complete(new List<Id>{ assignmentId }).isSuccess);
            Assert.areEqual(FleetAllocationService.STATUS_NOT_ALLOWED, service.complete(new List<Id>{ assignmentId }).errors[0].code, 'Completed is terminal.');
        }

        Vehicle_Assignment__c completed = [SELECT Status__c, Assignment_Start__c, Assignment_End__c FROM Vehicle_Assignment__c WHERE Id = :assignmentId];
        Assert.areEqual('Completed', completed.Status__c);
        Assert.isTrue(completed.Assignment_End__c > completed.Assignment_Start__c);
        Shipment__c saved = reload(shipment.Id);
        Assert.areEqual(vehicle.Id, saved.Vehicle__c, 'Completed assignments keep their historical references (Q18).');
        Assert.areEqual(driver.Id, saved.Driver__c);
    }

    /* ---------------- access ---------------- */

    @IsTest
    static void usersWithoutTheFleetPermissionAreDenied() {
        Shipment__c shipment = confirmed(1)[0];
        Vehicle__c vehicle = vehicles(1)[0];
        Driver__c driver = drivers(1)[0];
        System.runAs(TestDataFactory.getUser(OPS)) {
            try {
                new FleetAllocationService().allocate(new List<AllocationRequest>{ new AllocationRequest(shipment.Id, vehicle.Id, driver.Id) });
                Assert.fail('Operations Executives cannot allocate fleet.');
            } catch (AuthorizationException e) {
                Assert.areEqual(AuthorizationException.ACCESS_DENIED, e.code);
            }
        }
        System.runAs(TestDataFactory.getUser(MANAGER)) {
            PermissionService.testOverrides.put(VehicleAssignmentDomain.ALLOCATE_PERMISSION, false);
            try {
                new FleetAllocationService().release(new List<Id>{ TestDataFactory.fakeId(Vehicle_Assignment__c.SObjectType, 1) });
                Assert.fail('Without eLogix_Allocate_Fleet nothing is allowed.');
            } catch (AuthorizationException e) {
                Assert.areEqual(AuthorizationException.ACCESS_DENIED, e.code);
            }
        }
        Assert.areEqual(0, [SELECT COUNT() FROM Vehicle_Assignment__c]);
    }

    @IsTest
    static void invalidAndInvisibleRequestsAreReportedPerRecord() {
        Shipment__c shipment = confirmed(1)[0];
        Vehicle__c vehicle = vehicles(1)[0];
        Driver__c driver = drivers(1)[0];

        ServiceResult result = allocateAll(
            new List<AllocationRequest>{
                null,
                new AllocationRequest(shipment.Id, driver.Id, vehicle.Id), // ids of the wrong types
                new AllocationRequest(TestDataFactory.fakeId(Shipment__c.SObjectType, 7), vehicle.Id, driver.Id)
            }
        );

        Assert.areEqual(FleetAllocationService.REQUEST_INVALID, result.errorsFor(0)[0].code);
        Assert.areEqual(FleetAllocationService.REQUEST_INVALID, result.errorsFor(1)[0].code);
        Assert.areEqual(FleetAllocationService.NOT_FOUND, result.errorsFor(2)[0].code);
        Assert.isTrue(allocateAll(null).isSuccess);
    }

    /* ---------------- bulk and concurrency ---------------- */

    @IsTest
    static void twoHundredAllocationsInOneCall() {
        List<Shipment__c> shipments = confirmed(200);
        List<Vehicle__c> trucks = vehicles(200);
        List<Driver__c> crew = drivers(200);
        List<AllocationRequest> requests = new List<AllocationRequest>();
        for (Integer i = 0; i < 200; i++) {
            requests.add(new AllocationRequest(shipments[i].Id, trucks[i].Id, crew[i].Id));
        }

        ServiceResult result;
        Integer queries;
        Integer dml;
        System.runAs(TestDataFactory.getUser(FLEET)) {
            Test.startTest();
            Integer queriesBefore = Limits.getQueries();
            Integer dmlBefore = Limits.getDmlStatements();
            result = new FleetAllocationService().allocate(requests);
            queries = Limits.getQueries() - queriesBefore;
            dml = Limits.getDmlStatements() - dmlBefore;
            Test.stopTest();
        }

        Assert.isTrue(result.isSuccess, String.valueOf(result.errors));
        Assert.areEqual(200, result.recordIds.size());
        Assert.areEqual(10, queries, 'Service 3 (shipments, vehicles, drivers); trigger 6 (shipments, org time zone, 2 locks, conflicts, maintenance); mirror 1.');
        Assert.areEqual(2, dml, 'The assignment insert and the shipment mirror update.');
        Assert.areEqual(200, [SELECT COUNT() FROM Shipment__c WHERE Vehicle__c != NULL AND Driver__c != NULL]);
    }

    /** Q16: a lock wait timeout becomes a retryable per-record FLEET_BUSY error, not an exception. */
    @IsTest
    static void aLockTimeoutBecomesARetryableError() {
        Shipment__c shipment = confirmed(1)[0];
        Vehicle__c vehicle = vehicles(1)[0];
        Driver__c driver = drivers(1)[0];
        VehicleAssignmentDomain.selector = new TimeoutSelector();

        ServiceResult result = allocate(shipment.Id, vehicle.Id, driver.Id);

        Assert.areEqual(FleetAllocationService.FLEET_BUSY, result.errors[0].code);
        Assert.areEqual(Label.eLogix_Fleet_Busy, result.errors[0].message);
        Assert.areEqual(0, [SELECT COUNT() FROM Vehicle_Assignment__c]);
        Assert.isTrue(VehicleAssignmentDomain.isLockTimeout(new DmlException('UNABLE_TO_LOCK_ROW')));
        Assert.isFalse(VehicleAssignmentDomain.isLockTimeout(new DmlException('Something else')));
    }

    private class TimeoutSelector extends FleetSelector {
        public override Map<Id, Vehicle__c> lockVehicles(Set<Id> vehicleIds) {
            throw new QueryException('Record Currently Unavailable: UNABLE_TO_LOCK_ROW');
        }
    }

    /* ---------------- quoted vehicle type, end to end (Q7) ---------------- */

    @IsTest
    static void theQuotedVehicleTypeIsEnforced() {
        Account c = customer();
        Route__c route = TestDataFactory.createRoute('RT-FL', 350);
        insert TestDataFactory.buildRateCard('RC-FL-LCV', 'LCV');
        Shipment__c shipment;
        System.runAs(TestDataFactory.getUser(MANAGER)) {
            Shipment_Request__c request = TestDataFactory.buildShipmentRequest(c.Id, c.Business_Unit__c, route.Id, 'Submitted');
            insert request;
            QuotationService quotes = new QuotationService();
            Id quotationId = quotes.createFromRequests(new List<Id>{ request.Id }).recordIds[0];
            quotes.submitForApproval(new List<Id>{ quotationId });
            update new Quotation__c(Id = quotationId, Status__c = 'Sent');
            update new Quotation__c(Id = quotationId, Status__c = 'Accepted');
            Id shipmentId = quotes.convertToShipment(new List<Id>{ quotationId }).recordIds[0];
            shipment = new Shipment__c(Id = shipmentId);
            insert TestDataFactory.buildItems(new List<Shipment__c>{ shipment });
            update new Shipment__c(Id = shipmentId, Status__c = 'Confirmed');
        }
        Vehicle__c container = TestDataFactory.buildVehicle('TN-FL-CT1', c.Business_Unit__c);
        container.Vehicle_Type__c = 'Container Truck';
        Vehicle__c lcv = TestDataFactory.buildVehicle('TN-FL-LCV1', c.Business_Unit__c);
        System.runAs(TestDataFactory.getUser(FLEET)) {
            insert new List<Vehicle__c>{ container, lcv };
        }
        Driver__c driver = drivers(1)[0];
        // Regression: the Fleet Manager cannot read quotations at all (no object access, Private OWD),
        // yet the rule must still see the quoted type. Enforcement reads run without sharing.
        System.runAs(TestDataFactory.getUser(FLEET)) {
            Assert.isFalse(Schema.SObjectType.Quotation__c.isAccessible(), 'Precondition: quotations are not readable by the Fleet Manager.');
        }

        ServiceResult wrongType = allocate(shipment.Id, container.Id, driver.Id);
        Assert.isFalse(wrongType.isSuccess, 'A vehicle of another type than the quoted one must be refused.');
        Assert.areEqual(
            String.format(Label.eLogix_Fleet_Vehicle_Type_Mismatch, new List<Object>{ 'LCV', 'TN-FL-CT1', 'Container Truck' }),
            wrongType.errors[0].message
        );
        Assert.isTrue(allocate(shipment.Id, lcv.Id, driver.Id).isSuccess, 'The quoted vehicle type is accepted.');
    }
}
