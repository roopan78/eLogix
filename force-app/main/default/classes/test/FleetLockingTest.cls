/**
 * Phase 4 audit fixes 4 and 5. Q16: every row lock in the allocation, reallocation, release, mirror,
 * cancellation and Ready for Dispatch paths turns a lock timeout into the retryable FLEET_BUSY, without
 * raw database text and without writing anything. Real lock contention cannot be produced in an Apex
 * test, so each lock point is made to time out through the selector seam (a subclass whose chosen lock
 * query throws the platform's lock exception). Fix 5: the sharing-ignoring enforcement reads refuse to
 * run outside their trigger contexts.
 */
@IsTest
private class FleetLockingTest {
    private static final String FLEET = 'Locking Fleet Tester';
    private static final String OPS = 'Locking Ops Tester';
    private static final String LOCK_TIMEOUT = 'Record Currently Unavailable: The record you are attempting to edit is currently being modified (UNABLE_TO_LOCK_ROW)';
    private static Integer sequence = 0;

    @TestSetup
    static void setup() {
        Business_Unit__c businessUnit = TestDataFactory.createBusinessUnit('BU-LK');
        TestDataFactory.createCustomer('CUST-LK', businessUnit.Id);
        TestDataFactory.createUser(FLEET, TestDataFactory.FLEET);
        TestDataFactory.createUser(OPS, TestDataFactory.OPERATIONS);
    }

    /** Times out the named lock points and behaves normally everywhere else. */
    private class TimeoutSelector extends FleetSelector {
        private final Set<String> failing;

        TimeoutSelector(Set<String> failing) {
            this.failing = failing;
        }

        private void maybeFail(String point) {
            if (failing.contains(point)) {
                throw new QueryException(LOCK_TIMEOUT);
            }
        }

        public override Map<Id, Vehicle__c> lockVehicles(Set<Id> ids) {
            maybeFail('vehicles');
            return super.lockVehicles(ids);
        }

        public override Map<Id, Driver__c> lockDrivers(Set<Id> ids) {
            maybeFail('drivers');
            return super.lockDrivers(ids);
        }

        public override Map<Id, Shipment__c> shipmentsForAllocation(Set<Id> ids) {
            maybeFail('shipments');
            return super.shipmentsForAllocation(ids);
        }

        public override Map<Id, Vehicle_Assignment__c> plannedAssignmentByShipment(Set<Id> ids) {
            maybeFail('planned');
            return super.plannedAssignmentByShipment(ids);
        }

        public override Map<Id, Vehicle_Assignment__c> assignmentsForUpdate(Set<Id> ids) {
            maybeFail('assignments');
            return super.assignmentsForUpdate(ids);
        }

        public override Map<Id, Shipment__c> lockShipmentsForMirror(Set<Id> ids) {
            maybeFail('mirror');
            return super.lockShipmentsForMirror(ids);
        }

        public override List<Vehicle_Assignment__c> lockPlannedAssignmentsOfShipments(Set<Id> ids) {
            maybeFail('release');
            return super.lockPlannedAssignmentsOfShipments(ids);
        }
    }

    private static Shipment__c confirmedShipment() {
        Shipment__c shipment;
        System.runAs(TestDataFactory.getUser(OPS)) {
            Account c = [SELECT Id, Business_Unit__c FROM Account WHERE Customer_Code__c = 'CUST-LK'];
            shipment = TestDataFactory.confirmedShipments(1, c.Id, c.Business_Unit__c)[0];
        }
        return shipment;
    }

    private static AllocationRequest freshRequest(Id shipmentId) {
        Id businessUnitId = [SELECT Business_Unit__c FROM Account WHERE Customer_Code__c = 'CUST-LK'].Business_Unit__c;
        Vehicle__c truck = TestDataFactory.buildVehicle('TN-LK-' + (++sequence), businessUnitId);
        Driver__c driver = TestDataFactory.buildDriver('DL-LK-' + (++sequence), businessUnitId);
        System.runAs(TestDataFactory.getUser(FLEET)) {
            insert truck;
            insert driver;
        }
        return new AllocationRequest(shipmentId, truck.Id, driver.Id);
    }

