// eLogix ERP - Phase 5 post-deploy verification, part 2 of 3: failed attempts, retries and guards.
//
// Runs against the live org as the executing user (an administrator holding eLogix_Administrator),
// then rolls everything back. Runs in its own transaction to stay well inside the 100-query limit.
//
//   sf apex run --file scripts/apex/verify-phase5-retries.apex --target-org eLogixDev
//
// Expect "SMOKE SUMMARY checks=7 failures=0" in the output.

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

    String firstError(Database.SaveResult result) {
        return result.isSuccess() ? '(saved)' : result.getErrors()[0].getMessage();
    }

    /** Shipment status and its trip (assignment) status, in one query: "Status / Trip". */
    String state(Id shipmentId) {
        Shipment__c shipment = [SELECT Status__c, (SELECT Status__c FROM Vehicle_Assignments__r) FROM Shipment__c WHERE Id = :shipmentId];
        return shipment.Status__c + ' / ' + (shipment.Vehicle_Assignments__r.isEmpty() ? '-' : shipment.Vehicle_Assignments__r[0].Status__c);
    }
}

Smoke smoke = new Smoke();
Savepoint savepoint = Database.setSavepoint();
try {
    Business_Unit__c businessUnit = new Business_Unit__c(Name = 'Smoke Business Unit P5B', Business_Unit_Code__c = 'SMOKE-P5B', Region__c = 'South', Is_Active__c = true);
    insert businessUnit;
    Account customer = new Account(Name = 'Smoke Phase Five Retry Traders', BillingStreet = '9 Mount Road', BillingCity = 'Chennai', BillingPostalCode = '600002', Is_Active_Customer__c = true, Business_Unit__c = businessUnit.Id);
    insert customer;
    // Quoted is an allowed initial status; starting there keeps this script within its query budget.
    Shipment__c shipment = new Shipment__c(
        Customer__c = customer.Id, Business_Unit__c = businessUnit.Id, Origin__c = 'Chennai', Destination__c = 'Bangalore',
        Weight__c = 500, Distance__c = 350, Priority__c = 'Standard', Status__c = 'Quoted',
        Pickup_Date__c = Date.today(), Expected_Delivery_Date__c = Date.today().addDays(2)
    );
    insert shipment;
    insert new Shipment_Item__c(Shipment__c = shipment.Id, Item_Name__c = 'Pump', SKU__c = 'SMOKE-P5', Quantity__c = 1, Weight__c = 50, Package_Type__c = 'Crate');
    update new Shipment__c(Id = shipment.Id, Status__c = 'Confirmed');

    Date valid = Date.today().addDays(365);
    Vehicle__c truck = new Vehicle__c(Name = 'Smoke P5B Truck', Vehicle_Number__c = 'SMOKE-P5B-1', Vehicle_Type__c = 'LCV', Capacity__c = 1000, Business_Unit__c = businessUnit.Id, Registration_Expiry__c = valid, Insurance_Expiry__c = valid, Status__c = 'Available');
    insert truck;
    Driver__c driver = new Driver__c(Name = 'Smoke P5B Driver', License_Number__c = 'SMOKE-P5B-DL1', License_Expiry__c = valid, Business_Unit__c = businessUnit.Id, Status__c = 'Available');
    insert driver;
    new FleetAllocationService().allocate(new List<AllocationRequest>{ new AllocationRequest(shipment.Id, truck.Id, driver.Id) });
    for (String status : new List<String>{ 'Ready for Dispatch', 'Dispatched', 'In Transit' }) {
        update new Shipment__c(Id = shipment.Id, Status__c = status);
    }

    // Failed attempt and retry on the same trip.
    DeliveryService deliveries = new DeliveryService();
    deliveries.startAttempts(new List<Id>{ shipment.Id });
    ServiceResult failed = deliveries.recordFailures(new List<DeliveryFailureRequest>{ new DeliveryFailureRequest(shipment.Id, 'Consignee Unavailable') });
    String afterFailure = smoke.state(shipment.Id);
    smoke.check('failed attempt: shipment Failed Delivery, trip stays Active', failed.isSuccess && afterFailure == 'Failed Delivery / Active', smoke.firstError(failed) + ' / ' + afterFailure);

    ServiceResult retry = deliveries.startAttempts(new List<Id>{ shipment.Id });
    Integer trips = [SELECT COUNT() FROM Vehicle_Assignment__c WHERE Shipment__c = :shipment.Id];
    Integer secondAttempts = [SELECT COUNT() FROM Delivery__c WHERE Shipment__c = :shipment.Id AND Attempt_Number__c = 2];
    smoke.check('retry is attempt 2 on the same assignment', retry.isSuccess && trips == 1 && secondAttempts == 1, smoke.firstError(retry) + ' / trips=' + trips);

    // Event key fix: both Out for Delivery events are recorded, with distinct sequenced keys, although
    // this script runs within a second or two.
    Set<String> outKeys = new Set<String>();
    for (Tracking_Event__c event : [SELECT Event_Key__c FROM Tracking_Event__c WHERE Shipment__c = :shipment.Id AND To_Status__c = 'Out for Delivery']) {
        outKeys.add(event.Event_Key__c);
    }
    smoke.check('each delivery attempt has its own status event (sequenced key)', outKeys.size() == 2, 'events=' + outKeys);

    Database.SaveResult jump = Database.update(new Shipment__c(Id = shipment.Id, Status__c = 'Delivered', Actual_Delivery_Date__c = Date.today()), false);
    smoke.check('Delivered without a confirmed attempt is refused (delivery guard)', !jump.isSuccess(), smoke.firstError(jump));

    try {
        new DeliveryService().closeAttemptsOfCancelledShipments();
        smoke.check('attempt closure refused outside the trigger', false, 'no exception');
    } catch (AuthorizationException e) {
        smoke.check('attempt closure refused outside the trigger', e.code == DeliveryService.CANCELLATION_TRIGGER_ONLY, e.code);
    }
    try {
        new FleetAllocationService().advanceAssignmentLifecycle();
        smoke.check('assignment lifecycle refused outside the trigger', false, 'no exception');
    } catch (AuthorizationException e) {
        smoke.check('assignment lifecycle refused outside the trigger', e.code == FleetAllocationService.LIFECYCLE_TRIGGER_ONLY, e.code);
    }
} finally {
    Database.rollback(savepoint);
}
smoke.check(
    'no rows left behind',
    [SELECT COUNT() FROM Delivery__c] + [SELECT COUNT() FROM Vehicle_Assignment__c] + [SELECT COUNT() FROM Business_Unit__c WHERE Business_Unit_Code__c = 'SMOKE-P5B'] == 0,
    'rows remain'
);
System.debug(LoggingLevel.ERROR, 'SMOKE SUMMARY checks=' + smoke.checks + ' failures=' + smoke.failures);
