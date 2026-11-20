/**
 * Phase 6 GPS tracking: GpsIngestionService (validation, vehicle mapping, throttling, idempotency),
 * GpsIngestionJob (retry of the locked subset, backoff, dead letters, one batch log), GpsPingResource
 * and MockGpsProvider. Two shipments are In Transit on Active trips (vehicles TN-GPS-1, TN-GPS-2);
 * TN-GPS-IDLE has no trip. Pings are submitted as the GPS integration user.
 */
@IsTest
private class GpsIngestionTest {
    private static final String OPS = 'Gps Ops Tester';
    private static final String FLEET = 'Gps Fleet Tester';
    private static final String GPS = 'Gps Integration Tester';
    private static final String VEHICLE_1 = 'TN-GPS-1';
    private static final String VEHICLE_2 = 'TN-GPS-2';
    private static final String IDLE = 'TN-GPS-IDLE';
    private static final Decimal CHENNAI_LAT = 13.0827;
    private static final Decimal CHENNAI_LON = 80.2707;

    @TestSetup
    static void setup() {
        Business_Unit__c businessUnit = TestDataFactory.createBusinessUnit('BU-GPS');
        Account customer = TestDataFactory.createCustomer('CUST-GPS', businessUnit.Id);
        TestDataFactory.createUser(OPS, TestDataFactory.OPERATIONS);
        TestDataFactory.createUser(FLEET, TestDataFactory.FLEET);
        TestDataFactory.createUser(GPS, 'eLogix_GPS_Integration');

        List<Shipment__c> shipments;
        System.runAs(TestDataFactory.getUser(OPS)) {
            shipments = TestDataFactory.confirmedShipments(2, customer.Id, businessUnit.Id);
            List<Shipment__c> today = new List<Shipment__c>();
            for (Shipment__c shipment : shipments) {
                today.add(new Shipment__c(Id = shipment.Id, Pickup_Date__c = Date.today()));
            }
            update today;
        }
        System.runAs(TestDataFactory.getUser(FLEET)) {
            List<Vehicle__c> vehicles = new List<Vehicle__c>{
                TestDataFactory.buildVehicle(VEHICLE_1, businessUnit.Id),
                TestDataFactory.buildVehicle(VEHICLE_2, businessUnit.Id),
                TestDataFactory.buildVehicle(IDLE, businessUnit.Id)
            };
            List<Driver__c> drivers = new List<Driver__c>{
                TestDataFactory.buildDriver('DL-GPS-1', businessUnit.Id),
                TestDataFactory.buildDriver('DL-GPS-2', businessUnit.Id)
            };
            insert vehicles;
            insert drivers;
            ServiceResult allocated = new FleetAllocationService()
                .allocate(
                    new List<AllocationRequest>{
                        new AllocationRequest(shipments[0].Id, vehicles[0].Id, drivers[0].Id),
                        new AllocationRequest(shipments[1].Id, vehicles[1].Id, drivers[1].Id)
                    }
                );
            Assert.isTrue(allocated.isSuccess, String.valueOf(allocated.errors));
        }
        System.runAs(TestDataFactory.getUser(OPS)) {
            TestDataFactory.advance(
                new List<Shipment__c>{ new Shipment__c(Id = shipments[0].Id), new Shipment__c(Id = shipments[1].Id) },
                new List<String>{ 'Ready for Dispatch', 'Dispatched', 'In Transit' }
            );
        }
        // Each status change stamps Latest_Tracking_Timestamp__c with the current time (ShipmentDomain).
        // Model shipments last tracked 23 hours ago, so the GPS pings in these tests (all within the
        // last 22 hours) are newer than the summary; only newer events move it. System context: the
        // field is protected and no user may edit it.
        update new List<Shipment__c>{
            new Shipment__c(Id = shipments[0].Id, Latest_Tracking_Timestamp__c = System.now().addHours(-23)),
            new Shipment__c(Id = shipments[1].Id, Latest_Tracking_Timestamp__c = System.now().addHours(-23))
        };
    }

    /* ---------------- helpers ---------------- */

    /** Records the retries the job would enqueue: queueables cannot chain inside a test. */
    private class RecordingEnqueuer extends GpsIngestionJob.Enqueuer {
        List<GpsIngestionJob> jobs = new List<GpsIngestionJob>();
        List<Integer> delays = new List<Integer>();

