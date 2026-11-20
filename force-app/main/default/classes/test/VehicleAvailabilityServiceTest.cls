/**
 * Pure unit tests of the fleet eligibility rules (VehicleAvailabilityService) and of the window
 * boundaries (AssignmentWindow). In-memory records only; no DML.
 *
 * Reference: shipment of 500 kg, pickup today + 1, expected delivery today + 3; compliant 1,000 kg
 * LCV and driver, all in the same business unit.
 */
@IsTest
private class VehicleAvailabilityServiceTest {
    private static final Id UNIT = TestDataFactory.fakeId(Business_Unit__c.SObjectType, 1);
    private static final Id OTHER_UNIT = TestDataFactory.fakeId(Business_Unit__c.SObjectType, 2);
    private static final Date PICKUP = Date.today().addDays(1);
    private static final Date DELIVERY = Date.today().addDays(3);
    private static Integer sequence = 100;

    private static Shipment__c shipment(String quotedVehicleType) {
        Map<String, Object> fields = new Map<String, Object>{
            'attributes' => new Map<String, Object>{ 'type' => 'Shipment__c' },
            'Id' => TestDataFactory.fakeId(Shipment__c.SObjectType, ++sequence),
            'Name' => 'SHP-' + sequence,
            'Status__c' => 'Confirmed',
            'Business_Unit__c' => UNIT,
            'Weight__c' => 500,
            'Pickup_Date__c' => String.valueOf(PICKUP),
            'Expected_Delivery_Date__c' => String.valueOf(DELIVERY)
        };
        if (quotedVehicleType != null) {
            fields.put(
                'Quotation__r',
                new Map<String, Object>{
                    'attributes' => new Map<String, Object>{ 'type' => 'Quotation__c' },
                    'Rate_Card__r' => new Map<String, Object>{
                        'attributes' => new Map<String, Object>{ 'type' => 'Rate_Card__c' },
                        'Vehicle_Type__c' => quotedVehicleType
                    }
                }
            );
        }
        return (Shipment__c) JSON.deserialize(JSON.serialize(fields), Shipment__c.class);
    }

    private static Vehicle__c vehicle() {
        Vehicle__c vehicle = TestDataFactory.buildVehicle('TN-' + (++sequence), UNIT);
        vehicle.Id = TestDataFactory.fakeId(Vehicle__c.SObjectType, sequence);
        return vehicle;
    }

    private static Driver__c driver() {
        Driver__c driver = TestDataFactory.buildDriver('DL-' + (++sequence), UNIT);
        driver.Id = TestDataFactory.fakeId(Driver__c.SObjectType, sequence);
        return driver;
    }

    private static VehicleAvailabilityService.Candidate candidate(Integer index, Shipment__c shipment, Vehicle__c vehicle, Driver__c driver) {
        VehicleAvailabilityService.Candidate candidate = new VehicleAvailabilityService.Candidate();
        candidate.index = index;
        candidate.shipmentId = shipment.Id;
        candidate.vehicleId = vehicle.Id;
        candidate.driverId = driver.Id;
        candidate.startDate = shipment.Pickup_Date__c;
        candidate.endDate = shipment.Expected_Delivery_Date__c;
        candidate.startAt = AssignmentWindow.startOf(candidate.startDate);
        candidate.endAt = AssignmentWindow.endOf(candidate.endDate);
        return candidate;
    }

    private static VehicleAvailabilityService.Context context(List<Shipment__c> shipments, List<Vehicle__c> vehicles, List<Driver__c> drivers) {
        VehicleAvailabilityService.Context context = new VehicleAvailabilityService.Context();
        context.shipments = new Map<Id, Shipment__c>(shipments);
        context.vehicles = new Map<Id, Vehicle__c>(vehicles);
        context.drivers = new Map<Id, Driver__c>(drivers);
        return context;
    }

