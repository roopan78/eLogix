/**
 * Status event keys with a per-shipment sequence (Phase 5 fix to the Phase 2 key):
 * {shipmentId}:{From}>{To}:{previous version}:{sequence}. Every legitimate status change is recorded,
 * even when the same transition repeats within one second; a re-fired trigger for the same save still
 * finds its event and writes nothing; keys stay unique and ordered; stored keys are never rewritten.
 */
@IsTest
private class TrackingEventSequenceTest {
    private static final String OPS = 'Sequence Ops Tester';

    @TestSetup
    static void setup() {
        Business_Unit__c businessUnit = TestDataFactory.createBusinessUnit('BU-SQ');
        TestDataFactory.createCustomer('CUST-SQ', businessUnit.Id);
        TestDataFactory.createUser(OPS, TestDataFactory.OPERATIONS);
    }

    private static List<Shipment__c> confirmed(Integer count) {
        Account c = [SELECT Id, Business_Unit__c FROM Account WHERE Customer_Code__c = 'CUST-SQ'];
        List<Shipment__c> records;
        System.runAs(TestDataFactory.getUser(OPS)) {
            records = TestDataFactory.confirmedShipments(count, c.Id, c.Business_Unit__c);
        }
        return records;
    }

    /** Confirmed -> On Hold -> Confirmed for every shipment, `cycles` times, one bulk save per step. */
    private static void cycle(List<Shipment__c> shipments, Integer cycles) {
        System.runAs(TestDataFactory.getUser(OPS)) {
            for (Integer i = 0; i < cycles; i++) {
                List<Shipment__c> hold = new List<Shipment__c>();
                List<Shipment__c> resume = new List<Shipment__c>();
                for (Shipment__c shipment : shipments) {
                    hold.add(new Shipment__c(Id = shipment.Id, Status__c = 'On Hold', Hold_Reason__c = 'Hold ' + i));
                    resume.add(new Shipment__c(Id = shipment.Id, Status__c = 'Confirmed'));
                }
                update hold;
                update resume;
            }
        }
    }

    private static List<Tracking_Event__c> statusEvents(Id shipmentId) {
        return [
            SELECT To_Status__c, Event_Key__c
            FROM Tracking_Event__c
            WHERE Shipment__c = :shipmentId AND To_Status__c != NULL
            ORDER BY Event_Timestamp__c, CreatedDate, Id
        ];
    }

    private static Integer sequenceOf(String key) {
        return Integer.valueOf(key.substringAfterLast(':'));
    }

    /** Rapid repeats of the same transitions within one transaction (well within one second). */
    @IsTest
    static void everyRepeatedTransitionIsRecordedInOrder() {
        Shipment__c shipment = confirmed(1)[0];
        cycle(new List<Shipment__c>{ shipment }, 3);

        List<Tracking_Event__c> events = statusEvents(shipment.Id);
        // Created(Draft), Requested, Quoted, Confirmed, then 3 x (On Hold, Confirmed).
        Assert.areEqual(10, events.size());
        Set<String> keys = new Set<String>();
        for (Integer i = 0; i < events.size(); i++) {
            Assert.isTrue(keys.add(events[i].Event_Key__c), 'Unique key: ' + events[i].Event_Key__c);
            Assert.isTrue(events[i].Event_Key__c.startsWith(shipment.Id + ':'));
            Assert.areEqual(i + 1, sequenceOf(events[i].Event_Key__c), 'The sequence follows the shipment history: ' + events[i].Event_Key__c);
        }
        Integer holds = 0;
        for (Tracking_Event__c event : events) {
            holds += event.To_Status__c == 'On Hold' ? 1 : 0;
        }
        Assert.areEqual(3, holds, 'Each repeat of Confirmed -> On Hold has its own event.');
    }