        public override void enqueue(GpsIngestionJob job, Integer delayMinutes) {
            jobs.add(job);
            delays.add(delayMinutes);
        }
    }

    /** Every shipment lock query times out. */
    private class LockedSelector extends ShipmentSelector {
        public override Map<Id, Shipment__c> selectTrackingSummaryForUpdate(Set<Id> shipmentIds) {
            throw new QueryException('UNABLE_TO_LOCK_ROW, unable to obtain exclusive access to this record');
        }
    }

    /** Now, to the second: Datetime fields keep seconds only. */
    private static Datetime base() {
        return Datetime.newInstance((System.now().getTime() / 1000) * 1000);
    }

    private static GpsPing ping(String messageId, String vehicle, Decimal latitude, Decimal longitude, Datetime recordedAt) {
        return new GpsPing(messageId, vehicle, latitude, longitude, recordedAt);
    }

    private static Id shipmentOf(String vehicle) {
        return [SELECT Shipment__c FROM Vehicle_Assignment__c WHERE Vehicle__r.Vehicle_Number__c = :vehicle AND Status__c = 'Active'].Shipment__c;
    }

    private static List<Tracking_Event__c> gpsEvents(Id shipmentId) {
        return [
            SELECT Event_Type__c, Source__c, Latitude__c, Longitude__c, Location__c, Event_Timestamp__c, Event_Key__c
            FROM Tracking_Event__c
            WHERE Shipment__c = :shipmentId AND Source__c = 'GPS Integration'
            ORDER BY Event_Timestamp__c
        ];
    }

    private static Map<String, Object> counts(String batchId) {
        Integration_Log__c log = batchLog(batchId);
        return (Map<String, Object>) JSON.deserializeUntyped(log.Response_Payload__c);
    }

    private static Integration_Log__c batchLog(String batchId) {
        return [
            SELECT Status__c, Retry_Count__c, Response_Payload__c, Error_Category__c, Integration_Name__c, Direction__c
            FROM Integration_Log__c
            WHERE Idempotency_Key__c = :('GPS-BATCH:' + batchId)
        ];
    }

    private static Integer count(GpsIngestionService.Outcome outcome, String code) {
        return outcome.counts.containsKey(code) ? outcome.counts.get(code) : 0;
    }

    /* ---------------- ingestion ---------------- */

    @IsTest
    static void validPingsBecomeLocationUpdatesAndNeverChangeStatus() {
        Id shipment1 = shipmentOf(VEHICLE_1);
        Id shipment2 = shipmentOf(VEHICLE_2);
        Datetime at = base().addMinutes(-10);
        GpsIngestionService.Outcome outcome;
        System.runAs(TestDataFactory.getUser(GPS)) {
            GpsPing named = ping('M-1', VEHICLE_1.toLowerCase(), CHENNAI_LAT, CHENNAI_LON, at);
            named.location = 'Sriperumbudur';
            outcome = new GpsIngestionService().ingest(new List<GpsPing>{ named, ping('M-2', VEHICLE_2, 12.9165, 79.1325, at) });
        }

        Assert.areEqual(2, count(outcome, GpsIngestionService.STORED), String.valueOf(outcome.counts));
        Assert.isTrue(outcome.retryable.isEmpty());
        List<Tracking_Event__c> events = gpsEvents(shipment1);
        Assert.areEqual(1, events.size());
        Assert.areEqual('Location Update', events[0].Event_Type__c);
        Assert.areEqual('Sriperumbudur', events[0].Location__c);
        Assert.isTrue(events[0].Latitude__c == CHENNAI_LAT && events[0].Longitude__c == CHENNAI_LON, String.valueOf(events[0]));
        Assert.areEqual('EXT:GPSIntegration:M-1', events[0].Event_Key__c);
        Assert.areEqual('12.91650, 79.13250', gpsEvents(shipment2)[0].Location__c, 'Without a place name the coordinates are shown.');

        for (Shipment__c shipment : [SELECT Status__c, Latest_Location__c, Latest_Tracking_Timestamp__c FROM Shipment__c WHERE Id IN :new Set<Id>{ shipment1, shipment2 }]) {
            Assert.areEqual('In Transit', shipment.Status__c, 'GPS never changes the shipment status.');
            Assert.areEqual(at, shipment.Latest_Tracking_Timestamp__c);
        }
    }

