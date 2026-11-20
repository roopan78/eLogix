// eLogix ERP - Phase 5 post-deploy verification, part 1 of 3: dispatch, delivery confirmation and evidence.
//
// Runs against the live org as the executing user (an administrator holding eLogix_Administrator),
// then rolls everything back. Each Phase 5 script runs one full shipment lifecycle in its own
// transaction, so each stays well inside the 100-query limit for anonymous Apex.
//
//   sf apex run --file scripts/apex/verify-phase5-delivery.apex --target-org eLogixDev
//   (then verify-phase5-retries.apex and verify-phase5-cancellation.apex)
//
// Expect "SMOKE SUMMARY checks=11 failures=0" in the output.

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
smoke.check(
    'delivery settings deployed (3 attempts, file required)',
    SettingsService.getNumber('Max_Delivery_Attempts') == 3 && SettingsService.getBoolean('POD_File_Required') == true,
    SettingsService.getNumber('Max_Delivery_Attempts') + ' / ' + SettingsService.getBoolean('POD_File_Required')
);

Savepoint savepoint = Database.setSavepoint();
try {
    Business_Unit__c businessUnit = new Business_Unit__c(Name = 'Smoke Business Unit P5A', Business_Unit_Code__c = 'SMOKE-P5A', Region__c = 'South', Is_Active__c = true);
    insert businessUnit;
    Account customer = new Account(Name = 'Smoke Phase Five Delivery Traders', BillingStreet = '9 Mount Road', BillingCity = 'Chennai', BillingPostalCode = '600002', Is_Active_Customer__c = true, Business_Unit__c = businessUnit.Id);
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
    Vehicle__c truck = new Vehicle__c(Name = 'Smoke P5A Truck', Vehicle_Number__c = 'SMOKE-P5A-1', Vehicle_Type__c = 'LCV', Capacity__c = 1000, Business_Unit__c = businessUnit.Id, Registration_Expiry__c = valid, Insurance_Expiry__c = valid, Status__c = 'Available');
    insert truck;
    Driver__c driver = new Driver__c(Name = 'Smoke P5A Driver', License_Number__c = 'SMOKE-P5A-DL1', License_Expiry__c = valid, Business_Unit__c = businessUnit.Id, Status__c = 'Available');
    insert driver;
    ServiceResult allocated = new FleetAllocationService().allocate(new List<AllocationRequest>{ new AllocationRequest(shipment.Id, truck.Id, driver.Id) });
    update new Shipment__c(Id = shipment.Id, Status__c = 'Ready for Dispatch');
    update new Shipment__c(Id = shipment.Id, Status__c = 'Dispatched');
    String dispatched = smoke.state(shipment.Id);
    smoke.check('dispatch activates the assignment', allocated.isSuccess && dispatched == 'Dispatched / Active', smoke.firstError(allocated) + ' / ' + dispatched);

    update new Shipment__c(Id = shipment.Id, Status__c = 'In Transit');
    DeliveryService deliveries = new DeliveryService();
    ServiceResult started = deliveries.startAttempts(new List<Id>{ shipment.Id });
    Delivery__c attempt = [SELECT Attempt_Number__c, Attempt_Key__c, Shipment__r.Status__c FROM Delivery__c WHERE Shipment__c = :shipment.Id];
    smoke.check(
        'attempt 1 started with its unique key; shipment Out for Delivery',
        started.isSuccess && attempt.Attempt_Number__c == 1 && attempt.Attempt_Key__c == shipment.Id + ':1' && attempt.Shipment__r.Status__c == 'Out for Delivery',
        smoke.firstError(started)
    );

    ServiceResult noProof = deliveries.confirmDeliveries(new List<Id>{ shipment.Id });
    String afterNoProof = smoke.state(shipment.Id);
    smoke.check('confirmation without a proof is refused, nothing saved', !noProof.isSuccess && afterNoProof.startsWith('Out for Delivery'), smoke.firstError(noProof) + ' / ' + afterNoProof);

    Id proofId = deliveries.recordProofs(new List<ProofOfDeliveryRequest>{ new ProofOfDeliveryRequest(shipment.Id, 'Smoke receiver') }).recordIds[0];
    ServiceResult noFile = deliveries.confirmDeliveries(new List<Id>{ shipment.Id });
    smoke.check('confirmation without an evidence file is refused (D5)', !noFile.isSuccess && smoke.firstError(noFile) == Label.eLogix_Delivery_Evidence_Required, smoke.firstError(noFile));

    ContentVersion photo = new ContentVersion(Title = 'Smoke POD', PathOnClient = 'smoke-pod.jpg', VersionData = Blob.valueOf('smoke'), FirstPublishLocationId = proofId);
    insert photo;
    ServiceResult confirmed = deliveries.confirmDeliveries(new List<Id>{ shipment.Id });
    String delivered = smoke.state(shipment.Id);
    smoke.check('delivery confirmed: shipment Delivered and trip Completed', confirmed.isSuccess && delivered == 'Delivered / Completed', smoke.firstError(confirmed) + ' / ' + delivered);

    ServiceResult again = deliveries.confirmDeliveries(new List<Id>{ shipment.Id });
    Integer deliveredEvents = [SELECT COUNT() FROM Tracking_Event__c WHERE Shipment__c = :shipment.Id AND To_Status__c = 'Delivered'];
    smoke.check('a repeated confirmation is refused and records no event', !again.isSuccess && again.errors[0].code == DeliveryService.ALREADY_DELIVERED && deliveredEvents == 1, smoke.firstError(again) + ' / events=' + deliveredEvents);

    Database.SaveResult reverse = Database.update(new Shipment__c(Id = shipment.Id, Status__c = 'Dispatched'), false);
    smoke.check('a delivery cannot be reversed, even under override (Phase 2 hard rule)', !reverse.isSuccess() && smoke.firstError(reverse).contains('delivered shipment'), smoke.firstError(reverse));

    Id documentId = [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :photo.Id].ContentDocumentId;
    Database.DeleteResult fileDelete = Database.delete(documentId, false);
    smoke.check('evidence file cannot be deleted, even by an administrator (D5)', !fileDelete.isSuccess() && fileDelete.getErrors()[0].getMessage() == Label.eLogix_Delivery_Evidence_Protected, fileDelete.isSuccess() ? '(deleted)' : fileDelete.getErrors()[0].getMessage());

    Database.DeleteResult shipmentDelete = Database.delete(shipment.Id, false);
    smoke.check('a shipment with proof of delivery cannot be deleted', !shipmentDelete.isSuccess() && shipmentDelete.getErrors()[0].getMessage().contains('proof of delivery'), shipmentDelete.isSuccess() ? '(deleted)' : shipmentDelete.getErrors()[0].getMessage());
} finally {
    Database.rollback(savepoint);
}
smoke.check(
    'no rows left behind',
    [SELECT COUNT() FROM Delivery__c] + [SELECT COUNT() FROM Proof_of_Delivery__c] + [SELECT COUNT() FROM Vehicle_Assignment__c] +
    [SELECT COUNT() FROM Business_Unit__c WHERE Business_Unit_Code__c = 'SMOKE-P5A'] + [SELECT COUNT() FROM ContentVersion WHERE Title = 'Smoke POD'] == 0,
    'rows remain'
);
System.debug(LoggingLevel.ERROR, 'SMOKE SUMMARY checks=' + smoke.checks + ' failures=' + smoke.failures);