    private static ServiceResult allocate(List<AllocationRequest> requests) {
        ServiceResult result;
        System.runAs(TestDataFactory.getUser(FLEET)) {
            result = new FleetAllocationService().allocate(requests);
        }
        return result;
    }

    private static void assertBusy(ServiceResult result, Integer index) {
        ServiceResult.ServiceError error = result.errorsFor(index)[0];
        Assert.areEqual(FleetAllocationService.FLEET_BUSY, error.code);
        Assert.areEqual(Label.eLogix_Fleet_Busy, error.message, 'No raw database text.');
    }

    /* ---------------- service lock points ---------------- */

    @IsTest
    static void serviceLockTimeoutsAreRetryablePerRecord() {
        Shipment__c shipment = confirmedShipment();
        AllocationRequest request = freshRequest(shipment.Id);

        FleetAllocationService.selector = new TimeoutSelector(new Set<String>{ 'shipments' });
        ServiceResult blocked = allocate(new List<AllocationRequest>{ request, null });
        assertBusy(blocked, 0);
        Assert.areEqual(FleetAllocationService.REQUEST_INVALID, blocked.errorsFor(1)[0].code, 'A malformed request keeps its own error.');
        Assert.areEqual(0, [SELECT COUNT() FROM Vehicle_Assignment__c]);

        FleetAllocationService.selector = new FleetSelector();
        ServiceResult allocated = allocate(new List<AllocationRequest>{ request });
        Assert.isTrue(allocated.isSuccess, 'The retry succeeds: ' + allocated.errors);
        Id assignmentId = allocated.recordIds[0];

        AllocationRequest other = freshRequest(shipment.Id);
        System.runAs(TestDataFactory.getUser(FLEET)) {
            FleetAllocationService.selector = new TimeoutSelector(new Set<String>{ 'planned' });
            assertBusy(new FleetAllocationService().reallocate(new List<AllocationRequest>{ other }), 0);
            FleetAllocationService.selector = new TimeoutSelector(new Set<String>{ 'assignments' });
            assertBusy(new FleetAllocationService().release(new List<Id>{ assignmentId }), 0);
        }
        Vehicle_Assignment__c unchanged = [SELECT Status__c, Vehicle__c FROM Vehicle_Assignment__c WHERE Id = :assignmentId];
        Assert.areEqual('Planned', unchanged.Status__c);
        Assert.areEqual(request.vehicleId, unchanged.Vehicle__c);
    }

    /* ---------------- trigger lock points ---------------- */

    @IsTest
    static void aMirrorLockTimeoutFailsOnlyTheAssignment() {
        Shipment__c shipment = confirmedShipment();
        AllocationRequest request = freshRequest(shipment.Id);
        VehicleAssignmentDomain.selector = new TimeoutSelector(new Set<String>{ 'mirror' });

        ServiceResult result = allocate(new List<AllocationRequest>{ request });

        assertBusy(result, 0);
        Assert.areEqual(0, [SELECT COUNT() FROM Vehicle_Assignment__c]);
        Assert.isNull([SELECT Vehicle__c FROM Shipment__c WHERE Id = :shipment.Id].Vehicle__c);
    }

    @IsTest
    static void aCancellationLockTimeoutKeepsTheShipmentLive() {
        Shipment__c shipment = confirmedShipment();
        Id assignmentId = allocate(new List<AllocationRequest>{ freshRequest(shipment.Id) }).recordIds[0];
        FleetAllocationService.selector = new TimeoutSelector(new Set<String>{ 'release' });

        Database.SaveResult cancelled = Database.update(
            new Shipment__c(Id = shipment.Id, Status__c = 'Cancelled', Cancellation_Reason__c = 'Order withdrawn.'),
            false
        );

        Assert.isFalse(cancelled.isSuccess());
        Assert.areEqual(
            String.format(Label.eLogix_Fleet_Release_Failed, new List<Object>{ Label.eLogix_Fleet_Busy }),
            cancelled.getErrors()[0].getMessage()
        );
        Assert.areEqual('Confirmed', [SELECT Status__c FROM Shipment__c WHERE Id = :shipment.Id].Status__c);
        Assert.areEqual('Planned', [SELECT Status__c FROM Vehicle_Assignment__c WHERE Id = :assignmentId].Status__c);
    }

