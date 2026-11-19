/**
 * Tests for TrackingService.recordEvents: operational events from users and integrations.
 * Status-event behaviour is covered end to end in ShipmentTriggerHandlerTest.
 */
@IsTest
private class TrackingServiceTest {
    private static final String OPS = 'Tracking Ops Tester';
    private static final String OTHER_OPS = 'Other Ops Tester';
    private static final String SALES = 'Tracking Sales Tester';
    private static final String MANAGER = 'Tracking Manager Tester';

    @TestSetup
    static void setup() {
        Business_Unit__c businessUnit = TestDataFactory.createBusinessUnit('BU-TRK');
        TestDataFactory.createCustomer('CUST-TRK', businessUnit.Id);
        TestDataFactory.createUser(OPS, TestDataFactory.OPERATIONS);
        TestDataFactory.createUser(OTHER_OPS, TestDataFactory.OPERATIONS);
        TestDataFactory.createUser(SALES, TestDataFactory.SALES);
        TestDataFactory.createUser(MANAGER, TestDataFactory.LOGISTICS_MANAGER);
    }

    /** Inserts draft shipments owned by the running user. */
    private static List<Shipment__c> shipments(Integer count) {
        Account customer = [SELECT Id, Business_Unit__c FROM Account WHERE Customer_Code__c = 'CUST-TRK'];
        List<Shipment__c> records = TestDataFactory.buildShipments(count, customer.Id, customer.Business_Unit__c, 'Draft');
        insert records;
        return records;
    }

    private static TrackingEventRequest gps(Id shipmentId, String location, Datetime timestamp, String externalId) {
        TrackingEventRequest request = new TrackingEventRequest(shipmentId, 'Location Update', location);
        request.eventTimestamp = timestamp;
        request.source = 'GPS Integration';
        request.externalEventId = externalId;
        request.latitude = 12.5266;
        request.longitude = 78.2150;
        return request;
    }

    private static Shipment__c summary(Id shipmentId) {
        return [SELECT Latest_Location__c, Latest_Tracking_Timestamp__c FROM Shipment__c WHERE Id = :shipmentId];
    }

    @IsTest
    static void recordsLocationEventAndUpdatesTrackingSummary() {
        System.runAs(TestDataFactory.getUser(OPS)) {
            Shipment__c shipment = shipments(1)[0];
            Datetime timestamp = System.now().addMinutes(5);

            ServiceResult result = new TrackingService().recordEvents(new List<TrackingEventRequest>{ gps(shipment.Id, 'Krishnagiri Toll Plaza', timestamp, 'GPS-1001') });

            Assert.isTrue(result.isSuccess, String.valueOf(result.errors));
            Assert.areEqual(1, result.recordIds.size());
            Tracking_Event__c event = [
                SELECT Event_Type__c, Location__c, Source__c, Event_Key__c, Latitude__c, From_Status__c
                FROM Tracking_Event__c
                WHERE Id = :result.recordIds[0]
            ];
            Assert.areEqual('Location Update', event.Event_Type__c);
            Assert.areEqual('GPS Integration', event.Source__c);
            Assert.areEqual('EXT:GPSIntegration:GPS-1001', event.Event_Key__c);
            Assert.areEqual(12.5266, event.Latitude__c);
            Assert.isNull(event.From_Status__c, 'Operational events do not change status.');
            Assert.areEqual('Krishnagiri Toll Plaza', summary(shipment.Id).Latest_Location__c);
            Assert.areEqual(timestamp, summary(shipment.Id).Latest_Tracking_Timestamp__c);
            Assert.areEqual('Draft', [SELECT Status__c FROM Shipment__c WHERE Id = :shipment.Id].Status__c);
        }
    }

    @IsTest
    static void replayedExternalEventIsIdempotent() {
        System.runAs(TestDataFactory.getUser(OPS)) {
            Shipment__c shipment = shipments(1)[0];
            Datetime timestamp = System.now().addMinutes(5);
            TrackingService service = new TrackingService();

            service.recordEvents(new List<TrackingEventRequest>{ gps(shipment.Id, 'Hosur', timestamp, 'GPS-2001') });
            ServiceResult replay = service.recordEvents(
                new List<TrackingEventRequest>{ gps(shipment.Id, 'Hosur', timestamp, 'GPS-2001'), gps(shipment.Id, 'Hosur', timestamp, 'GPS-2001') }
            );

            Assert.isTrue(replay.isSuccess, 'A replay is not an error.');
            Assert.areEqual(0, replay.recordIds.size(), 'Nothing new was written.');
            Assert.areEqual(1, [SELECT COUNT() FROM Tracking_Event__c WHERE Event_Type__c = 'Location Update']);
        }
    }

    @IsTest
    static void duplicateWithinOneBatchIsRecordedOnce() {
        System.runAs(TestDataFactory.getUser(OPS)) {
            Shipment__c shipment = shipments(1)[0];
            Datetime timestamp = System.now().addMinutes(5);

            ServiceResult result = new TrackingService()
                .recordEvents(new List<TrackingEventRequest>{ gps(shipment.Id, 'Hosur', timestamp, 'GPS-3001'), gps(shipment.Id, 'Hosur', timestamp, 'GPS-3001') });

            Assert.isTrue(result.isSuccess);
            Assert.areEqual(1, result.recordIds.size());
        }
    }

