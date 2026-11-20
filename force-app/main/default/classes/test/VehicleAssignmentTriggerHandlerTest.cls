/**
 * VehicleAssignmentDomain through direct DML, as the UI, the API or Data Loader would save, without
 * FleetAllocationService. Proves that the fleet rules, permission, transitions, immutability and the
 * shipment mirror cannot be bypassed, and that the trigger-only entry points refuse other callers.
 */
@IsTest
private class VehicleAssignmentTriggerHandlerTest {
    private static final String FLEET = 'Direct Fleet Tester';
    private static final String OPS = 'Direct Ops Tester';
    private static Integer sequence = 0;

    @TestSetup
    static void setup() {
        Business_Unit__c businessUnit = TestDataFactory.createBusinessUnit('BU-VA');
        TestDataFactory.createCustomer('CUST-VA', businessUnit.Id);
        TestDataFactory.createUser(FLEET, TestDataFactory.FLEET);
        TestDataFactory.createUser(OPS, TestDataFactory.OPERATIONS);
    }

    private static Account customer() {
        return [SELECT Id, Business_Unit__c FROM Account WHERE Customer_Code__c = 'CUST-VA'];
    }

    private static List<Shipment__c> confirmed(Integer count) {
        List<Shipment__c> shipments;
        System.runAs(TestDataFactory.getUser(OPS)) {
            Account c = customer();
            shipments = TestDataFactory.confirmedShipments(count, c.Id, c.Business_Unit__c);
        }
        return shipments;
    }

    private static Vehicle__c vehicle() {
        Vehicle__c record = TestDataFactory.buildVehicle('TN-VA-' + (++sequence), customer().Business_Unit__c);
        System.runAs(TestDataFactory.getUser(FLEET)) {
            insert record;
        }
        return record;
    }

    private static Driver__c driver() {
        Driver__c record = TestDataFactory.buildDriver('DL-VA-' + (++sequence), customer().Business_Unit__c);
        System.runAs(TestDataFactory.getUser(FLEET)) {
            insert record;
        }
        return record;
    }

    private static Vehicle_Assignment__c direct(Id shipmentId, Id vehicleId, Id driverId, String status) {
        return new Vehicle_Assignment__c(
            Shipment__c = shipmentId,
            Vehicle__c = vehicleId,
            Driver__c = driverId,
            Status__c = status,
            Assignment_Start__c = System.now().addYears(1), // ignored: the trigger derives the window
            Assignment_End__c = System.now().addYears(2)
        );
    }

    private static String firstError(Database.SaveResult result) {
        return result.isSuccess() ? null : result.getErrors()[0].getMessage();
    }

    @IsTest
    static void directInsertsFollowTheSameRules() {
        List<Shipment__c> shipments = confirmed(2);
        Vehicle__c truck = vehicle();
        Driver__c person = driver();
        Driver__c other = driver();
        System.runAs(TestDataFactory.getUser(FLEET)) {
            Assert.areEqual(Label.eLogix_Fleet_Must_Start_Planned, firstError(Database.insert(direct(shipments[0].Id, truck.Id, person.Id, 'Active'), false)));
            Assert.areEqual(Label.eLogix_Fleet_Shipment_Required, firstError(Database.insert(direct(null, truck.Id, person.Id, 'Planned'), false)));

            Vehicle_Assignment__c valid = direct(shipments[0].Id, truck.Id, person.Id, 'Planned');
            Assert.isNull(firstError(Database.insert(valid, false)));
            Vehicle_Assignment__c saved = [SELECT Assignment_Start__c, Assignment_End__c FROM Vehicle_Assignment__c WHERE Id = :valid.Id];
            Shipment__c shipment = [SELECT Pickup_Date__c, Expected_Delivery_Date__c, Vehicle__c FROM Shipment__c WHERE Id = :shipments[0].Id];
            Assert.areEqual(AssignmentWindow.startOf(shipment.Pickup_Date__c), saved.Assignment_Start__c, 'The supplied window is replaced (Q3).');
            Assert.areEqual(AssignmentWindow.endOf(shipment.Expected_Delivery_Date__c), saved.Assignment_End__c);
            Assert.areEqual(truck.Id, shipment.Vehicle__c, 'The mirror runs for direct inserts too.');

            String overlap = firstError(Database.insert(direct(shipments[1].Id, truck.Id, other.Id, 'Planned'), false));
            Assert.isTrue(overlap.contains('already has an assignment that overlaps'), overlap);
        }
    }