    @IsTest
    static void invalidStaleUnknownIdleAndDuplicatePingsAreRejectedAndCounted() {
        Datetime at = base().addMinutes(-10);
        GpsIngestionService.Outcome outcome;
        System.runAs(TestDataFactory.getUser(GPS)) {
            outcome = new GpsIngestionService()
                .ingest(
                    new List<GpsPing>{
                        ping('R-1', VEHICLE_1, 95, CHENNAI_LON, at), // latitude out of range
                        ping('R-2', VEHICLE_1, 0, 0, at), // null island
                        ping('R-3', VEHICLE_1, CHENNAI_LAT, CHENNAI_LON, base().addMinutes(60)), // beyond future skew
                        ping('', VEHICLE_1, CHENNAI_LAT, CHENNAI_LON, at), // no message id
                        ping('R-5', VEHICLE_1, CHENNAI_LAT, CHENNAI_LON, base().addHours(-48)), // stale
                        ping('R-6', 'XX-NOT-A-TRUCK', CHENNAI_LAT, CHENNAI_LON, at),
                        ping('R-7', IDLE, CHENNAI_LAT, CHENNAI_LON, at), // vehicle without an Active trip (G4)
                        ping('R-8', VEHICLE_1, CHENNAI_LAT, CHENNAI_LON, at),
                        ping('R-8', VEHICLE_1, CHENNAI_LAT, CHENNAI_LON, at) // same message twice
                    }
                );
        }

        Assert.areEqual(9, count(outcome, GpsIngestionService.RECEIVED));
        Assert.areEqual(4, count(outcome, GpsIngestionService.INVALID), String.valueOf(outcome.counts));
        Assert.areEqual(1, count(outcome, GpsIngestionService.STALE));
        Assert.areEqual(1, count(outcome, GpsIngestionService.UNKNOWN_VEHICLE));
        Assert.areEqual(1, count(outcome, GpsIngestionService.NO_ACTIVE_TRIP));
        Assert.areEqual(1, count(outcome, GpsIngestionService.DUPLICATE));
        Assert.areEqual(1, count(outcome, GpsIngestionService.STORED));
        Assert.areEqual(1, [SELECT COUNT() FROM Tracking_Event__c WHERE Source__c = 'GPS Integration']);
    }

    /**
     * G3: stored when GPS_Min_Interval_Minutes (15) passed or the vehicle moved GPS_Min_Distance_Km (2)
     * since the last stored location; otherwise no event and no summary change.
     */
    @IsTest
    static void throttledPingsCreateNoEventAndLeaveTheSummaryAlone() {
        Id shipmentId = shipmentOf(VEHICLE_1);
        Datetime t = base().addMinutes(-60);
        GpsIngestionService.Outcome outcome;
        GpsIngestionService.Outcome later;
        System.runAs(TestDataFactory.getUser(GPS)) {
            outcome = new GpsIngestionService()
                .ingest(
                    new List<GpsPing>{
                        ping('T-E', VEHICLE_1, CHENNAI_LAT + 0.05, CHENNAI_LON, t.addMinutes(35)), // 5 min after T-D, same place: throttled
                        ping('T-A', VEHICLE_1, CHENNAI_LAT, CHENNAI_LON, t), // first: stored
                        ping('T-B', VEHICLE_1, CHENNAI_LAT + 0.001, CHENNAI_LON, t.addMinutes(5)), // ~0.1 km, 5 min: throttled
                        ping('T-C', VEHICLE_1, CHENNAI_LAT + 0.05, CHENNAI_LON, t.addMinutes(10)), // ~5.6 km: stored (distance)
                        ping('T-D', VEHICLE_1, CHENNAI_LAT + 0.05, CHENNAI_LON, t.addMinutes(30)) // 20 min: stored (interval)
                    }
                );
            // Across batches the last stored location (T-D) is read back from the database.
            later = new GpsIngestionService()
                .ingest(new List<GpsPing>{ ping('T-F', VEHICLE_1, CHENNAI_LAT + 0.0501, CHENNAI_LON, t.addMinutes(40)) });
        }

        Assert.areEqual(3, count(outcome, GpsIngestionService.STORED), String.valueOf(outcome.counts));
        Assert.areEqual(2, count(outcome, GpsIngestionService.THROTTLED));
        Assert.areEqual(1, count(later, GpsIngestionService.THROTTLED), String.valueOf(later.counts));
        List<Tracking_Event__c> events = gpsEvents(shipmentId);
        Assert.areEqual(3, events.size());
        Assert.areEqual('EXT:GPSIntegration:T-D', events[2].Event_Key__c);
        Shipment__c shipment = [SELECT Latest_Tracking_Timestamp__c FROM Shipment__c WHERE Id = :shipmentId];
        Assert.areEqual(t.addMinutes(30), shipment.Latest_Tracking_Timestamp__c, 'Throttled T-E and T-F are newer but must not move the summary.');
    }

