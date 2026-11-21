// eLogix ERP - Phase 4 post-deploy verification (fleet allocation).
//
// Runs against the live org as the executing user (an administrator holding eLogix_Administrator,
// which includes eLogix_Allocate_Fleet), then rolls everything back. Exercises the live trigger,
// formulas, settings, the Ready for Dispatch guard and the cancellation auto-release.
//
//   sf apex run --file scripts/apex/verify-phase4-fleet.apex --target-org eLogixDev
//
// Expect "SMOKE SUMMARY checks=20 failures=0" in the output.

class Smoke {
    Integer checks = 0;
    Integer failures = 0;

    void check(String name, Boolean passed, String detail) {
        checks++;
        if (!passed) {
            failures++;
        }
        System.debug(LoggingLevel.ERROR, 'SMOKE ' + (passed ? 'PASS ' : 'FAIL ') + name + (passed ? '' : ' | ' + detail));
    }

    String firstError(ServiceResult result) {
        return result.isSuccess ? '(saved)' : result.errors[0].message;
    }
}

Smoke smoke = new Smoke();
smoke.check(
    'expiry warning setting deployed (30 days)',
    SettingsService.getNumber('Document_Expiry_Warning_Days') == 30,
    String.valueOf(SettingsService.getNumber('Document_Expiry_Warning_Days'))
);
smoke.check('allocate permission held by the executing administrator', FeatureManagement.checkPermission('eLogix_Allocate_Fleet'), 'missing');