    @IsTest
    static void thePermissionIsRequiredForDirectChanges() {
        Shipment__c shipment = confirmed(1)[0];
        Vehicle__c truck = vehicle();
        Driver__c person = driver();
        System.runAs(TestDataFactory.getUser(OPS)) {
            Assert.isFalse(Database.insert(direct(shipment.Id, truck.Id, person.Id, 'Planned'), false).isSuccess(), 'Operations has read-only access.');
        }
        System.runAs(TestDataFactory.getUser(FLEET)) {
            Vehicle_Assignment__c planned = direct(shipment.Id, truck.Id, person.Id, 'Planned');
            insert planned;
            PermissionService.testOverrides.put(VehicleAssignmentDomain.ALLOCATE_PERMISSION, false);
            Assert.areEqual(
                Label.eLogix_Fleet_Permission_Required,
                firstError(Database.insert(direct(confirmed(1)[0].Id, vehicle().Id, driver().Id, 'Planned'), false))
            );
            // The automatic-release exemption needs a Cancelled shipment; it cannot be borrowed.
            Assert.areEqual(
                Label.eLogix_Fleet_Permission_Required,
                firstError(Database.update(new Vehicle_Assignment__c(Id = planned.Id, Status__c = 'Cancelled'), false))
            );
        }
    }

    @IsTest
    static void transitionsAndLocksAreEnforced() {
        List<Shipment__c> shipments = confirmed(3);
        Vehicle__c truck = vehicle();
        Vehicle__c spare = vehicle();
        Driver__c person = driver();
        Driver__c relief = driver();
        System.runAs(TestDataFactory.getUser(FLEET)) {
            Vehicle_Assignment__c a = direct(shipments[0].Id, truck.Id, person.Id, 'Planned');
            insert a;
            Assert.areEqual(
                String.format(Label.eLogix_Fleet_Transition_Not_Allowed, new List<Object>{ 'Planned', 'Completed' }),
                firstError(Database.update(new Vehicle_Assignment__c(Id = a.Id, Status__c = 'Completed'), false))
            );
            Assert.areEqual(
                Label.eLogix_Fleet_Shipment_Immutable,
                firstError(Database.update(new Vehicle_Assignment__c(Id = a.Id, Shipment__c = shipments[1].Id), false))
            );
            Assert.isTrue(
                firstError(Database.update(new Vehicle_Assignment__c(Id = a.Id, Status__c = 'Cancelled', Vehicle__c = spare.Id), false))
                    .contains('can no longer change'),
                'A status change cannot carry a vehicle change.'
            );
            update new Vehicle_Assignment__c(Id = a.Id, Status__c = 'Cancelled');
            Assert.isTrue(firstError(Database.update(new Vehicle_Assignment__c(Id = a.Id, Status__c = 'Planned'), false)).contains('Cancelled'));
            Assert.isTrue(firstError(Database.update(new Vehicle_Assignment__c(Id = a.Id, Vehicle__c = spare.Id), false)).contains('Cancelled'));
            Assert.isNull(firstError(Database.update(new Vehicle_Assignment__c(Id = a.Id, Remarks__c = 'History note.'), false)), 'Remarks stay editable.');
        }

        // Active: vehicle and window frozen.
        Vehicle_Assignment__c active = direct(shipments[2].Id, truck.Id, person.Id, 'Planned');
        System.runAs(TestDataFactory.getUser(FLEET)) {
            insert active;
        }
        System.runAs(TestDataFactory.getUser(OPS)) {
            update new Shipment__c(Id = shipments[2].Id, Status__c = 'Ready for Dispatch');
        }
        System.runAs(TestDataFactory.getUser(FLEET)) {
            update new Vehicle_Assignment__c(Id = active.Id, Status__c = 'Active');
            Assert.isTrue(firstError(Database.update(new Vehicle_Assignment__c(Id = active.Id, Driver__c = relief.Id), false)).contains('Active'));
            Assert.isTrue(
                firstError(Database.update(new Vehicle_Assignment__c(Id = active.Id, Assignment_End__c = System.now().addDays(30)), false)).contains('Active')
            );
            Assert.areEqual(
                String.format(Label.eLogix_Fleet_Transition_Not_Allowed, new List<Object>{ 'Active', 'Cancelled' }),
                firstError(Database.update(new Vehicle_Assignment__c(Id = active.Id, Status__c = 'Cancelled'), false))
            );
        }
    }