    /** Evaluates one candidate and returns its violation code, or null when it passes. */
    private static String codeFor(Shipment__c shipment, Vehicle__c vehicle, Driver__c driver, VehicleAvailabilityService.Context extra) {
        VehicleAvailabilityService.Context ctx = context(new List<Shipment__c>{ shipment }, new List<Vehicle__c>{ vehicle }, new List<Driver__c>{ driver });
        if (extra != null) {
            ctx.openAssignments = extra.openAssignments;
            ctx.maintenance = extra.maintenance;
        }
        Map<Integer, VehicleAvailabilityService.Violation> violations = new VehicleAvailabilityService()
            .evaluate(new List<VehicleAvailabilityService.Candidate>{ candidate(0, shipment, vehicle, driver) }, ctx);
        return violations.containsKey(0) ? violations.get(0).code : null;
    }

    private static String codeFor(Shipment__c shipment, Vehicle__c vehicle, Driver__c driver) {
        return codeFor(shipment, vehicle, driver, null);
    }

    /* ---------------- eligibility ---------------- */

    @IsTest
    static void aCompliantAllocationPasses() {
        Assert.isNull(codeFor(shipment(null), vehicle(), driver()));
    }

    @IsTest
    static void administrativeStatusesBlockOnlyInactiveMaintenanceAndLeave() {
        for (String status : new List<String>{ 'Available', 'Assigned', 'In Transit' }) {
            Vehicle__c ok = vehicle();
            ok.Status__c = status;
            Assert.isNull(codeFor(shipment(null), ok, driver()), 'Vehicle ' + status + ' is allocatable (Q2).');
        }
        Vehicle__c inactive = vehicle();
        inactive.Status__c = 'Inactive';
        Assert.areEqual(VehicleAvailabilityService.VEHICLE_INACTIVE, codeFor(shipment(null), inactive, driver()));
        Vehicle__c maintenance = vehicle();
        maintenance.Status__c = 'Under Maintenance';
        Assert.areEqual(VehicleAvailabilityService.VEHICLE_UNDER_MAINTENANCE, codeFor(shipment(null), maintenance, driver()));

        for (String status : new List<String>{ 'Inactive', 'On Leave' }) {
            Driver__c blocked = driver();
            blocked.Status__c = status;
            Assert.areEqual(VehicleAvailabilityService.DRIVER_UNAVAILABLE, codeFor(shipment(null), vehicle(), blocked), 'Driver ' + status);
        }
        Driver__c onDuty = driver();
        onDuty.Status__c = 'On Duty';
        Assert.isNull(codeFor(shipment(null), vehicle(), onDuty), 'On Duty is administrative availability, not a booking.');
    }

    @IsTest
    static void businessUnitsMustMatch() {
        Vehicle__c foreignVehicle = vehicle();
        foreignVehicle.Business_Unit__c = OTHER_UNIT;
        Assert.areEqual(VehicleAvailabilityService.BUSINESS_UNIT_MISMATCH, codeFor(shipment(null), foreignVehicle, driver()));
        Driver__c foreignDriver = driver();
        foreignDriver.Business_Unit__c = OTHER_UNIT;
        Assert.areEqual(VehicleAvailabilityService.BUSINESS_UNIT_MISMATCH, codeFor(shipment(null), vehicle(), foreignDriver));
    }

    @IsTest
    static void capacityMustCoverTheShipmentWeight() {
        Vehicle__c exact = vehicle();
        exact.Capacity__c = 500;
        Assert.isNull(codeFor(shipment(null), exact, driver()), 'Capacity equal to weight is enough.');
        Vehicle__c small = vehicle();
        small.Capacity__c = 499.99;
        Assert.areEqual(VehicleAvailabilityService.CAPACITY_INSUFFICIENT, codeFor(shipment(null), small, driver()));
    }

    @IsTest
    static void quotedVehicleTypeMustMatchWhenQuoted() {
        Vehicle__c trailer = vehicle();
        trailer.Vehicle_Type__c = 'Trailer';
        Assert.areEqual(VehicleAvailabilityService.VEHICLE_TYPE_MISMATCH, codeFor(shipment('LCV'), trailer, driver()));
        Assert.isNull(codeFor(shipment('LCV'), vehicle(), driver()), 'Same type as quoted.');
        Assert.isNull(codeFor(shipment(null), trailer, driver()), 'No quotation: any type with enough capacity.');
    }

