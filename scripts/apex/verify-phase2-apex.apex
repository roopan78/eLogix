// eLogix ERP - Phase 2 post-deploy verification (status policy, tracking, trigger).
//
// Runs against the live org as the executing user, then rolls everything back (no data or storage
// left behind). The executing admin holds eLogix_Override_Shipment_Status through
// eLogix_Administrator, so the override paths and the hard rules that override cannot skip are
// both exercised.
//
//   sf apex run --file scripts/apex/verify-phase2-apex.apex --target-org eLogixDev
//
// Expect "SMOKE SUMMARY checks=12 failures=0" in the output.

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

    String lastEventType(Id shipmentId) {
        List<Tracking_Event__c> events = [
            SELECT Event_Type__c FROM Tracking_Event__c WHERE Shipment__c = :shipmentId ORDER BY CreatedDate DESC, Name DESC LIMIT 1
        ];
        return events.isEmpty() ? null : events[0].Event_Type__c;
    }

    String firstError(Database.SaveResult result) {
        return result.isSuccess() ? '(saved)' : result.getErrors()[0].getMessage();
    }
}

Smoke smoke = new Smoke();
Integer activeTransitions = 0;
for (Shipment_Status_Transition__mdt row : Shipment_Status_Transition__mdt.getAll().values()) {
    if (row.Is_Active__c) {
        activeTransitions++;
    }
}
smoke.check('46 active status transitions deployed', activeTransitions == 46, 'found ' + activeTransitions);
smoke.check(
    'running user holds the override permission',
    FeatureManagement.checkPermission('eLogix_Override_Shipment_Status'),
    'assign eLogix_Administrator first'
);

Savepoint savepoint = Database.setSavepoint();
try {
    Business_Unit__c businessUnit = new Business_Unit__c(Name = 'Smoke Business Unit P2', Business_Unit_Code__c = 'SMOKE-P2', Is_Active__c = true);
    insert businessUnit;
    Account customer = new Account(Name = 'Smoke Customer P2');
    insert customer;

    List<Shipment__c> shipments = new List<Shipment__c>();
    for (Integer i = 0; i < 4; i++) {
        shipments.add(
            new Shipment__c(
                Customer__c = customer.Id,
                Business_Unit__c = businessUnit.Id,
                Origin__c = 'Chennai',
                Destination__c = 'Bangalore',
                Weight__c = 100,
                Distance__c = 350,
                Pickup_Date__c = Date.today().addDays(1),
                Expected_Delivery_Date__c = Date.today().addDays(3),
                Status__c = 'Draft'
            )
        );
    }
    insert shipments;
    smoke.check('insert writes a Created event', [SELECT COUNT() FROM Tracking_Event__c WHERE Shipment__c IN :shipments AND Event_Type__c = 'Created'] == 4, 'expected 4');

    Shipment__c lifecycle = shipments[0];
    lifecycle.Status__c = 'Requested';
    update lifecycle;
    Tracking_Event__c requested = [SELECT Event_Key__c, From_Status__c, Source__c FROM Tracking_Event__c WHERE Shipment__c = :lifecycle.Id AND Event_Type__c = 'Requested'];
    smoke.check(
        'allowed transition writes a keyed event',
        requested.From_Status__c == 'Draft' && requested.Event_Key__c.startsWith(lifecycle.Id + ':Draft>Requested:') && requested.Source__c == 'Apex Service',
        requested.Event_Key__c + ' ' + requested.Source__c
    );

    lifecycle.Status__c = 'Cancelled';
    lifecycle.Cancellation_Reason__c = 'Smoke test.';
    update lifecycle;
    smoke.check('cancellation event carries the reason', [SELECT Remarks__c FROM Tracking_Event__c WHERE Shipment__c = :lifecycle.Id AND Event_Type__c = 'Cancelled'].Remarks__c == 'Smoke test.', 'remarks differ');

    lifecycle.Status__c = 'Draft';
    Database.SaveResult reopen = Database.update(lifecycle, false);
    smoke.check('override cannot reopen Cancelled', !reopen.isSuccess() && smoke.firstError(reopen).contains('final status'), smoke.firstError(reopen));

    Shipment__c overridden = shipments[1];
    overridden.Status__c = 'Quoted';
    update overridden;
    smoke.check('override records an Exception event', smoke.lastEventType(overridden.Id) == 'Exception', smoke.lastEventType(overridden.Id));

    Shipment__c delivered = shipments[2];
    delivered.Status__c = 'Delivered';
    delivered.Actual_Delivery_Date__c = Date.today().addDays(2);
    update delivered;
    delivered.Status__c = 'Dispatched';
    Database.SaveResult reverse = Database.update(delivered, false);
    smoke.check('override cannot reverse a delivery', !reverse.isSuccess() && smoke.firstError(reverse).contains('delivered shipment'), smoke.firstError(reverse));

    Shipment__c unconfirmed = shipments[3];
    unconfirmed.Status__c = 'Confirmed';
    Database.SaveResult noItems = Database.update(unconfirmed, false);
    smoke.check('item guard applies under override', !noItems.isSuccess() && smoke.firstError(noItems) == Label.eLogix_Shipment_Items_Required, smoke.firstError(noItems));

    insert new Shipment_Item__c(Shipment__c = unconfirmed.Id, Item_Name__c = 'Smoke item', Quantity__c = 1, Weight__c = 10);
    smoke.check('roll-up re-fire writes no event', [SELECT COUNT() FROM Tracking_Event__c WHERE Shipment__c = :unconfirmed.Id] == 1, 'unexpected event');

    ServiceResult tracked = new TrackingService().recordEvents(
        new List<TrackingEventRequest>{ new TrackingEventRequest(unconfirmed.Id, 'Location Update', 'Krishnagiri') }
    );
    smoke.check(
        'operational event updates the tracking summary',
        tracked.isSuccess && [SELECT Latest_Location__c FROM Shipment__c WHERE Id = :unconfirmed.Id].Latest_Location__c == 'Krishnagiri',
        String.valueOf(tracked.errors)
    );
} finally {
    Database.rollback(savepoint);
}
smoke.check('no rows left behind', [SELECT COUNT() FROM Shipment__c WHERE Business_Unit__r.Business_Unit_Code__c = 'SMOKE-P2'] == 0, 'rows remain');
System.debug(LoggingLevel.ERROR, 'SMOKE SUMMARY checks=' + smoke.checks + ' failures=' + smoke.failures);