    @IsTest
    static void olderEventDoesNotOverwriteTheLatestLocation() {
        System.runAs(TestDataFactory.getUser(OPS)) {
            Shipment__c shipment = shipments(1)[0];
            Datetime newest = System.now().addMinutes(10);
            TrackingService service = new TrackingService();

            service.recordEvents(new List<TrackingEventRequest>{ gps(shipment.Id, 'Hosur', newest, 'GPS-4001') });
            ServiceResult late = service.recordEvents(new List<TrackingEventRequest>{ gps(shipment.Id, 'Vellore', System.now().addHours(-2), 'GPS-4000') });

            Assert.isTrue(late.isSuccess);
            Assert.areEqual(2, [SELECT COUNT() FROM Tracking_Event__c WHERE Event_Type__c = 'Location Update'], 'Late events are still history.');
            Assert.areEqual('Hosur', summary(shipment.Id).Latest_Location__c);
            Assert.areEqual(newest, summary(shipment.Id).Latest_Tracking_Timestamp__c);
        }
    }

    @IsTest
    static void newestEventInABatchWinsAndKeepsLastKnownLocation() {
        System.runAs(TestDataFactory.getUser(OPS)) {
            Shipment__c shipment = shipments(1)[0];
            TrackingEventRequest hubScan = new TrackingEventRequest(shipment.Id, 'Hub Arrival', 'Bangalore Hub');
            hubScan.eventTimestamp = System.now().addMinutes(5);
            TrackingEventRequest ping = new TrackingEventRequest(shipment.Id, 'Location Update', null);
            ping.eventTimestamp = System.now().addMinutes(6);

            ServiceResult result = new TrackingService().recordEvents(new List<TrackingEventRequest>{ hubScan, ping });

            Assert.isTrue(result.isSuccess, String.valueOf(result.errors));
            Assert.areEqual(2, result.recordIds.size());
            Shipment__c saved = summary(shipment.Id);
            Assert.areEqual(ping.eventTimestamp, saved.Latest_Tracking_Timestamp__c);
            Assert.areEqual('Bangalore Hub', saved.Latest_Location__c, 'An event without a location keeps the last known location.');
        }
    }

    @IsTest
    static void statusAndInvalidEventsAreRejectedPerRequest() {
        System.runAs(TestDataFactory.getUser(OPS)) {
            Shipment__c shipment = shipments(1)[0];
            Account customer = [SELECT Id FROM Account WHERE Customer_Code__c = 'CUST-TRK'];
            TrackingEventRequest wrongSource = new TrackingEventRequest(shipment.Id, 'Location Update', 'Hosur');
            wrongSource.source = 'Carrier Pigeon';
            List<TrackingEventRequest> requests = new List<TrackingEventRequest>{
                new TrackingEventRequest(shipment.Id, 'Delivered', 'Bangalore'), // 0: a status
                new TrackingEventRequest(shipment.Id, 'Created', 'Chennai'), // 1: reserved for creation
                new TrackingEventRequest(shipment.Id, 'Teleported', 'Mars'), // 2: unknown type
                new TrackingEventRequest(null, 'Location Update', 'Hosur'), // 3: no shipment
                new TrackingEventRequest(customer.Id, 'Location Update', 'Hosur'), // 4: not a shipment Id
                wrongSource, // 5: unknown source
                null, // 6: missing request
                new TrackingEventRequest(shipment.Id, 'Hub Departure', 'Chennai Hub') // 7: valid
            };

            ServiceResult result = new TrackingService().recordEvents(requests);

            Assert.isFalse(result.isSuccess);
            Assert.areEqual(TrackingService.STATUS_EVENT_NOT_ALLOWED, result.errorsFor(0)[0].code);
            Assert.areEqual(
                String.format(Label.eLogix_Tracking_Status_Event_Not_Allowed, new List<Object>{ 'Delivered' }),
                result.errorsFor(0)[0].message
            );
            Assert.areEqual(TrackingService.STATUS_EVENT_NOT_ALLOWED, result.errorsFor(1)[0].code);
            for (Integer i = 2; i <= 6; i++) {
                Assert.areEqual(TrackingService.REQUEST_INVALID, result.errorsFor(i)[0].code, 'Request ' + i);
            }
            Assert.isTrue(result.errorsFor(7).isEmpty());
            Assert.areEqual(1, result.recordIds.size());
            Assert.areEqual(1, [SELECT COUNT() FROM Tracking_Event__c WHERE Event_Type__c = 'Hub Departure']);
            Assert.areEqual(0, [SELECT COUNT() FROM Tracking_Event__c WHERE Event_Type__c = 'Delivered']);
        }
    }