    @IsTest
    static void documentsMustLastThroughTheWindowEnd() {
        Vehicle__c registrationEndsEarly = vehicle();
        registrationEndsEarly.Registration_Expiry__c = DELIVERY.addDays(-1);
        Assert.areEqual(VehicleAvailabilityService.VEHICLE_DOCUMENT_INVALID, codeFor(shipment(null), registrationEndsEarly, driver()));

        Vehicle__c insuranceMissing = vehicle();
        insuranceMissing.Insurance_Expiry__c = null;
        Assert.areEqual(VehicleAvailabilityService.VEHICLE_DOCUMENT_INVALID, codeFor(shipment(null), insuranceMissing, driver()));

        Vehicle__c lastsExactly = vehicle();
        lastsExactly.Registration_Expiry__c = DELIVERY;
        lastsExactly.Insurance_Expiry__c = DELIVERY;
        Assert.isNull(codeFor(shipment(null), lastsExactly, driver()), 'Valid on the last day of the window is enough.');

        Driver__c licenceEndsEarly = driver();
        licenceEndsEarly.License_Expiry__c = DELIVERY.addDays(-1);
        Assert.areEqual(VehicleAvailabilityService.DRIVER_LICENCE_INVALID, codeFor(shipment(null), vehicle(), licenceEndsEarly));
    }

    @IsTest
    static void fitnessIsCheckedOnlyWhenFilledIn() {
        Vehicle__c noFitness = vehicle();
        noFitness.Fitness_Expiry__c = null;
        Assert.isNull(codeFor(shipment(null), noFitness, driver()), 'Blank fitness expiry does not block (Q4).');

        Vehicle__c fitnessEndsEarly = vehicle();
        fitnessEndsEarly.Fitness_Expiry__c = DELIVERY.addDays(-1);
        Assert.areEqual(VehicleAvailabilityService.VEHICLE_DOCUMENT_INVALID, codeFor(shipment(null), fitnessEndsEarly, driver()));

        Vehicle__c fitnessLasts = vehicle();
        fitnessLasts.Fitness_Expiry__c = DELIVERY;
        Assert.isNull(codeFor(shipment(null), fitnessLasts, driver()));
    }

    @IsTest
    static void maintenanceBlocksWhenInProgressOrOverlapping() {
        Vehicle__c truck = vehicle();
        VehicleAvailabilityService.Context extra = new VehicleAvailabilityService.Context();

        extra.maintenance = new List<Vehicle_Maintenance__c>{
            new Vehicle_Maintenance__c(Vehicle__c = truck.Id, Status__c = 'In Progress', Scheduled_Date__c = Date.today().addDays(-30))
        };
        Assert.areEqual(VehicleAvailabilityService.MAINTENANCE_CONFLICT, codeFor(shipment(null), truck, driver(), extra), 'Ongoing job without completion date blocks.');

        extra.maintenance = new List<Vehicle_Maintenance__c>{ new Vehicle_Maintenance__c(Vehicle__c = truck.Id, Status__c = 'Scheduled', Scheduled_Date__c = DELIVERY) };
        Assert.areEqual(VehicleAvailabilityService.MAINTENANCE_CONFLICT, codeFor(shipment(null), truck, driver(), extra), 'Scheduled on the last day.');

        extra.maintenance = new List<Vehicle_Maintenance__c>{
            new Vehicle_Maintenance__c(Vehicle__c = truck.Id, Status__c = 'Scheduled', Scheduled_Date__c = PICKUP.addDays(-2), Completion_Date__c = PICKUP)
        };
        Assert.areEqual(VehicleAvailabilityService.MAINTENANCE_CONFLICT, codeFor(shipment(null), truck, driver(), extra), 'A multi-day period running into the window.');

        extra.maintenance = new List<Vehicle_Maintenance__c>{
            new Vehicle_Maintenance__c(Vehicle__c = truck.Id, Status__c = 'Scheduled', Scheduled_Date__c = PICKUP.addDays(-1)),
            new Vehicle_Maintenance__c(Vehicle__c = truck.Id, Status__c = 'Scheduled', Scheduled_Date__c = DELIVERY.addDays(1))
        };
        Assert.isNull(codeFor(shipment(null), truck, driver(), extra), 'The day before and the day after do not overlap.');
    }