    @IsTest
    static void distanceIsGreatCircle() {
        Decimal km = GpsIngestionService.distanceKm(13.0827, 80.2707, 12.9716, 77.5946); // Chennai - Bangalore
        Assert.isTrue(km > 285 && km < 295, String.valueOf(km));
        Assert.areEqual(0, GpsIngestionService.distanceKm(13.0827, 80.2707, 13.0827, 80.2707));
    }

    /* ---------------- job: retry, idempotency, logging ---------------- */

    /** Only the locked pings are retried, after 1, 2 and 4 minutes; then they become dead letters (G5). */
    @IsTest
    static void lockedSubsetIsRetriedWithBackoffThenDeadLettered() {
        RecordingEnqueuer recorder = new RecordingEnqueuer();
        GpsIngestionJob.enqueuer = recorder;
        TrackingService.shipmentSelector = new LockedSelector();
        Datetime at = base().addMinutes(-10);
        List<GpsPing> pings = new List<GpsPing>{
            ping('D-1', VEHICLE_1, CHENNAI_LAT, CHENNAI_LON, at),
            ping('D-2', IDLE, CHENNAI_LAT, CHENNAI_LON, at),
            ping('D-3', VEHICLE_1, 95, CHENNAI_LON, at)
        };

        System.runAs(TestDataFactory.getUser(GPS)) {
            new GpsIngestionJob('B-DL', pings, 0).execute(null);
            Assert.areEqual(1, recorder.jobs.size());
            Assert.areEqual(1, recorder.jobs[0].pings.size(), 'Only the locked ping is retried.');
            Assert.areEqual('D-1', recorder.jobs[0].pings[0].messageId);
            Assert.areEqual(1, recorder.jobs[0].attempt);
            Integration_Log__c first = batchLog('B-DL');
            Assert.areEqual('Retrying', first.Status__c);
            Assert.areEqual('Inbound', first.Direction__c);

            for (Integer i = 0; i < 3; i++) {
                recorder.jobs[i].execute(null);
            }
        }

        Assert.areEqual(new List<Integer>{ 1, 2, 4 }, recorder.delays, 'Backoff 1, 2, 4 minutes; no fourth retry.');
        Assert.areEqual(3, recorder.jobs.size());
        Integration_Log__c log = batchLog('B-DL');
        Assert.areEqual('Failed', log.Status__c);
        Assert.areEqual(3, log.Retry_Count__c);
        Map<String, Object> stats = counts('B-DL');
        Assert.areEqual(3, stats.get(GpsIngestionService.RECEIVED));
        Assert.areEqual(1, stats.get(GpsIngestionService.NO_ACTIVE_TRIP));
        Assert.areEqual(1, stats.get(GpsIngestionService.INVALID));
        Assert.areEqual(1, stats.get(GpsIngestionService.DEAD_LETTER));
        Assert.isFalse(stats.containsKey(GpsIngestionService.RECORD_LOCKED));

        Assert.areEqual(1, [SELECT COUNT() FROM Integration_Log__c WHERE Correlation_Id__c = 'B-DL' AND Status__c != 'Dead Letter'], 'One log per batch.');
        Integration_Log__c deadLetter = [SELECT Status__c, Request_Payload__c FROM Integration_Log__c WHERE Idempotency_Key__c = 'GPS-DL:D-1'];
        Assert.isTrue(deadLetter.Request_Payload__c.contains('D-1'));
        Assert.areEqual(1, [SELECT COUNT() FROM Integration_Log__c WHERE Status__c = 'Dead Letter'], 'Dead letters only for exhausted pings.');
        Assert.areEqual(0, [SELECT COUNT() FROM Tracking_Event__c WHERE Source__c = 'GPS Integration']);
    }