Savepoint savepoint = Database.setSavepoint();
try {
    Business_Unit__c businessUnit = new Business_Unit__c(Name = 'Smoke Business Unit P4', Business_Unit_Code__c = 'SMOKE-P4', Region__c = 'South', Is_Active__c = true);
    insert businessUnit;
    Account customer = new Account(
        Name = 'Smoke Phase Four Engineering',
        BillingStreet = '12 Anna Salai',
        BillingCity = 'Chennai',
        BillingPostalCode = '600002',
        Is_Active_Customer__c = true,
        Business_Unit__c = businessUnit.Id
    );
    insert customer;

    List<Shipment__c> shipments = new List<Shipment__c>();
    for (Integer i = 0; i < 4; i++) {
        shipments.add(
            new Shipment__c(
                Customer__c = customer.Id,
                Business_Unit__c = businessUnit.Id,
                Origin__c = 'Chennai',
                Destination__c = 'Bangalore',
                Weight__c = 500,
                Distance__c = 350,
                Pickup_Date__c = Date.today().addDays(1),
                Expected_Delivery_Date__c = Date.today().addDays(3),
                Priority__c = 'Standard',
                Status__c = 'Draft'
            )
        );
    }
    insert shipments;
    List<Shipment_Item__c> items = new List<Shipment_Item__c>();
    for (Shipment__c shipment : shipments) {
        items.add(new Shipment_Item__c(Shipment__c = shipment.Id, Item_Name__c = 'Industrial pump', SKU__c = 'SMOKE-P4', Quantity__c = 2, Weight__c = 50, Package_Type__c = 'Crate'));
    }
    insert items;
    for (String status : new List<String>{ 'Requested', 'Quoted', 'Confirmed' }) {
        for (Shipment__c shipment : shipments) {
            shipment.Status__c = status;
        }
        update shipments;
    }

    Date valid = Date.today().addDays(365);
    Vehicle__c compliant = new Vehicle__c(Name = 'Smoke Truck A', Vehicle_Number__c = 'SMOKE-P4-A', Vehicle_Type__c = 'LCV', Capacity__c = 1000, Business_Unit__c = businessUnit.Id, Registration_Expiry__c = valid, Insurance_Expiry__c = valid, Status__c = 'Available');
    Vehicle__c uninsured = new Vehicle__c(Name = 'Smoke Truck B', Vehicle_Number__c = 'SMOKE-P4-B', Vehicle_Type__c = 'LCV', Capacity__c = 1000, Business_Unit__c = businessUnit.Id, Registration_Expiry__c = valid, Insurance_Expiry__c = Date.today().addDays(2), Status__c = 'Available');
    Vehicle__c small = new Vehicle__c(Name = 'Smoke Truck C', Vehicle_Number__c = 'SMOKE-P4-C', Vehicle_Type__c = 'LCV', Capacity__c = 200, Business_Unit__c = businessUnit.Id, Registration_Expiry__c = valid, Insurance_Expiry__c = valid, Status__c = 'Available');
    Vehicle__c serviced = new Vehicle__c(Name = 'Smoke Truck D', Vehicle_Number__c = 'SMOKE-P4-D', Vehicle_Type__c = 'LCV', Capacity__c = 1000, Business_Unit__c = businessUnit.Id, Registration_Expiry__c = valid, Insurance_Expiry__c = valid, Status__c = 'Available');
    insert new List<Vehicle__c>{ compliant, uninsured, small, serviced };
    Driver__c ravi = new Driver__c(Name = 'Smoke Driver Ravi', License_Number__c = 'SMOKE-P4-DL1', License_Expiry__c = valid, Business_Unit__c = businessUnit.Id, Status__c = 'Available');
    Driver__c meena = new Driver__c(Name = 'Smoke Driver Meena', License_Number__c = 'SMOKE-P4-DL2', License_Expiry__c = valid, Business_Unit__c = businessUnit.Id, Status__c = 'Available');
    insert new List<Driver__c>{ ravi, meena };
    insert new Vehicle_Maintenance__c(Vehicle__c = serviced.Id, Maintenance_Type__c = 'Preventive', Scheduled_Date__c = Date.today().addDays(2), Status__c = 'Scheduled');

    Vehicle__c statusRow = [SELECT Document_Status__c, Is_Allocatable__c FROM Vehicle__c WHERE Id = :uninsured.Id];
    smoke.check(
        'insurance expiring in 2 days: Expiring Soon, still allocatable today (Q15)',
        statusRow.Document_Status__c == 'Expiring Soon' && statusRow.Is_Allocatable__c,
        statusRow.Document_Status__c + ' / ' + statusRow.Is_Allocatable__c
    );

    FleetAllocationService service = new FleetAllocationService();
    ServiceResult uninsuredResult = service.allocate(new List<AllocationRequest>{ new AllocationRequest(shipments[1].Id, uninsured.Id, meena.Id) });
    smoke.check('insurance ending inside the window rejected (Q4)', smoke.firstError(uninsuredResult).contains('cannot be allocated: its'), smoke.firstError(uninsuredResult));

    ServiceResult smallResult = service.allocate(new List<AllocationRequest>{ new AllocationRequest(shipments[1].Id, small.Id, meena.Id) });
    smoke.check('capacity below the shipment weight rejected (Q6)', smoke.firstError(smallResult).contains('carries up to'), smoke.firstError(smallResult));

    ServiceResult servicedResult = service.allocate(new List<AllocationRequest>{ new AllocationRequest(shipments[1].Id, serviced.Id, meena.Id) });
    smoke.check('scheduled maintenance inside the window rejected (Q5)', smoke.firstError(servicedResult).contains('maintenance in progress or scheduled'), smoke.firstError(servicedResult));

    ServiceResult allocated = service.allocate(new List<AllocationRequest>{ new AllocationRequest(shipments[0].Id, compliant.Id, ravi.Id) });
    Shipment__c mirrored = [SELECT Vehicle__c, Driver__c FROM Shipment__c WHERE Id = :shipments[0].Id];
    smoke.check(
        'compliant allocation saved and mirrored to the shipment (Q18)',
        allocated.isSuccess && mirrored.Vehicle__c == compliant.Id && mirrored.Driver__c == ravi.Id,
        smoke.firstError(allocated)
    );

    // A compliant truck with enough capacity, so the request passes every earlier rule and reaches the
    // driver-overlap rule: same driver, same (overlapping) window as the booking above.
    Vehicle__c relief = new Vehicle__c(Name = 'Smoke Truck F', Vehicle_Number__c = 'SMOKE-P4-F', Vehicle_Type__c = 'LCV', Capacity__c = 1000, Business_Unit__c = businessUnit.Id, Registration_Expiry__c = valid, Insurance_Expiry__c = valid, Status__c = 'Available');
    insert relief;
    ServiceResult doubleBooked = service.allocate(new List<AllocationRequest>{ new AllocationRequest(shipments[1].Id, relief.Id, ravi.Id) });
    smoke.check(
        'overlapping driver booking rejected (Q1)',
        !doubleBooked.isSuccess && smoke.firstError(doubleBooked) == String.format(Label.eLogix_Fleet_Driver_Double_Booked, new List<Object>{ ravi.Name }),
        smoke.firstError(doubleBooked)
    );

    Database.SaveResult unallocated = Database.update(new Shipment__c(Id = shipments[2].Id, Status__c = 'Ready for Dispatch'), false);
    smoke.check(
        'Ready for Dispatch refused without an allocation (Q10)',
        !unallocated.isSuccess() && unallocated.getErrors()[0].getMessage().contains(Label.eLogix_Fleet_Allocation_Required),
        unallocated.isSuccess() ? '(saved)' : unallocated.getErrors()[0].getMessage()
    );

    Database.SaveResult ready = Database.update(new Shipment__c(Id = shipments[0].Id, Status__c = 'Ready for Dispatch'), false);
    smoke.check('Ready for Dispatch allowed with a verified allocation', ready.isSuccess(), ready.isSuccess() ? '' : ready.getErrors()[0].getMessage());

    ServiceResult lateChange = service.reallocate(new List<AllocationRequest>{ new AllocationRequest(shipments[0].Id, compliant.Id, meena.Id) });
    smoke.check('no reallocation at Ready for Dispatch (Q9)', !lateChange.isSuccess, 'reallocated');

    Id dispatchedAssignment = [SELECT Id FROM Vehicle_Assignment__c WHERE Shipment__c = :shipments[0].Id].Id;
    Database.DeleteResult deleted = Database.delete(dispatchedAssignment, false);
    smoke.check(
        'assignment delete refused, even for an administrator (audit fix 1)',
        !deleted.isSuccess() && deleted.getErrors()[0].getMessage() == Label.eLogix_Fleet_Delete_Not_Allowed,
        deleted.isSuccess() ? '(deleted)' : deleted.getErrors()[0].getMessage()
    );

    update new Shipment__c(Id = shipments[0].Id, Status__c = 'On Hold', Hold_Reason__c = 'Smoke test hold.');
    ServiceResult heldChange = service.reallocate(new List<AllocationRequest>{ new AllocationRequest(shipments[0].Id, compliant.Id, meena.Id) });
    smoke.check(
        'On Hold after Ready for Dispatch keeps the allocation locked (Q9, tracking history)',
        !heldChange.isSuccess && heldChange.errors[0].message.contains('already reached Ready for Dispatch'),
        smoke.firstError(heldChange)
    );

    AllocationRequest fix = new AllocationRequest(shipments[0].Id, compliant.Id, ravi.Id);
    fix.correctionReason = 'Smoke test correction.';
    ServiceResult corrected = service.correctDispatchedAllocation(new List<AllocationRequest>{ fix });
    Integer correctionEvents = [SELECT COUNT() FROM Tracking_Event__c WHERE Shipment__c = :shipments[0].Id AND Event_Type__c = 'Exception' AND To_Status__c = NULL];
    smoke.check(
        'controlled correction while On Hold is revalidated and recorded in tracking history (round 3)',
        corrected.isSuccess && correctionEvents == 1,
        smoke.firstError(corrected) + ' / events=' + correctionEvents
    );

    Database.DeleteResult shipmentDelete = Database.delete(shipments[0].Id, false);
    smoke.check(
        'a shipment with an open assignment cannot be deleted (round 3)',
        !shipmentDelete.isSuccess() && shipmentDelete.getErrors()[0].getMessage().contains('still has a Planned or Active vehicle assignment'),
        shipmentDelete.isSuccess() ? '(deleted)' : shipmentDelete.getErrors()[0].getMessage()
    );

    Vehicle__c spare = new Vehicle__c(Name = 'Smoke Truck E', Vehicle_Number__c = 'SMOKE-P4-E', Vehicle_Type__c = 'LCV', Capacity__c = 1000, Business_Unit__c = businessUnit.Id, Registration_Expiry__c = valid, Insurance_Expiry__c = valid, Status__c = 'Available');
    insert spare;
    ServiceResult second = service.allocate(new List<AllocationRequest>{ new AllocationRequest(shipments[3].Id, spare.Id, meena.Id) });
    update new Shipment__c(Id = shipments[3].Id, Weight__c = 1500);
    Database.SaveResult overweight = Database.update(new Shipment__c(Id = shipments[3].Id, Status__c = 'Ready for Dispatch'), false);
    smoke.check(
        'Ready for Dispatch revalidates: weight raised above capacity after allocation is refused (audit fix 3)',
        !overweight.isSuccess() && overweight.getErrors()[0].getMessage().contains('carries up to'),
        overweight.isSuccess() ? '(saved)' : overweight.getErrors()[0].getMessage()
    );
    update new Shipment__c(Id = shipments[3].Id, Weight__c = 500, Status__c = 'Cancelled', Cancellation_Reason__c = 'Smoke test cancellation.');
    Vehicle_Assignment__c released = [SELECT Status__c FROM Vehicle_Assignment__c WHERE Shipment__c = :shipments[3].Id];
    Shipment__c cleared = [SELECT Vehicle__c, Driver__c FROM Shipment__c WHERE Id = :shipments[3].Id];
    smoke.check(
        'cancelling the shipment released its assignment and cleared the mirror (Q11)',
        second.isSuccess && released.Status__c == 'Cancelled' && cleared.Vehicle__c == null && cleared.Driver__c == null,
        smoke.firstError(second) + ' / ' + released.Status__c
    );

    try {
        new VehicleAssignmentDomain().syncShipments();
        smoke.check('shipment mirror refused outside the trigger', false, 'no exception');
    } catch (AuthorizationException e) {
        smoke.check('shipment mirror refused outside the trigger', e.code == VehicleAssignmentDomain.MIRROR_TRIGGER_ONLY, e.code);
    }
    try {
        new FleetAllocationService().releaseCancelledShipmentAssignments();
        smoke.check('cancellation release refused outside the trigger', false, 'no exception');
    } catch (AuthorizationException e) {
        smoke.check('cancellation release refused outside the trigger', e.code == FleetAllocationService.CANCELLATION_TRIGGER_ONLY, e.code);
    }
} finally {
    Database.rollback(savepoint);
}
smoke.check(
    'no rows left behind',
    [SELECT COUNT() FROM Vehicle_Assignment__c] + [SELECT COUNT() FROM Vehicle__c WHERE Vehicle_Number__c LIKE 'SMOKE-P4%'] +
    [SELECT COUNT() FROM Business_Unit__c WHERE Business_Unit_Code__c = 'SMOKE-P4'] == 0,
    'rows remain'
);
System.debug(LoggingLevel.ERROR, 'SMOKE SUMMARY checks=' + smoke.checks + ' failures=' + smoke.failures);
