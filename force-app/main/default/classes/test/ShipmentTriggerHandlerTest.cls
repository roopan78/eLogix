/**
 * End-to-end tests of ShipmentTrigger: policy enforcement, tracking history, permissions,
 * overrides, bulk behaviour, trigger re-entry and rollback. Every test runs as a role user,
 * because the deploying admin holds every custom permission.
 */
@IsTest
private class ShipmentTriggerHandlerTest {
    private static final String OPS = 'Operations Tester';
    private static final String MANAGER = 'Manager Tester';

    @TestSetup
    static void setup() {
        Business_Unit__c businessUnit = TestDataFactory.createBusinessUnit('BU-TRG');
        TestDataFactory.createCustomer('CUST-TRG', businessUnit.Id);
        TestDataFactory.createUser(OPS, TestDataFactory.OPERATIONS);
        TestDataFactory.createUser(MANAGER, TestDataFactory.LOGISTICS_MANAGER);
    }

    private static List<Shipment__c> build(Integer count, String status) {
        Account customer = [SELECT Id, Business_Unit__c FROM Account WHERE Customer_Code__c = 'CUST-TRG'];
        return TestDataFactory.buildShipments(count, customer.Id, customer.Business_Unit__c, status);
    }

    private static List<Tracking_Event__c> eventsFor(Id shipmentId) {
        return [
            SELECT Event_Type__c, From_Status__c, To_Status__c, Source__c, Event_Key__c, Remarks__c, Event_Timestamp__c
            FROM Tracking_Event__c
            WHERE Shipment__c = :shipmentId
            ORDER BY CreatedDate, Name
        ];
    }

    private static Shipment__c reload(Id shipmentId) {
        return [
            SELECT Id, Status__c, CreatedDate, SystemModstamp, Item_Count__c, Hold_Reason__c, Cancellation_Reason__c, Latest_Tracking_Timestamp__c
            FROM Shipment__c
            WHERE Id = :shipmentId
        ];
    }

    private static String expected(String label, String fromStatus, String toStatus) {
        return String.format(label, new List<Object>{ fromStatus, toStatus });
    }

    /** Draft shipment with one item, moved to Confirmed through allowed transitions. */
    private static Shipment__c confirmedShipment() {
        Shipment__c shipment = build(1, 'Draft')[0];
        insert shipment;
        insert TestDataFactory.buildItems(new List<Shipment__c>{ shipment });
        TestDataFactory.advance(new List<Shipment__c>{ shipment }, new List<String>{ 'Requested', 'Quoted', 'Confirmed' });
        return shipment;
    }

    @IsTest
    static void insertRecordsCreatedEventWithDeterministicKey() {
        System.runAs(TestDataFactory.getUser(OPS)) {
            Shipment__c shipment = build(1, 'Draft')[0];
            insert shipment;

            Shipment__c saved = reload(shipment.Id);
            List<Tracking_Event__c> events = eventsFor(shipment.Id);
            Assert.areEqual(1, events.size());
            Assert.areEqual('Created', events[0].Event_Type__c);
            Assert.isNull(events[0].From_Status__c);
            Assert.areEqual('Draft', events[0].To_Status__c);
            Assert.areEqual(TrackingService.SOURCE_APEX, events[0].Source__c);
            Assert.areEqual(saved.Id + ':NEW>Draft:' + saved.CreatedDate.getTime() + ':1', events[0].Event_Key__c, 'Save identity plus the per-shipment sequence (Phase 5).');
            Assert.isNotNull(saved.Latest_Tracking_Timestamp__c, 'An allowed status change stamps the tracking summary.');
        }
    }

    @IsTest
    static void insertWithNonInitialStatusIsRejected() {
        System.runAs(TestDataFactory.getUser(OPS)) {
            Shipment__c shipment = build(1, 'Dispatched')[0];
            try {
                insert shipment;
                Assert.fail('A shipment cannot be created as Dispatched.');
            } catch (DmlException e) {
                Assert.isTrue(e.getMessage().contains('A new shipment cannot start as Dispatched.'), e.getMessage());
            }
            Assert.areEqual(0, [SELECT COUNT() FROM Shipment__c]);
            Assert.areEqual(0, [SELECT COUNT() FROM Tracking_Event__c]);
        }
    }