    /** A retry that succeeds stores the ping once, and a repeated retry never stores it twice. */
    @IsTest
    static void retriesAreIdempotent() {
        RecordingEnqueuer recorder = new RecordingEnqueuer();
        GpsIngestionJob.enqueuer = recorder;
        TrackingService.shipmentSelector = new LockedSelector();
        Id shipmentId = shipmentOf(VEHICLE_1);
        Datetime at = base().addMinutes(-10);
        List<GpsPing> pings = new List<GpsPing>{
            ping('I-1', VEHICLE_1, CHENNAI_LAT, CHENNAI_LON, at),
            ping('I-2', VEHICLE_2, CHENNAI_LAT, CHENNAI_LON, at)
        };

        System.runAs(TestDataFactory.getUser(GPS)) {
            new GpsIngestionJob('B-OK', pings, 0).execute(null);
            TrackingService.shipmentSelector = new ShipmentSelector(); // the lock is released
            recorder.jobs[0].execute(null);
            recorder.jobs[0].execute(null); // the same retry delivered twice
            // A provider resubmission with a newer timestamp under the same message id.
            GpsPing replay = ping('I-1', VEHICLE_1, CHENNAI_LAT + 1, CHENNAI_LON, at.addMinutes(5));
            new GpsIngestionJob('B-REPLAY', new List<GpsPing>{ replay }, 0).execute(null);
        }

        Assert.areEqual(1, recorder.jobs.size(), 'No further retry after success.');
        Assert.areEqual(1, gpsEvents(shipmentId).size(), 'Never a duplicate tracking event.');
        Assert.areEqual(at, [SELECT Latest_Tracking_Timestamp__c FROM Shipment__c WHERE Id = :shipmentId].Latest_Tracking_Timestamp__c);
        Integration_Log__c log = batchLog('B-OK');
        Assert.areEqual('Success', log.Status__c);
        Map<String, Object> stats = counts('B-OK');
        Assert.areEqual(2, stats.get(GpsIngestionService.RECEIVED));
        Assert.isFalse(stats.containsKey(GpsIngestionService.RECORD_LOCKED));
        Assert.areEqual(0, [SELECT COUNT() FROM Integration_Log__c WHERE Status__c = 'Dead Letter']);
    }

    @IsTest
    static void backoffDoublesAndIsCapped() {
        Assert.areEqual(1, GpsIngestionJob.backoffMinutes(0));
        Assert.areEqual(2, GpsIngestionJob.backoffMinutes(1));
        Assert.areEqual(4, GpsIngestionJob.backoffMinutes(2));
        Assert.areEqual(10, GpsIngestionJob.backoffMinutes(6));
    }

    /* ---------------- REST endpoint ---------------- */

    private static RestResponse post(String body) {
        RestContext.request = new RestRequest();
        RestContext.request.requestURI = '/services/apexrest/elogix/gps/v1/pings';
        RestContext.request.httpMethod = 'POST';
        RestContext.request.requestBody = body == null ? null : Blob.valueOf(body);
        RestContext.response = new RestResponse();
        GpsPingResource.submit();
        return RestContext.response;
    }

    @IsTest
    static void endpointAcceptsABatchAndProcessesItAsynchronously() {
        Id shipmentId = shipmentOf(VEHICLE_1);
        String recordedAt = JSON.serialize(base().addMinutes(-5)).remove('"');
        String body =
            '{"pings":[{"messageId":"REST-1","vehicleNumber":"' + VEHICLE_1 + '","latitude":13.0827,"longitude":80.2707,"recordedAt":"' + recordedAt + '"},' +
            '{"messageId":"REST-2","vehicleNumber":"' + IDLE + '","latitude":13.0827,"longitude":80.2707,"recordedAt":"' + recordedAt + '"}]}';
        RestResponse response;
        System.runAs(TestDataFactory.getUser(GPS)) {
            Test.startTest();
            response = post(body);
            Test.stopTest();
        }

        Assert.areEqual(202, response.statusCode, response.responseBody?.toString());
        Map<String, Object> reply = (Map<String, Object>) JSON.deserializeUntyped(response.responseBody.toString());
        Assert.areEqual(2, reply.get('accepted'));
        String batchId = (String) reply.get('batchId');
        Assert.areEqual(1, gpsEvents(shipmentId).size());
        Assert.areEqual('Success', batchLog(batchId).Status__c);
        Assert.areEqual(1, counts(batchId).get(GpsIngestionService.NO_ACTIVE_TRIP));
    }