    @IsTest
    static void windowAndRecordsMustBeUsable() {
        Shipment__c noDates = shipment(null);
        VehicleAvailabilityService.Candidate broken = candidate(0, noDates, vehicle(), driver());
        broken.endDate = broken.startDate.addDays(-1);
        Vehicle__c truck = vehicle();
        Driver__c person = driver();
        broken.vehicleId = truck.Id;
        broken.driverId = person.Id;
        Map<Integer, VehicleAvailabilityService.Violation> violations = new VehicleAvailabilityService()
            .evaluate(
                new List<VehicleAvailabilityService.Candidate>{ broken },
                context(new List<Shipment__c>{ noDates }, new List<Vehicle__c>{ truck }, new List<Driver__c>{ person })
            );
        Assert.areEqual(VehicleAvailabilityService.WINDOW_INVALID, violations.get(0).code);

        VehicleAvailabilityService.Candidate orphan = candidate(0, shipment(null), truck, person);
        Map<Integer, VehicleAvailabilityService.Violation> missingShipment = new VehicleAvailabilityService()
            .evaluate(new List<VehicleAvailabilityService.Candidate>{ orphan }, new VehicleAvailabilityService.Context());
        Assert.areEqual(VehicleAvailabilityService.SHIPMENT_REQUIRED, missingShipment.get(0).code);

        Shipment__c known = shipment(null);
        Map<Integer, VehicleAvailabilityService.Violation> missingVehicle = new VehicleAvailabilityService()
            .evaluate(
                new List<VehicleAvailabilityService.Candidate>{ candidate(0, known, truck, person) },
                context(new List<Shipment__c>{ known }, new List<Vehicle__c>(), new List<Driver__c>{ person })
            );
        Assert.areEqual(VehicleAvailabilityService.RECORD_NOT_FOUND, missingVehicle.get(0).code);
    }

    /* ---------------- bookings (Q1, Q9) ---------------- */

    private static Vehicle_Assignment__c booked(Id shipmentId, Id vehicleId, Id driverId, Date fromDay, Date toDay) {
        return new Vehicle_Assignment__c(
            Id = TestDataFactory.fakeId(Vehicle_Assignment__c.SObjectType, ++sequence),
            Shipment__c = shipmentId,
            Vehicle__c = vehicleId,
            Driver__c = driverId,
            Status__c = 'Planned',
            Assignment_Start__c = AssignmentWindow.startOf(fromDay),
            Assignment_End__c = AssignmentWindow.endOf(toDay)
        );
    }

    @IsTest
    static void storedOverlappingBookingsConflict() {
        Vehicle__c truck = vehicle();
        Driver__c person = driver();
        Id elsewhere = TestDataFactory.fakeId(Shipment__c.SObjectType, 999);
        VehicleAvailabilityService.Context extra = new VehicleAvailabilityService.Context();

        extra.openAssignments = new List<Vehicle_Assignment__c>{ booked(elsewhere, truck.Id, driver().Id, DELIVERY, DELIVERY.addDays(2)) };
        Assert.areEqual(VehicleAvailabilityService.VEHICLE_DOUBLE_BOOKED, codeFor(shipment(null), truck, person, extra));

        extra.openAssignments = new List<Vehicle_Assignment__c>{ booked(elsewhere, vehicle().Id, person.Id, PICKUP.addDays(-3), PICKUP) };
        Assert.areEqual(VehicleAvailabilityService.DRIVER_DOUBLE_BOOKED, codeFor(shipment(null), truck, person, extra));

        extra.openAssignments = new List<Vehicle_Assignment__c>{
            booked(elsewhere, truck.Id, person.Id, PICKUP.addDays(-3), PICKUP.addDays(-1)),
            booked(elsewhere, truck.Id, person.Id, DELIVERY.addDays(1), DELIVERY.addDays(4))
        };
        Assert.isNull(codeFor(shipment(null), truck, person, extra), 'Back-to-back days do not overlap.');
    }