    @IsTest
    static void allowedTransitionRecordsOneEvent() {
        System.runAs(TestDataFactory.getUser(OPS)) {
            Shipment__c shipment = build(1, 'Draft')[0];
            insert shipment;
            Shipment__c before = reload(shipment.Id);

            shipment.Status__c = 'Requested';
            update shipment;

            List<Tracking_Event__c> events = eventsFor(shipment.Id);
            Assert.areEqual(2, events.size());
            Tracking_Event__c event = events[1];
            Assert.areEqual('Requested', event.Event_Type__c);
            Assert.areEqual('Draft', event.From_Status__c);
            Assert.areEqual('Requested', event.To_Status__c);
            Assert.areEqual(shipment.Id + ':Draft>Requested:' + before.SystemModstamp.getTime() + ':2', event.Event_Key__c);
        }
    }

    @IsTest
    static void invalidTransitionIsRejectedWithoutEvent() {
        System.runAs(TestDataFactory.getUser(OPS)) {
            Shipment__c shipment = build(1, 'Draft')[0];
            insert shipment;

            shipment.Status__c = 'Delivered';
            shipment.Actual_Delivery_Date__c = Date.today().addDays(2);
            Database.SaveResult result = Database.update(shipment, false);

            Assert.isFalse(result.isSuccess());
            Assert.areEqual(expected(Label.eLogix_Status_Transition_Not_Allowed, 'Draft', 'Delivered'), result.getErrors()[0].getMessage());
            Assert.areEqual('Draft', reload(shipment.Id).Status__c);
            Assert.areEqual(1, eventsFor(shipment.Id).size(), 'Only the Created event exists.');
        }
    }

    @IsTest
    static void confirmationRequiresAnItem() {
        System.runAs(TestDataFactory.getUser(OPS)) {
            Shipment__c shipment = build(1, 'Draft')[0];
            insert shipment;
            TestDataFactory.advance(new List<Shipment__c>{ shipment }, new List<String>{ 'Requested', 'Quoted' });

            shipment.Status__c = 'Confirmed';
            Database.SaveResult rejected = Database.update(shipment, false);
            Assert.isFalse(rejected.isSuccess());
            Assert.areEqual(Label.eLogix_Shipment_Items_Required, rejected.getErrors()[0].getMessage());

            insert TestDataFactory.buildItems(new List<Shipment__c>{ shipment });
            shipment.Status__c = 'Confirmed';
            update shipment;
            Assert.areEqual('Confirmed', reload(shipment.Id).Status__c);
            Assert.areEqual(4, eventsFor(shipment.Id).size(), 'Created, Requested, Quoted, Confirmed.');
        }
    }

    @IsTest
    static void cancellingAfterConfirmationNeedsPermission() {
        System.runAs(TestDataFactory.getUser(OPS)) {
            Shipment__c shipment = confirmedShipment();
            shipment.Status__c = 'Cancelled';
            shipment.Cancellation_Reason__c = 'Customer withdrew the order.';
            Database.SaveResult result = Database.update(shipment, false);

            Assert.isFalse(result.isSuccess());
            Assert.areEqual(expected(Label.eLogix_Status_Permission_Required, 'Confirmed', 'Cancelled'), result.getErrors()[0].getMessage());
            Assert.areEqual('Confirmed', reload(shipment.Id).Status__c);
        }

        System.runAs(TestDataFactory.getUser(MANAGER)) {
            Shipment__c shipment = confirmedShipment();
            shipment.Status__c = 'Cancelled';
            shipment.Cancellation_Reason__c = 'Customer withdrew the order.';
            update shipment;

            List<Tracking_Event__c> events = eventsFor(shipment.Id);
            Tracking_Event__c cancelled = events[events.size() - 1];
            Assert.areEqual('Cancelled', cancelled.Event_Type__c, 'The manager holds the cancel permission, so this is a normal transition.');
            Assert.areEqual('Customer withdrew the order.', cancelled.Remarks__c);
        }
    }

    @IsTest
    static void overrideRecordsAnExceptionEvent() {
        System.runAs(TestDataFactory.getUser(MANAGER)) {
            Shipment__c shipment = build(1, 'Draft')[0];
            insert shipment;

            shipment.Status__c = 'Quoted';
            update shipment;

            List<Tracking_Event__c> events = eventsFor(shipment.Id);
            Tracking_Event__c overridden = events[1];
            Assert.areEqual(ShipmentStatusPolicy.OVERRIDE_EVENT_TYPE, overridden.Event_Type__c);
            Assert.areEqual(
                String.format(Label.eLogix_Status_Override_Remark, new List<Object>{ ShipmentStatusPolicy.TRANSITION_NOT_ALLOWED }),
                overridden.Remarks__c
            );
        }
    }