    @IsTest
    static void endpointRejectsCallersWithoutTheCustomPermission() {
        RestResponse response;
        System.runAs(TestDataFactory.getUser(OPS)) {
            Test.startTest();
            response = post('{"pings":[]}');
            Test.stopTest();
            try {
                GpsIngestionJob.submit(new List<GpsPing>{ ping('X-1', VEHICLE_1, CHENNAI_LAT, CHENNAI_LON, base()) });
                Assert.fail('Expected an AuthorizationException.');
            } catch (AuthorizationException e) {
                Assert.areEqual(AuthorizationException.ACCESS_DENIED, e.code);
            }
        }
        Assert.areEqual(403, response.statusCode);
        Assert.areEqual(0, [SELECT COUNT() FROM AsyncApexJob WHERE JobType = 'Queueable']);
    }

    @IsTest
    static void endpointRejectsMalformedBodies() {
        System.runAs(TestDataFactory.getUser(GPS)) {
            Assert.areEqual(400, post('not json').statusCode);
            Assert.areEqual(400, post('{"pings":[]}').statusCode);
            Assert.areEqual(400, post(null).statusCode);
            List<GpsPing> tooMany = new List<GpsPing>();
            for (Integer i = 0; i <= GpsIngestionJob.MAX_PINGS; i++) {
                tooMany.add(ping('O-' + i, VEHICLE_1, CHENNAI_LAT, CHENNAI_LON, base()));
            }
            Assert.areEqual(400, post(JSON.serialize(new Map<String, Object>{ 'pings' => tooMany })).statusCode);
        }
        Assert.areEqual(0, [SELECT COUNT() FROM Integration_Log__c]);
    }

    /* ---------------- mock provider and bulk ---------------- */

    @IsTest
    static void mockProviderReportsActiveTripsBetweenTheirCities() {
        List<GpsPing> pings;
        System.runAs(TestDataFactory.getUser(GPS)) {
            pings = new MockGpsProvider().currentPositions();
        }
        Assert.areEqual(2, pings.size(), 'One ping per Active trip; the idle vehicle has none.');
        for (GpsPing ping : pings) {
            Assert.isTrue(ping.messageId.startsWith('MOCK-' + ping.vehicleNumber + '-'));
            // Chennai (13.08, 80.27) to Bangalore (12.97, 77.59)
            Assert.isTrue(ping.latitude >= 12.9716 && ping.latitude <= 13.0827, String.valueOf(ping.latitude));
            Assert.isTrue(ping.longitude >= 77.5946 && ping.longitude <= 80.2707, String.valueOf(ping.longitude));
        }
    }

    /** 150 pings over 2 shipments cost a fixed number of queries, not one per ping. */
    @IsTest
    static void bulkBatchUsesAFixedNumberOfQueries() {
        List<GpsPing> pings = new List<GpsPing>();
        Datetime start = base().addHours(-21);
        for (Integer i = 0; i < 75; i++) {
            pings.add(ping('BULK-1-' + i, VEHICLE_1, CHENNAI_LAT, CHENNAI_LON, start.addMinutes(16 * i)));
            pings.add(ping('BULK-2-' + i, VEHICLE_2, CHENNAI_LAT, CHENNAI_LON, start.addMinutes(16 * i)));
        }
        GpsIngestionService.Outcome outcome;
        Integer queries;
        System.runAs(TestDataFactory.getUser(GPS)) {
            Test.startTest();
            Integer before = Limits.getQueries();
            outcome = new GpsIngestionService().ingest(pings);
            queries = Limits.getQueries() - before;
            Test.stopTest();
        }
        Assert.areEqual(150, count(outcome, GpsIngestionService.STORED), String.valueOf(outcome.counts));
        Assert.isTrue(queries <= 12, 'Queries: ' + queries);
        Assert.areEqual(150, [SELECT COUNT() FROM Tracking_Event__c WHERE Source__c = 'GPS Integration']);
    }
}