    @IsTest
    static void oneOpenAssignmentPerShipmentAndSelfIsIgnored() {
        Shipment__c consignment = shipment(null);
        Vehicle__c truck = vehicle();
        Driver__c person = driver();
        Vehicle_Assignment__c existing = booked(consignment.Id, vehicle().Id, driver().Id, Date.today().addDays(40), Date.today().addDays(41));
        VehicleAvailabilityService.Context extra = new VehicleAvailabilityService.Context();
        extra.openAssignments = new List<Vehicle_Assignment__c>{ existing };
        Assert.areEqual(VehicleAvailabilityService.SHIPMENT_ALREADY_ALLOCATED, codeFor(consignment, truck, person, extra));

        // Re-evaluating that same assignment (a reallocation) does not conflict with itself.
        VehicleAvailabilityService.Candidate self = candidate(0, consignment, truck, person);
        self.assignmentId = existing.Id;
        VehicleAvailabilityService.Context ctx = context(new List<Shipment__c>{ consignment }, new List<Vehicle__c>{ truck }, new List<Driver__c>{ person });
        ctx.openAssignments = new List<Vehicle_Assignment__c>{ existing };
        Assert.isTrue(new VehicleAvailabilityService().evaluate(new List<VehicleAvailabilityService.Candidate>{ self }, ctx).isEmpty());
    }

    @IsTest
    static void conflictsWithinOneBatchAreDetected() {
        Shipment__c first = shipment(null);
        Shipment__c second = shipment(null);
        Shipment__c later = shipment(null);
        later.Pickup_Date__c = DELIVERY.addDays(1);
        later.Expected_Delivery_Date__c = DELIVERY.addDays(2);
        Vehicle__c truck = vehicle();
        Vehicle__c spare = vehicle();
        Driver__c person = driver();
        Driver__c relief = driver();
        VehicleAvailabilityService.Context ctx = context(
            new List<Shipment__c>{ first, second, later },
            new List<Vehicle__c>{ truck, spare },
            new List<Driver__c>{ person, relief }
        );

        Map<Integer, VehicleAvailabilityService.Violation> violations = new VehicleAvailabilityService()
            .evaluate(
                new List<VehicleAvailabilityService.Candidate>{
                    candidate(0, first, truck, person),
                    candidate(1, second, truck, relief), // same vehicle, same window
                    candidate(2, second, spare, person), // same driver, same window
                    candidate(3, later, truck, person), // same vehicle and driver, later window
                    candidate(4, first, spare, relief) // same shipment twice
                },
                ctx
            );

        Assert.isFalse(violations.containsKey(0));
        Assert.areEqual(VehicleAvailabilityService.VEHICLE_DOUBLE_BOOKED, violations.get(1).code);
        Assert.areEqual(VehicleAvailabilityService.DRIVER_DOUBLE_BOOKED, violations.get(2).code);
        Assert.isFalse(violations.containsKey(3), 'A later booking for the same vehicle and driver is allowed.');
        Assert.areEqual(VehicleAvailabilityService.SHIPMENT_ALREADY_ALLOCATED, violations.get(4).code);
    }

    /* ---------------- windows (Q3) ---------------- */

    @IsTest
    static void windowsUseOrgTimeBoundaries() {
        Date day = Date.newInstance(2026, 12, 1);
        String tz = [SELECT TimeZoneSidKey FROM Organization LIMIT 1].TimeZoneSidKey;
        Assert.areEqual('2026-12-01 00:00:00', AssignmentWindow.startOf(day).format('yyyy-MM-dd HH:mm:ss', tz));
        Assert.areEqual('2026-12-01 23:59:59', AssignmentWindow.endOf(day).format('yyyy-MM-dd HH:mm:ss', tz));

        Datetime dayEnd = AssignmentWindow.endOf(day);
        Datetime nextStart = AssignmentWindow.startOf(day.addDays(1));
        Assert.isFalse(AssignmentWindow.overlaps(AssignmentWindow.startOf(day), dayEnd, nextStart, AssignmentWindow.endOf(day.addDays(1))));
        Assert.isTrue(AssignmentWindow.overlaps(AssignmentWindow.startOf(day), dayEnd, AssignmentWindow.startOf(day), null), 'Open-ended overlaps.');
        Assert.isTrue(AssignmentWindow.overlapsDays(day, day, day, day.addDays(1)));
        Assert.isFalse(AssignmentWindow.overlapsDays(day, day, day.addDays(1), null));
    }
}