    @IsTest
    static void shipmentTheUserCannotSeeIsReportedAsNotFound() {
        Shipment__c hidden;
        System.runAs(TestDataFactory.getUser(OTHER_OPS)) {
            hidden = shipments(1)[0];
        }
        System.runAs(TestDataFactory.getUser(OPS)) {
            ServiceResult result = new TrackingService().recordEvents(new List<TrackingEventRequest>{ gps(hidden.Id, 'Hosur', null, null) });

            Assert.isFalse(result.isSuccess);
            Assert.areEqual(TrackingService.SHIPMENT_NOT_FOUND, result.errors[0].code);
        }
        Assert.areEqual(0, [SELECT COUNT() FROM Tracking_Event__c WHERE Event_Type__c = 'Location Update']);
    }

    @IsTest
    static void managerWithViewAllCanRecordOnAnotherUsersShipment() {
        Shipment__c shipment;
        System.runAs(TestDataFactory.getUser(OPS)) {
            shipment = shipments(1)[0];
        }
        System.runAs(TestDataFactory.getUser(MANAGER)) {
            ServiceResult result = new TrackingService().recordEvents(new List<TrackingEventRequest>{ gps(shipment.Id, 'Hosur', System.now().addMinutes(5), null) });
            Assert.isTrue(result.isSuccess, String.valueOf(result.errors));
        }
        Assert.areEqual('Hosur', summary(shipment.Id).Latest_Location__c);
    }

    @IsTest
    static void userWithoutCreateAccessIsDenied() {
        Shipment__c shipment;
        System.runAs(TestDataFactory.getUser(OPS)) {
            shipment = shipments(1)[0];
        }
        System.runAs(TestDataFactory.getUser(SALES)) {
            try {
                new TrackingService().recordEvents(new List<TrackingEventRequest>{ gps(shipment.Id, 'Hosur', null, null) });
                Assert.fail('Sales Executives cannot create tracking events.');
            } catch (AuthorizationException e) {
                Assert.areEqual(AuthorizationException.ACCESS_DENIED, e.code);
                Assert.areEqual(Label.eLogix_Access_Denied, e.getMessage());
            }
        }
    }

    @IsTest
    static void futureTimestampFailsOnlyThatRequest() {
        System.runAs(TestDataFactory.getUser(OPS)) {
            List<Shipment__c> records = shipments(2);
            List<TrackingEventRequest> requests = new List<TrackingEventRequest>{
                gps(records[0].Id, 'Hosur', System.now().addHours(3), 'GPS-5001'),
                gps(records[1].Id, 'Vellore', System.now().addMinutes(5), 'GPS-5002')
            };

            ServiceResult result = new TrackingService().recordEvents(requests);

            Assert.areEqual(1, result.errors.size());
            Assert.areEqual(0, result.errors[0].recordIndex);
            Assert.areEqual('FIELD_CUSTOM_VALIDATION_EXCEPTION', result.errors[0].code);
            Assert.areEqual(1, result.recordIds.size());
            Assert.isNull(summary(records[0].Id).Latest_Location__c);
            Assert.areEqual('Vellore', summary(records[1].Id).Latest_Location__c);
        }
    }

    @IsTest
    static void longExternalIdsAreHashedToFitTheKey() {
        String shortKey = TrackingService.externalEventKey('GPS Integration', 'GPS-1');
        String longKey = TrackingService.externalEventKey('GPS Integration', 'X'.repeat(120));

        Assert.areEqual('EXT:GPSIntegration:GPS-1', shortKey);
        Assert.isTrue(longKey.startsWith(TrackingService.EXTERNAL_KEY_PREFIX));
        Assert.areEqual(68, longKey.length(), 'Prefix plus a SHA-256 hex digest.');
        Assert.areEqual(longKey, TrackingService.externalEventKey('GPS Integration', 'X'.repeat(120)), 'Hashing is deterministic.');
    }

    @IsTest
    static void bulkEventsUseTwoQueries() {
        System.runAs(TestDataFactory.getUser(OPS)) {
            List<Shipment__c> records = shipments(100);
            List<TrackingEventRequest> requests = new List<TrackingEventRequest>();
            for (Integer i = 0; i < records.size(); i++) {
                requests.add(gps(records[i].Id, 'Hosur', System.now().addMinutes(5), 'GPS-B-' + i));
            }

            Test.startTest();
            Integer queriesBefore = Limits.getQueries();
            ServiceResult result = new TrackingService().recordEvents(requests);
            Integer queries = Limits.getQueries() - queriesBefore;
            Test.stopTest();

            Assert.isTrue(result.isSuccess, String.valueOf(result.errors));
            Assert.areEqual(100, result.recordIds.size());
            Assert.areEqual(2, queries, 'One query for the shipments, one for existing keys; the summary update re-fires the trigger at no cost.');
            Assert.areEqual(100, [SELECT COUNT() FROM Shipment__c WHERE Latest_Location__c = 'Hosur']);
        }
    }

    @IsTest
    static void emptyInputIsANoOp() {
        Assert.isTrue(new TrackingService().recordEvents(null).isSuccess);
        Assert.isTrue(new TrackingService().recordEvents(new List<TrackingEventRequest>()).isSuccess);
    }
}