    @IsTest
    static void overrideCannotReopenFinalStatusesOrReverseDelivery() {
        // Phase 5: Delivered needs a confirmed delivery attempt even under the override (guards always
        // apply), so the delivered shipment is taken through the real lifecycle. Vehicles and drivers
        // are created by the running administrator; the Logistics Manager does the rest.
        Account customer = [SELECT Id, Business_Unit__c FROM Account WHERE Customer_Code__c = 'CUST-TRG'];
        Vehicle__c vehicle = TestDataFactory.buildVehicle('TN-TRG-1', customer.Business_Unit__c);
        Driver__c driver = TestDataFactory.buildDriver('DL-TRG-1', customer.Business_Unit__c);
        insert vehicle;
        insert driver;
        System.runAs(TestDataFactory.getUser(MANAGER)) {
            Shipment__c cancelled = build(1, 'Draft')[0];
            insert cancelled;
            Shipment__c delivered = TestDataFactory.deliveredShipment(customer.Id, customer.Business_Unit__c, vehicle.Id, driver.Id);
            List<Shipment__c> shipments = new List<Shipment__c>{ cancelled, new Shipment__c(Id = delivered.Id) };
            delivered = shipments[1];

            cancelled.Status__c = 'Cancelled';
            cancelled.Cancellation_Reason__c = 'Duplicate booking.';
            update cancelled; // Draft -> Cancelled is configured.

            cancelled.Status__c = 'Draft';
            delivered.Status__c = 'Dispatched';
            List<Database.SaveResult> results = Database.update(shipments, false);

            Assert.areEqual(expected(Label.eLogix_Status_Terminal, 'Cancelled', 'Draft'), results[0].getErrors()[0].getMessage());
            Assert.areEqual(expected(Label.eLogix_Status_Delivered_Reversal, 'Delivered', 'Dispatched'), results[1].getErrors()[0].getMessage());
            Assert.areEqual('Cancelled', reload(cancelled.Id).Status__c);
            Assert.areEqual('Delivered', reload(delivered.Id).Status__c);
        }
    }

    @IsTest
    static void holdReasonIsCopiedToTheEvent() {
        System.runAs(TestDataFactory.getUser(OPS)) {
            Shipment__c shipment = confirmedShipment();
            shipment.Status__c = 'On Hold';
            shipment.Hold_Reason__c = 'Awaiting e-way bill.';
            update shipment;

            List<Tracking_Event__c> events = eventsFor(shipment.Id);
            Assert.areEqual('On Hold', events[events.size() - 1].Event_Type__c);
            Assert.areEqual('Awaiting e-way bill.', events[events.size() - 1].Remarks__c);
        }
    }

    @IsTest
    static void bulkInsertAndUpdateUseOneQueryAndOneInsertEach() {
        System.runAs(TestDataFactory.getUser(OPS)) {
            List<Shipment__c> shipments = build(200, 'Draft');

            Test.startTest();
            Integer queriesBefore = Limits.getQueries();
            Integer dmlBefore = Limits.getDmlStatements();
            insert shipments;
            Integer insertQueries = Limits.getQueries() - queriesBefore;
            Integer insertDml = Limits.getDmlStatements() - dmlBefore;

            for (Shipment__c shipment : shipments) {
                shipment.Status__c = 'Requested';
            }
            queriesBefore = Limits.getQueries();
            dmlBefore = Limits.getDmlStatements();
            update shipments;
            Integer updateQueries = Limits.getQueries() - queriesBefore;
            Integer updateDml = Limits.getDmlStatements() - dmlBefore;
            Test.stopTest();

            Assert.areEqual(2, insertQueries, 'Insert: the status-event count (aggregate) and the identity keys (Phase 5 sequence).');
            Assert.areEqual(2, insertDml, 'Insert: the shipment insert plus one tracking insert.');
            Assert.areEqual(2, updateQueries, 'Update: the status-event count (aggregate) and the identity keys (Phase 5 sequence).');
            Assert.areEqual(2, updateDml, 'Update: the shipment update plus one tracking insert.');
            Assert.areEqual(200, [SELECT COUNT() FROM Tracking_Event__c WHERE Event_Type__c = 'Created']);
            Assert.areEqual(200, [SELECT COUNT() FROM Tracking_Event__c WHERE Event_Type__c = 'Requested']);
        }
    }