    /** Q18: an old assignment never clears a reference that now belongs to something else. */
    @IsTest
    static void anOldAssignmentNeverClearsANewerReference() {
        Shipment__c shipment = confirmed(1)[0];
        Vehicle__c original = vehicle();
        Vehicle__c newer = vehicle();
        Driver__c person = driver();
        Vehicle_Assignment__c planned = direct(shipment.Id, original.Id, person.Id, 'Planned');
        System.runAs(TestDataFactory.getUser(FLEET)) {
            insert planned;
        }
        // An administrator (who may edit the protected field) points the shipment at another vehicle.
        update new Shipment__c(Id = shipment.Id, Vehicle__c = newer.Id);

        System.runAs(TestDataFactory.getUser(FLEET)) {
            update new Vehicle_Assignment__c(Id = planned.Id, Status__c = 'Cancelled');
        }

        Shipment__c saved = [SELECT Vehicle__c, Driver__c FROM Shipment__c WHERE Id = :shipment.Id];
        Assert.areEqual(newer.Id, saved.Vehicle__c, 'Not this assignment vehicle any more: left alone.');
        Assert.isNull(saved.Driver__c, 'Still this assignment driver: cleared.');
    }

    @IsTest
    static void theFleetManagerCannotWriteTheShipmentMirrorDirectly() {
        Shipment__c shipment = confirmed(1)[0];
        Vehicle__c truck = vehicle();
        System.runAs(TestDataFactory.getUser(FLEET)) {
            Assert.isFalse(
                Database.update(new Shipment__c(Id = shipment.Id, Vehicle__c = truck.Id), false).isSuccess(),
                'Read-only shipment access and a protected field.'
            );
        }
        Assert.isNull([SELECT Vehicle__c FROM Shipment__c WHERE Id = :shipment.Id].Vehicle__c);
    }

    @IsTest
    static void triggerOnlyEntryPointsRefuseOtherCallers() {
        Map<String, String> codes = new Map<String, String>();
        try {
            new VehicleAssignmentDomain().syncShipments();
        } catch (AuthorizationException e) {
            codes.put('mirror', e.code);
        }
        try {
            new FleetAllocationService().clearCancelledShipmentAllocations();
        } catch (AuthorizationException e) {
            codes.put('clear', e.code);
        }
        try {
            new FleetAllocationService().releaseCancelledShipmentAssignments();
        } catch (AuthorizationException e) {
            codes.put('release', e.code);
        }
        Assert.areEqual(VehicleAssignmentDomain.MIRROR_TRIGGER_ONLY, codes.get('mirror'));
        Assert.areEqual(FleetAllocationService.CANCELLATION_TRIGGER_ONLY, codes.get('clear'));
        Assert.areEqual(FleetAllocationService.CANCELLATION_TRIGGER_ONLY, codes.get('release'));
    }

    @IsTest
    static void aRemarksOnlySaveCostsNothing() {
        List<Shipment__c> shipments = confirmed(20);
        List<Vehicle__c> trucks = new List<Vehicle__c>();
        List<Driver__c> crew = new List<Driver__c>();
        Id businessUnitId = customer().Business_Unit__c;
        for (Integer i = 0; i < 20; i++) {
            trucks.add(TestDataFactory.buildVehicle('TN-VA-B' + i, businessUnitId));
            crew.add(TestDataFactory.buildDriver('DL-VA-B' + i, businessUnitId));
        }
        List<Vehicle_Assignment__c> assignments = new List<Vehicle_Assignment__c>();
        System.runAs(TestDataFactory.getUser(FLEET)) {
            insert trucks;
            insert crew;
            for (Integer i = 0; i < 20; i++) {
                assignments.add(direct(shipments[i].Id, trucks[i].Id, crew[i].Id, 'Planned'));
            }
            insert assignments;
            List<Vehicle_Assignment__c> remarks = new List<Vehicle_Assignment__c>();
            for (Vehicle_Assignment__c assignment : assignments) {
                remarks.add(new Vehicle_Assignment__c(Id = assignment.Id, Remarks__c = 'Driver briefed.'));
            }

            Test.startTest();
            Integer queriesBefore = Limits.getQueries();
            Integer dmlBefore = Limits.getDmlStatements();
            update remarks;
            Integer queries = Limits.getQueries() - queriesBefore;
            Integer dml = Limits.getDmlStatements() - dmlBefore;
            Test.stopTest();

            Assert.areEqual(0, queries);
            Assert.areEqual(1, dml);
        }
    }