    @IsTest
    static void bulkShipmentsEachKeepTheirOwnSequence() {
        List<Shipment__c> shipments = confirmed(50);
        Set<Id> ids = new Map<Id, Shipment__c>(shipments).keySet();

        Test.startTest();
        cycle(shipments, 2);
        Test.stopTest();

        List<Tracking_Event__c> all = [
            SELECT Shipment__c, Event_Key__c
            FROM Tracking_Event__c
            WHERE Shipment__c IN :ids AND To_Status__c != NULL
            ORDER BY Shipment__c, Event_Timestamp__c, CreatedDate, Id
        ];
        Assert.areEqual(50 * 8, all.size(), 'Four lifecycle events and four cycle events per shipment.');
        Set<String> keys = new Set<String>();
        Map<Id, Integer> lastSequence = new Map<Id, Integer>();
        for (Tracking_Event__c event : all) {
            Assert.isTrue(keys.add(event.Event_Key__c), 'Keys are unique across the batch.');
            Integer previous = lastSequence.containsKey(event.Shipment__c) ? lastSequence.get(event.Shipment__c) : 0;
            Assert.areEqual(previous + 1, sequenceOf(event.Event_Key__c), 'Each shipment counts its own history.');
            lastSequence.put(event.Shipment__c, previous + 1);
        }
    }

    /**
     * Duplicate prevention is kept, even in the hardest case: a re-fired trigger for a save whose
     * identity (same transition, same previous version to the second) already occurred earlier.
     * The event the first run of the save would write is stored first; the save must not add another.
     */
    @IsTest
    static void aReFiredSaveStillWritesNothing() {
        Shipment__c shipment = confirmed(1)[0];
        cycle(new List<Shipment__c>{ shipment }, 1);
        Shipment__c current = [SELECT Id, SystemModstamp FROM Shipment__c WHERE Id = :shipment.Id];
        String identity = current.Id + ':Confirmed>OnHold:' + current.SystemModstamp.getTime();
        Integer total = [SELECT COUNT() FROM Tracking_Event__c WHERE Shipment__c = :shipment.Id AND To_Status__c != NULL];
        String expectedKey = identity + ':' + (total + 1); // what the first run of the next save writes
        insert new Tracking_Event__c(
            Shipment__c = shipment.Id,
            Event_Type__c = 'On Hold',
            Event_Timestamp__c = System.now(),
            From_Status__c = 'Confirmed',
            To_Status__c = 'On Hold',
            Event_Key__c = expectedKey,
            Remarks__c = 'Written by the first trigger run.'
        );
        // The earlier, legitimate On Hold event of the cycle usually shares this identity (same
        // second); it is counted here too and must stay distinct from the save's own event.
        Integer statusEventsBefore = [SELECT COUNT() FROM Tracking_Event__c WHERE Shipment__c = :shipment.Id AND To_Status__c != NULL];

        System.runAs(TestDataFactory.getUser(OPS)) {
            update new Shipment__c(Id = shipment.Id, Status__c = 'On Hold', Hold_Reason__c = 'Again.');
        }

        Assert.areEqual(
            statusEventsBefore,
            [SELECT COUNT() FROM Tracking_Event__c WHERE Shipment__c = :shipment.Id AND To_Status__c != NULL],
            'The save found its event already recorded and wrote no second one.'
        );
        Assert.areEqual('Written by the first trigger run.', [SELECT Remarks__c FROM Tracking_Event__c WHERE Event_Key__c = :expectedKey].Remarks__c);
        Assert.areEqual('On Hold', [SELECT Status__c FROM Shipment__c WHERE Id = :shipment.Id].Status__c);
    }

    /** Keys stored before the sequence existed are kept as they are and counted in the history. */
    @IsTest
    static void historicalKeysAreKept() {
        Shipment__c shipment = confirmed(1)[0];
        String legacyKey = shipment.Id + ':Confirmed>OnHold:1700000000000';
        insert new Tracking_Event__c(
            Shipment__c = shipment.Id,
            Event_Type__c = 'On Hold',
            Event_Timestamp__c = System.now().addDays(-30),
            From_Status__c = 'Confirmed',
            To_Status__c = 'On Hold',
            Event_Key__c = legacyKey
        );
        Integer before = [SELECT COUNT() FROM Tracking_Event__c WHERE Shipment__c = :shipment.Id AND To_Status__c != NULL];

        cycle(new List<Shipment__c>{ shipment }, 1);

        Assert.areEqual(1, [SELECT COUNT() FROM Tracking_Event__c WHERE Event_Key__c = :legacyKey], 'The stored key is not rewritten.');
        Tracking_Event__c newest = [
            SELECT Event_Key__c
            FROM Tracking_Event__c
            WHERE Shipment__c = :shipment.Id AND To_Status__c = 'Confirmed'
            ORDER BY CreatedDate DESC, Id DESC
            LIMIT 1
        ];
        Assert.areEqual(before + 2, sequenceOf(newest.Event_Key__c), 'The sequence continues after the existing history.');
    }
}