    @IsTest
    static void aDispatchGuardLockTimeoutIsRetryable() {
        Shipment__c shipment = confirmedShipment();
        allocate(new List<AllocationRequest>{ freshRequest(shipment.Id) });
        VehicleAssignmentDomain.selector = new TimeoutSelector(new Set<String>{ 'drivers' });

        Database.SaveResult first;
        System.runAs(TestDataFactory.getUser(OPS)) {
            first = Database.update(new Shipment__c(Id = shipment.Id, Status__c = 'Ready for Dispatch'), false);
        }
        Assert.areEqual(Label.eLogix_Fleet_Busy, first.getErrors()[0].getMessage());

        VehicleAssignmentDomain.selector = new FleetSelector();
        Database.SaveResult retry;
        System.runAs(TestDataFactory.getUser(OPS)) {
            retry = Database.update(new Shipment__c(Id = shipment.Id, Status__c = 'Ready for Dispatch'), false);
        }
        Assert.isTrue(retry.isSuccess(), 'The retry succeeds: ' + retry.getErrors());
    }

    @IsTest
    static void lockErrorsAreRecognisedWhateverTheirSource() {
        Assert.areEqual(FleetAllocationService.FLEET_BUSY, FleetAllocationService.codeFor('UNABLE_TO_LOCK_ROW', 'unable to obtain exclusive access'));
        Assert.areEqual(FleetAllocationService.FLEET_BUSY, FleetAllocationService.codeFor('FIELD_CUSTOM_VALIDATION_EXCEPTION', Label.eLogix_Fleet_Busy));
        Assert.areEqual(FleetAllocationService.FLEET_BUSY, FleetAllocationService.codeFor('CANNOT_INSERT_UPDATE_ACTIVATE_ENTITY', LOCK_TIMEOUT));
        Assert.areEqual('FIELD_CUSTOM_VALIDATION_EXCEPTION', FleetAllocationService.codeFor('FIELD_CUSTOM_VALIDATION_EXCEPTION', 'Vehicle is inactive.'));
        Assert.isTrue(VehicleAssignmentDomain.isLockTimeout(new QueryException(LOCK_TIMEOUT)));
        Assert.isFalse(VehicleAssignmentDomain.isLockTimeout(new QueryException('No such column')));
        Assert.isFalse(VehicleAssignmentDomain.isLockTimeout((Exception) null));
    }

    /* ---------------- fix 5: enforcement reads are trigger-only ---------------- */

    @IsTest
    static void enforcementReadsRefuseCallsOutsideTheirTrigger() {
        Set<Id> none = new Set<Id>{ TestDataFactory.fakeId(Shipment__c.SObjectType, 1) };
        FleetSelector selector = new FleetSelector();
        List<String> refused = new List<String>();
        for (Integer i = 0; i < 9; i++) {
            try {
                switch on i {
                    when 0 { selector.lockVehicles(none); }
                    when 1 { selector.lockDrivers(none); }
                    when 2 { selector.shipmentsForAssignments(none); }
                    when 3 { selector.openAssignmentsInWindow(none, none, none, System.now(), System.now().addDays(1), null); }
                    when 4 { selector.openMaintenance(none); }
                    when 5 { selector.shipmentsWithHistoryBeyond(none, new Set<String>()); }
                    when 6 { selector.openAssignmentsOfShipments(none); }
                    when 7 { selector.lockPlannedAssignmentsOfShipments(none); }
                    when 8 { selector.lockShipmentsForMirror(none); }
                }
            } catch (AuthorizationException e) {
                if (e.code == FleetSelector.ENFORCEMENT_TRIGGER_ONLY) {
                    refused.add(String.valueOf(i));
                }
            }
        }
        Assert.areEqual(9, refused.size(), 'Every sharing-ignoring read refuses a caller outside its trigger: ' + refused);
        Assert.isNull(FleetSelector.currentTriggerContext());
        // User-mode reads stay available: they apply the caller's own access.
        Assert.isTrue(selector.readableVehicleIds(new Set<Id>{ TestDataFactory.fakeId(Vehicle__c.SObjectType, 1) }).isEmpty());
    }
}