    /* ---------------- audit fix 1: no delete, no undelete ---------------- */

    @IsTest
    static void deletionIsRefusedForEveryoneAndKeepsTheBooking() {
        List<Shipment__c> shipments = confirmed(2);
        Vehicle__c truck = vehicle();
        Driver__c person = driver();
        Driver__c other = driver();
        Vehicle_Assignment__c planned = direct(shipments[0].Id, truck.Id, person.Id, 'Planned');
        System.runAs(TestDataFactory.getUser(FLEET)) {
            insert planned;
            Assert.isFalse(Schema.SObjectType.Vehicle_Assignment__c.isDeletable(), 'Least privilege: no Delete for the Fleet Manager.');
            Assert.isFalse(Database.delete(planned.Id, false).isSuccess(), 'Fleet Manager delete.');
        }
        // The running administrator holds Delete and Modify All; the trigger still refuses.
        Database.DeleteResult adminDelete = Database.delete(planned.Id, false);
        Assert.isFalse(adminDelete.isSuccess());
        Assert.areEqual(Label.eLogix_Fleet_Delete_Not_Allowed, adminDelete.getErrors()[0].getMessage());

        // The booking still holds: the vehicle cannot be double-booked through a delete.
        System.runAs(TestDataFactory.getUser(FLEET)) {
            String overlap = firstError(Database.insert(direct(shipments[1].Id, truck.Id, other.Id, 'Planned'), false));
            Assert.isTrue(overlap.contains('already has an assignment that overlaps'), overlap);
        }
    }

    @IsTest
    static void completedHistoryCannotBeDeleted() {
        Shipment__c shipment = confirmed(1)[0];
        Vehicle_Assignment__c assignment = direct(shipment.Id, vehicle().Id, driver().Id, 'Planned');
        System.runAs(TestDataFactory.getUser(FLEET)) {
            insert assignment;
        }
        System.runAs(TestDataFactory.getUser(OPS)) {
            update new Shipment__c(Id = shipment.Id, Status__c = 'Ready for Dispatch');
        }
        System.runAs(TestDataFactory.getUser(FLEET)) {
            FleetAllocationService service = new FleetAllocationService();
            Assert.isTrue(service.activate(new List<Id>{ assignment.Id }).isSuccess);
            Assert.isTrue(service.complete(new List<Id>{ assignment.Id }).isSuccess);
        }

        Database.DeleteResult adminDelete = Database.delete(assignment.Id, false);

        Assert.areEqual(Label.eLogix_Fleet_Delete_Not_Allowed, adminDelete.getErrors()[0].getMessage());
        Assert.areEqual('Completed', [SELECT Status__c FROM Vehicle_Assignment__c WHERE Id = :assignment.Id].Status__c);
    }

    /**
     * A real undelete cannot be produced in a test, because no user can delete an assignment in the
     * first place. The platform fires after undelete for every restore (UI, API, Database.undelete);
     * this proves the handler routes it, and before delete, to a refusal.
     */
    @IsTest
    static void deleteAndRestoreAreRoutedToARefusal() {
        Vehicle_Assignment__c restored = new Vehicle_Assignment__c(Id = TestDataFactory.fakeId(Vehicle_Assignment__c.SObjectType, 1), Status__c = 'Planned');
        new VehicleAssignmentTriggerHandler(System.TriggerOperation.AFTER_UNDELETE, new List<SObject>{ restored }, null).run();
        Assert.areEqual(Label.eLogix_Fleet_Delete_Not_Allowed, restored.getErrors()[0].getMessage());

        Vehicle_Assignment__c deleted = new Vehicle_Assignment__c(Id = TestDataFactory.fakeId(Vehicle_Assignment__c.SObjectType, 2), Status__c = 'Cancelled');
        new VehicleAssignmentTriggerHandler(System.TriggerOperation.BEFORE_DELETE, null, new Map<Id, SObject>{ deleted.Id => deleted }).run();
        Assert.areEqual(Label.eLogix_Fleet_Delete_Not_Allowed, deleted.getErrors()[0].getMessage());
    }

