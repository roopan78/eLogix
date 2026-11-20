// eLogix ERP - Phase 5 post-deploy verification, part 3 of 3: Active trips (D3) and cancellation after dispatch (D2).
//
// Runs against the live org as the executing user (an administrator holding eLogix_Administrator,
// which includes eLogix_Cancel_Confirmed_Shipment), then rolls everything back. Runs in its own
// transaction to stay well inside the 100-query limit.
//
//   sf apex run --file scripts/apex/verify-phase5-cancellation.apex --target-org eLogixDev
//
// Expect "SMOKE SUMMARY checks=3 failures=0" in the output.

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
Savepoint savepoint = Database.setSavepoint();
try {
    Business_Unit__c businessUnit = new Business_Unit__c(Name = 'Smoke Business Unit P5C', Business_Unit_Code__c = 'SMOKE-P5C', Region__c = 'South', Is_Active__c = true);
    insert businessUnit;
    Account customer = new Account(Name = 'Smoke Phase Five Cancellation Traders', BillingStreet = '9 Mount Road', BillingCity = 'Chennai', BillingPostalCode = '600002', Is_Active_Customer__c = true, Business_Unit__c = businessUnit.Id);
    insert customer;
    // Shipment 0 goes on the road; shipment 1 starts after shipment 0's planned window ends.
    // Quoted is an allowed initial status; starting there keeps this script within its query budget.
    List<Shipment__c> shipments = new List<Shipment__c>();
    for (Integer i = 0; i < 2; i++) {
        Boolean later = i == 1;
        shipments.add(
            new Shipment__c(
                Customer__c = customer.Id, Business_Unit__c = businessUnit.Id, Origin__c = 'Chennai', Destination__c = 'Bangalore',
                Weight__c = 500, Distance__c = 350, Priority__c = 'Standard', Status__c = 'Quoted',
                Pickup_Date__c = later ? Date.today().addDays(6) : Date.today(),
                Expected_Delivery_Date__c = later ? Date.today().addDays(8) : Date.today().addDays(2)
            )
        );
    }
    insert shipments;
    insert new List<Shipment_Item__c>{
        new Shipment_Item__c(Shipment__c = shipments[0].Id, Item_Name__c = 'Pump', SKU__c = 'SMOKE-P5', Quantity__c = 1, Weight__c = 50, Package_Type__c = 'Crate'),
        new Shipment_Item__c(Shipment__c = shipments[1].Id, Item_Name__c = 'Pump', SKU__c = 'SMOKE-P5', Quantity__c = 1, Weight__c = 50, Package_Type__c = 'Crate')
    };
    update new List<Shipment__c>{ new Shipment__c(Id = shipments[0].Id, Status__c = 'Confirmed'), new Shipment__c(Id = shipments[1].Id, Status__c = 'Confirmed') };

    Date valid = Date.today().addDays(365);
    Vehicle__c truck = new Vehicle__c(Name = 'Smoke P5C Truck', Vehicle_Number__c = 'SMOKE-P5C-1', Vehicle_Type__c = 'LCV', Capacity__c = 1000, Business_Unit__c = businessUnit.Id, Registration_Expiry__c = valid, Insurance_Expiry__c = valid, Status__c = 'Available');
    insert truck;
    List<Driver__c> drivers = new List<Driver__c>{
        new Driver__c(Name = 'Smoke P5C Driver 1', License_Number__c = 'SMOKE-P5C-DL1', License_Expiry__c = valid, Business_Unit__c = businessUnit.Id, Status__c = 'Available'),
        new Driver__c(Name = 'Smoke P5C Driver 2', License_Number__c = 'SMOKE-P5C-DL2', License_Expiry__c = valid, Business_Unit__c = businessUnit.Id, Status__c = 'Available')
    };
    insert drivers;
    new FleetAllocationService().allocate(new List<AllocationRequest>{ new AllocationRequest(shipments[0].Id, truck.Id, drivers[0].Id) });
    for (String status : new List<String>{ 'Ready for Dispatch', 'Dispatched' }) {
        update new Shipment__c(Id = shipments[0].Id, Status__c = status);
    }

    // D3: the Active trip holds its truck beyond its planned window.
    ServiceResult blocked = new FleetAllocationService().allocate(new List<AllocationRequest>{ new AllocationRequest(shipments[1].Id, truck.Id, drivers[1].Id) });
    smoke.check('an Active trip blocks its truck after its planned window (D3)', !blocked.isSuccess && smoke.firstError(blocked).contains('overlaps'), smoke.firstError(blocked));

    // D2: cancellation after dispatch, with an open delivery attempt.
    update new Shipment__c(Id = shipments[0].Id, Status__c = 'In Transit');
    new DeliveryService().startAttempts(new List<Id>{ shipments[0].Id });
    update new Shipment__c(Id = shipments[0].Id, Status__c = 'Delayed');
    update new Shipment__c(Id = shipments[0].Id, Status__c = 'On Hold', Hold_Reason__c = 'Smoke dispute.');
    update new Shipment__c(Id = shipments[0].Id, Status__c = 'Cancelled', Cancellation_Reason__c = 'Smoke cancellation after dispatch.');
    Delivery__c closed = [SELECT Delivery_Status__c, Failure_Reason__c FROM Delivery__c WHERE Shipment__c = :shipments[0].Id];
    String trip = [SELECT Status__c FROM Vehicle_Assignment__c WHERE Shipment__c = :shipments[0].Id].Status__c;
    smoke.check(
        'cancellation after dispatch closes the attempt (Other) and completes the trip (D2)',
        closed.Delivery_Status__c == 'Failed' && closed.Failure_Reason__c == 'Other' && trip == 'Completed',
        closed.Delivery_Status__c + ' / ' + closed.Failure_Reason__c + ' / ' + trip
    );
} finally {
    Database.rollback(savepoint);
}
smoke.check(
    'no rows left behind',
    [SELECT COUNT() FROM Delivery__c] + [SELECT COUNT() FROM Vehicle_Assignment__c] + [SELECT COUNT() FROM Business_Unit__c WHERE Business_Unit_Code__c = 'SMOKE-P5C'] == 0,
    'rows remain'
);
System.debug(LoggingLevel.ERROR, 'SMOKE SUMMARY checks=' + smoke.checks + ' failures=' + smoke.failures);