    @IsTest
    static void partialSuccessKeepsValidRowsAndRejectsInvalidOnes() {
        System.runAs(TestDataFactory.getUser(OPS)) {
            List<Shipment__c> shipments = build(200, 'Draft');
            insert shipments;
            for (Integer i = 0; i < shipments.size(); i++) {
                shipments[i].Status__c = Math.mod(i, 2) == 0 ? 'Requested' : 'Closed';
            }

            List<Database.SaveResult> results = Database.update(shipments, false);

            Integer succeeded = 0;
            for (Integer i = 0; i < results.size(); i++) {
                Boolean shouldSucceed = Math.mod(i, 2) == 0;
                Assert.areEqual(shouldSucceed, results[i].isSuccess(), 'Row ' + i);
                if (shouldSucceed) {
                    succeeded++;
                } else {
                    Assert.areEqual(expected(Label.eLogix_Status_Transition_Not_Allowed, 'Draft', 'Closed'), results[i].getErrors()[0].getMessage());
                }
            }
            Assert.areEqual(100, succeeded);
            Assert.areEqual(100, [SELECT COUNT() FROM Shipment__c WHERE Status__c = 'Requested']);
            Assert.areEqual(100, [SELECT COUNT() FROM Shipment__c WHERE Status__c = 'Draft']);
            Assert.areEqual(100, [SELECT COUNT() FROM Tracking_Event__c WHERE Event_Type__c = 'Requested']);
            Assert.areEqual(0, [SELECT COUNT() FROM Tracking_Event__c WHERE Event_Type__c = 'Closed']);
        }
    }

    @IsTest
    static void rollUpRecalculationReFiresTriggerWithoutEvents() {
        System.runAs(TestDataFactory.getUser(OPS)) {
            List<Shipment__c> shipments = build(50, 'Draft');
            insert shipments;
            Integer eventsBefore = [SELECT COUNT() FROM Tracking_Event__c];

            Test.startTest();
            Integer queriesBefore = Limits.getQueries();
            insert TestDataFactory.buildItems(shipments);
            Integer itemQueries = Limits.getQueries() - queriesBefore;
            Test.stopTest();

            Assert.areEqual(0, itemQueries, 'A save without a status change must not query.');
            Assert.areEqual(eventsBefore, [SELECT COUNT() FROM Tracking_Event__c]);
            Assert.areEqual(50, [SELECT COUNT() FROM Shipment__c WHERE Item_Count__c = 1]);
        }
    }

    /**
     * Re-entry through the real trigger path. A workflow or flow re-fire runs the after-trigger again
     * with the original Trigger.old, so it computes the key of an event that already exists. The test
     * stores that event first, then makes the status change: the trigger must find the key and write
     * nothing. The opposite case (key absent, so the event is written, as after a partial-success
     * rollback) is the normal path, asserted in allowedTransitionRecordsOneEvent.
     */
    @IsTest
    static void reEntryWithTheSameVersionDoesNotDuplicateEvents() {
        Shipment__c shipment;
        System.runAs(TestDataFactory.getUser(OPS)) {
            shipment = build(1, 'Draft')[0];
            insert shipment;
        }
        Shipment__c original = reload(shipment.Id);
        // The key the first run of this save would write: its identity and sequence 2 (after Created).
        String expectedKey = original.Id + ':Draft>Requested:' + original.SystemModstamp.getTime() + ':2';
        insert new Tracking_Event__c(
            Shipment__c = original.Id,
            Event_Type__c = 'Requested',
            Event_Timestamp__c = System.now(),
            From_Status__c = 'Draft',
            To_Status__c = 'Requested',
            Event_Key__c = expectedKey,
            Remarks__c = 'Written by the first trigger run.'
        );
        Assert.areEqual(original.SystemModstamp, reload(original.Id).SystemModstamp, 'Adding history must not change the shipment version.');

        System.runAs(TestDataFactory.getUser(OPS)) {
            shipment.Status__c = 'Requested';
            update shipment;
        }

        List<Tracking_Event__c> requested = [
            SELECT Event_Key__c, Remarks__c
            FROM Tracking_Event__c
            WHERE Shipment__c = :original.Id AND Event_Type__c = 'Requested'
        ];
        Assert.areEqual(1, requested.size(), 'The re-fired trigger must not write a second event.');
        Assert.areEqual(expectedKey, requested[0].Event_Key__c);
        Assert.areEqual('Written by the first trigger run.', requested[0].Remarks__c);
        Assert.areEqual('Requested', reload(original.Id).Status__c, 'Skipping a recorded event does not block the save.');
    }