    /* ---------------- round 3, issue 3: no orphaned bookings ---------------- */

    @IsTest
    static void aShipmentWithAnOpenAssignmentCannotBeDeleted() {
        List<Shipment__c> shipments = confirmed(2);
        Vehicle_Assignment__c planned = direct(shipments[0].Id, vehicle().Id, driver().Id, 'Planned');
        Vehicle_Assignment__c active = direct(shipments[1].Id, vehicle().Id, driver().Id, 'Planned');
        System.runAs(TestDataFactory.getUser(FLEET)) {
            insert new List<Vehicle_Assignment__c>{ planned, active };
        }
        System.runAs(TestDataFactory.getUser(OPS)) {
            update new Shipment__c(Id = shipments[1].Id, Status__c = 'Ready for Dispatch');
        }
        System.runAs(TestDataFactory.getUser(FLEET)) {
            Assert.isTrue(new FleetAllocationService().activate(new List<Id>{ active.Id }).isSuccess);
        }
        Map<Id, String> names = new Map<Id, String>();
        for (Shipment__c shipment : [SELECT Id, Name FROM Shipment__c WHERE Id IN :shipments]) {
            names.put(shipment.Id, shipment.Name);
        }

        // The running administrator may delete shipments, but not ones with a live booking.
        List<Database.DeleteResult> blocked = Database.delete(new List<Id>{ shipments[0].Id, shipments[1].Id }, false);
        for (Integer i = 0; i < 2; i++) {
            Assert.areEqual(
                String.format(Label.eLogix_Fleet_Shipment_Delete_Blocked, new List<Object>{ names.get(shipments[i].Id) }),
                blocked[i].getErrors()[0].getMessage()
            );
        }

        // Once the Planned assignment is cancelled through its lifecycle, the shipment can go; the
        // Cancelled assignment stays as history under the existing retention behaviour.
        System.runAs(TestDataFactory.getUser(FLEET)) {
            Assert.isTrue(new FleetAllocationService().release(new List<Id>{ planned.Id }).isSuccess);
        }
        Assert.isTrue(Database.delete(shipments[0].Id, false).isSuccess());
        Vehicle_Assignment__c history = [SELECT Status__c, Shipment__c FROM Vehicle_Assignment__c WHERE Id = :planned.Id];
        Assert.areEqual('Cancelled', history.Status__c);
        Assert.isNull(history.Shipment__c);
        Assert.areEqual(1, [SELECT COUNT() FROM Shipment__c WHERE Id = :shipments[1].Id], 'The shipment with an Active assignment remains.');
    }

    @IsTest
    static void theDeletionCheckOnlyRunsInItsTrigger() {
        try {
            new FleetAllocationService().rejectDeletionWithOpenAssignments();
            Assert.fail('Expected a refusal.');
        } catch (AuthorizationException e) {
            Assert.areEqual(FleetAllocationService.DELETION_TRIGGER_ONLY, e.code);
        }
    }

    @IsTest
    static void theHandlerRoutesBeforeInsertToTheDomain() {
        PermissionService.testOverrides.put(VehicleAssignmentDomain.ALLOCATE_PERMISSION, true);
        Vehicle_Assignment__c orphan = new Vehicle_Assignment__c(Status__c = 'Planned');
        new VehicleAssignmentTriggerHandler(System.TriggerOperation.BEFORE_INSERT, new List<Vehicle_Assignment__c>{ orphan }, null).run();
        Assert.areEqual(Label.eLogix_Fleet_Shipment_Required, orphan.getErrors()[0].getMessage());
    }
}
