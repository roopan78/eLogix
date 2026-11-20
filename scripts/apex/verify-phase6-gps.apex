// eLogix ERP - Phase 6 post-deploy verification: GPS ingestion (G1-G5).
//
// Runs against the live org as the executing user (an administrator holding eLogix_Administrator,
// which includes eLogix_Ingest_GPS), then rolls everything back, including the enqueued job.
// Processing is called synchronously through GpsIngestionService; the asynchronous path (REST endpoint
// and retries) is covered by GpsIngestionTest and the manual REST check in docs/DEPLOYMENT_GUIDE.md.
//
//   sf apex run --file scripts/apex/verify-phase6-gps.apex --target-org eLogixDev
//
// Expect "SMOKE SUMMARY checks=8 failures=0" in the output.

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

    Integer count(GpsIngestionService.Outcome outcome, String code) {
        return outcome.counts.containsKey(code) ? outcome.counts.get(code) : 0;
    }
}

Smoke smoke = new Smoke();
String run = String.valueOf(System.now().getTime());
Savepoint savepoint = Database.setSavepoint();
try {
    Business_Unit__c businessUnit = new Business_Unit__c(Name = 'Smoke Business Unit P6', Business_Unit_Code__c = 'SMOKE-P6', Region__c = 'South', Is_Active__c = true);
    insert businessUnit;
    Account customer = new Account(Name = 'Smoke Phase Six GPS Traders', BillingStreet = '9 Mount Road', BillingCity = 'Chennai', BillingPostalCode = '600002', Is_Active_Customer__c = true, Business_Unit__c = businessUnit.Id);
    insert customer;
    Shipment__c shipment = new Shipment__c(
        Customer__c = customer.Id, Business_Unit__c = businessUnit.Id, Origin__c = 'Chennai', Destination__c = 'Bangalore',
        Weight__c = 500, Distance__c = 350, Priority__c = 'Standard', Status__c = 'Quoted',
        Pickup_Date__c = Date.today(), Expected_Delivery_Date__c = Date.today().addDays(2)
    );
    insert shipment;
    insert new Shipment_Item__c(Shipment__c = shipment.Id, Item_Name__c = 'Pump', SKU__c = 'SMOKE-P6', Quantity__c = 1, Weight__c = 50, Package_Type__c = 'Crate');
    update new Shipment__c(Id = shipment.Id, Status__c = 'Confirmed');

    Date valid = Date.today().addDays(365);
    List<Vehicle__c> trucks = new List<Vehicle__c>{
        new Vehicle__c(Name = 'Smoke P6 Truck', Vehicle_Number__c = 'SMOKE-P6-1', Vehicle_Type__c = 'LCV', Capacity__c = 1000, Business_Unit__c = businessUnit.Id, Registration_Expiry__c = valid, Insurance_Expiry__c = valid, Status__c = 'Available'),
        new Vehicle__c(Name = 'Smoke P6 Idle Truck', Vehicle_Number__c = 'SMOKE-P6-IDLE', Vehicle_Type__c = 'LCV', Capacity__c = 1000, Business_Unit__c = businessUnit.Id, Registration_Expiry__c = valid, Insurance_Expiry__c = valid, Status__c = 'Available')
    };
    insert trucks;
    Driver__c driver = new Driver__c(Name = 'Smoke P6 Driver', License_Number__c = 'SMOKE-P6-DL1', License_Expiry__c = valid, Business_Unit__c = businessUnit.Id, Status__c = 'Available');
    insert driver;
    new FleetAllocationService().allocate(new List<AllocationRequest>{ new AllocationRequest(shipment.Id, trucks[0].Id, driver.Id) });
    for (String status : new List<String>{ 'Ready for Dispatch', 'Dispatched' }) {
        update new Shipment__c(Id = shipment.Id, Status__c = status);
    }

    // Pings 2 and 3 minutes ahead (within GPS_Max_Future_Skew_Minutes) are newer than the status events.
    Datetime at = Datetime.newInstance((System.now().getTime() / 1000) * 1000).addMinutes(2);
    String firstId = 'SMOKE-P6-' + run;
    GpsIngestionService service = new GpsIngestionService();
    GpsIngestionService.Outcome outcome = service.ingest(
        new List<GpsPing>{
            new GpsPing(firstId, 'smoke-p6-1', 13.0827, 80.2707, at),
            new GpsPing(firstId + '-T', 'SMOKE-P6-1', 13.0828, 80.2707, at.addMinutes(1)), // ~0.01 km, 1 minute later
            new GpsPing(firstId + '-U', 'SMOKE-P6-NONE', 13.0827, 80.2707, at),
            new GpsPing(firstId + '-I', 'SMOKE-P6-IDLE', 13.0827, 80.2707, at)
        }
    );
    List<Tracking_Event__c> events = [SELECT Event_Type__c, Source__c, Event_Key__c FROM Tracking_Event__c WHERE Shipment__c = :shipment.Id AND Source__c = 'GPS Integration'];
    Shipment__c after = [SELECT Status__c, Latest_Tracking_Timestamp__c FROM Shipment__c WHERE Id = :shipment.Id];

    smoke.check(
        'a valid ping is stored once as a Location Update with the provider message key (G1, G2)',
        smoke.count(outcome, GpsIngestionService.STORED) == 1 && events.size() == 1 && events[0].Event_Type__c == 'Location Update' &&
            events[0].Event_Key__c == 'EXT:GPSIntegration:' + firstId,
        String.valueOf(outcome.counts) + ' / ' + events
    );
    smoke.check('GPS never changes the shipment status', after.Status__c == 'Dispatched', after.Status__c);
    smoke.check(
        'a throttled ping creates no event and leaves the summary at the stored ping (G3)',
        smoke.count(outcome, GpsIngestionService.THROTTLED) == 1 && after.Latest_Tracking_Timestamp__c == at,
        String.valueOf(outcome.counts) + ' / ' + after.Latest_Tracking_Timestamp__c
    );
    smoke.check(
        'unknown vehicles and vehicles without an Active trip are rejected and counted (G4)',
        smoke.count(outcome, GpsIngestionService.UNKNOWN_VEHICLE) == 1 && smoke.count(outcome, GpsIngestionService.NO_ACTIVE_TRIP) == 1,
        String.valueOf(outcome.counts)
    );

    // A replay of the stored ping in a later batch never creates a second event.
    service.ingest(new List<GpsPing>{ new GpsPing(firstId, 'SMOKE-P6-1', 13.0827, 80.2707, at) });
    Integer replayed = [SELECT COUNT() FROM Tracking_Event__c WHERE Shipment__c = :shipment.Id AND Source__c = 'GPS Integration'];
    smoke.check('a replayed ping is idempotent', replayed == 1, String.valueOf(replayed));

    // G5: one log row per batch, Dead Letter rows only for exhausted pings.
    String batchId = 'SMOKE-P6-' + run;
    service.logBatch(batchId, 0, outcome, true, new List<GpsPing>());
    GpsIngestionService.Outcome retry = new GpsIngestionService.Outcome();
    retry.count(GpsIngestionService.RECORD_LOCKED);
    GpsPing exhausted = new GpsPing(firstId + '-DL', 'SMOKE-P6-1', 13.0827, 80.2707, at);
    service.logBatch(batchId, 3, retry, false, new List<GpsPing>{ exhausted });
    Map<String, String> logs = new Map<String, String>();
    for (Integration_Log__c log : [SELECT Status__c, Idempotency_Key__c FROM Integration_Log__c WHERE Correlation_Id__c = :batchId]) {
        logs.put(log.Idempotency_Key__c, log.Status__c);
    }
    smoke.check(
        'one batch log (Failed after exhaustion) plus one Dead Letter row (G5)',
        logs.size() == 2 && logs.get('GPS-BATCH:' + batchId) == 'Failed' && logs.get('GPS-DL:' + firstId + '-DL') == 'Dead Letter',
        String.valueOf(logs)
    );

    // The submit path checks eLogix_Ingest_GPS and returns a batch id (the enqueued job is rolled back).
    String submitted = GpsIngestionJob.submit(new MockGpsProvider().currentPositions());
    smoke.check('the mock provider feeds the asynchronous path (G1)', submitted != null && submitted.length() == 36, submitted);
} finally {
    Database.rollback(savepoint);
}
smoke.check(
    'no rows left behind',
    [SELECT COUNT() FROM Business_Unit__c WHERE Business_Unit_Code__c = 'SMOKE-P6'] + [SELECT COUNT() FROM Integration_Log__c WHERE Correlation_Id__c = :('SMOKE-P6-' + run)] == 0,
    'rows remain'
);
System.debug(LoggingLevel.ERROR, 'SMOKE SUMMARY checks=' + smoke.checks + ' failures=' + smoke.failures);