    /** F1: status history cannot be written from outside the Shipment__c trigger, even through the handler test seam. */
    @IsTest
    static void statusEventsCannotBeRecordedOutsideTheShipmentTrigger() {
        System.runAs(TestDataFactory.getUser(OPS)) {
            Shipment__c shipment = build(1, 'Draft')[0];
            insert shipment;
            Shipment__c previous = reload(shipment.Id);
            Shipment__c fabricated = previous.clone(true, true, true, true);
            fabricated.Status__c = 'Delivered';

            try {
                new TrackingService().recordStatusEvents();
                Assert.fail('recordStatusEvents must refuse to run outside a trigger.');
            } catch (AuthorizationException e) {
                Assert.areEqual(TrackingService.STATUS_EVENTS_TRIGGER_ONLY, e.code);
                Assert.areEqual(Label.eLogix_Access_Denied, e.getMessage());
            }

            try {
                new ShipmentTriggerHandler(
                        System.TriggerOperation.AFTER_UPDATE,
                        new List<Shipment__c>{ fabricated },
                        new Map<Id, Shipment__c>{ previous.Id => previous }
                    )
                    .run();
                Assert.fail('Fabricated before and after records must not produce status history.');
            } catch (AuthorizationException e) {
                Assert.areEqual(TrackingService.STATUS_EVENTS_TRIGGER_ONLY, e.code);
            }

            Assert.areEqual(0, [SELECT COUNT() FROM Tracking_Event__c WHERE Shipment__c = :shipment.Id AND Event_Type__c = 'Delivered']);
            Assert.areEqual('Draft', reload(shipment.Id).Status__c);
        }
    }

    @IsTest
    static void consecutiveTransitionsInOneTransactionEachRecordAnEvent() {
        System.runAs(TestDataFactory.getUser(OPS)) {
            Shipment__c shipment = build(1, 'Draft')[0];
            insert shipment;
            TestDataFactory.advance(new List<Shipment__c>{ shipment }, new List<String>{ 'Requested', 'Quoted' });
            shipment.Status__c = 'Cancelled'; // free before confirmation
            shipment.Cancellation_Reason__c = 'Customer chose another carrier.';
            update shipment;

            List<Tracking_Event__c> events = eventsFor(shipment.Id);
            List<String> types = new List<String>();
            Set<String> keys = new Set<String>();
            for (Tracking_Event__c event : events) {
                types.add(event.Event_Type__c);
                keys.add(event.Event_Key__c);
            }
            Assert.areEqual(new List<String>{ 'Created', 'Requested', 'Quoted', 'Cancelled' }, types);
            Assert.areEqual(4, keys.size(), 'Every transition has its own key.');
        }
    }

    @IsTest
    static void trackingFailureRollsBackTheStatusChange() {
        System.runAs(TestDataFactory.getUser(OPS)) {
            List<Shipment__c> shipments = build(2, 'Draft');
            insert shipments;

            // A timestamp a day ahead fails TE_Timestamp_Not_In_Future, so the event insert fails.
            TrackingService.nowOverride = System.now().addDays(1);
            shipments[0].Status__c = 'Requested';
            try {
                update shipments[0];
                Assert.fail('The update must fail when its tracking event cannot be written.');
            } catch (DmlException e) {
                Assert.isTrue(e.getMessage().contains(Label.eLogix_Tracking_Event_Failed), e.getMessage());
            }

            shipments[1].Status__c = 'Requested';
            Database.SaveResult partial = Database.update(shipments[1], false);
            Assert.isFalse(partial.isSuccess());
            Assert.areEqual(Label.eLogix_Tracking_Event_Failed, partial.getErrors()[0].getMessage());
            TrackingService.nowOverride = null;

            Assert.areEqual(2, [SELECT COUNT() FROM Shipment__c WHERE Status__c = 'Draft'], 'Both status changes were rolled back.');
            Assert.areEqual(0, [SELECT COUNT() FROM Tracking_Event__c WHERE Event_Type__c = 'Requested']);
        }
    }

    @IsTest
    static void savesWithoutStatusChangeCostNothing() {
        System.runAs(TestDataFactory.getUser(OPS)) {
            List<Shipment__c> shipments = build(200, 'Draft');
            insert shipments;
            Integer eventsBefore = [SELECT COUNT() FROM Tracking_Event__c];
            for (Shipment__c shipment : shipments) {
                shipment.Special_Instructions__c = 'Handle with care.';
            }

            Test.startTest();
            Integer queriesBefore = Limits.getQueries();
            Integer dmlBefore = Limits.getDmlStatements();
            update shipments;
            Integer queries = Limits.getQueries() - queriesBefore;
            Integer dml = Limits.getDmlStatements() - dmlBefore;
            Test.stopTest();

            Assert.areEqual(0, queries, 'A save without a status change must not query.');
            Assert.areEqual(1, dml, 'Only the shipment update itself.');
            Assert.areEqual(eventsBefore, [SELECT COUNT() FROM Tracking_Event__c]);
        }
    }
}
