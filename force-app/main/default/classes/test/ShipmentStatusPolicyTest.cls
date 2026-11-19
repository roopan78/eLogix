/**
 * Pure unit tests for ShipmentStatusPolicy: injected transition rows and in-memory shipments, no
 * DML. Custom permissions are forced through PermissionService.testOverrides in every test,
 * because the deploying admin really holds the override permission.
 */
@IsTest
private class ShipmentStatusPolicyTest {
    private static final String CANCEL = TestDataFactory.CANCEL_PERMISSION;
    private static final String OVERRIDE_PERMISSION = ShipmentStatusPolicy.OVERRIDE_PERMISSION;

    private static void grant(Boolean canOverride, Boolean canCancel) {
        PermissionService.testOverrides.put(OVERRIDE_PERMISSION, canOverride);
        PermissionService.testOverrides.put(CANCEL, canCancel);
    }

    private static Shipment_Status_Transition__mdt row(String fromStatus, String toStatus, String eventType, String permission, Boolean active) {
        return new Shipment_Status_Transition__mdt(
            From_Status__c = fromStatus,
            To_Status__c = toStatus,
            Tracking_Event_Type__c = eventType,
            Required_Permission__c = permission,
            Is_Active__c = active
        );
    }

    private static List<Shipment_Status_Transition__mdt> standardRows() {
        return new List<Shipment_Status_Transition__mdt>{
            row(null, 'Draft', 'Created', null, true),
            row('Draft', 'Requested', null, null, true),
            row('Requested', 'Quoted', 'Quoted', null, true),
            row('Quoted', 'Confirmed', 'Confirmed', null, true),
            row('Confirmed', 'Cancelled', 'Cancelled', CANCEL, true),
            row('Draft', 'Cancelled', 'Cancelled', null, false),
            row('Out for Delivery', 'Delivered', 'Delivered', null, true),
            row('Delivered', 'Closed', 'Closed', null, true)
        };
    }

    private static ShipmentStatusPolicy policy(List<Shipment_Status_Transition__mdt> rows) {
        return new ShipmentStatusPolicy(rows, ShipmentStatusPolicy.defaultGuards());
    }

    private static ShipmentStatusPolicy.Decision decide(ShipmentStatusPolicy policy, String fromStatus, String toStatus, Integer itemCount) {
        Shipment__c record = TestDataFactory.shipmentInMemory(TestDataFactory.fakeId(Shipment__c.SObjectType, 1), toStatus, itemCount);
        return policy.evaluate(new List<ShipmentStatusPolicy.StatusChange>{ new ShipmentStatusPolicy.StatusChange(0, record, fromStatus, toStatus) })[0];
    }

    private static ShipmentStatusPolicy.Decision decide(ShipmentStatusPolicy policy, String fromStatus, String toStatus) {
        return decide(policy, fromStatus, toStatus, 1);
    }

    private static void assertRejected(ShipmentStatusPolicy.Decision decision, String expectedCode) {
        Assert.areEqual(ShipmentStatusPolicy.Outcome.REJECTED, decision.outcome, 'Expected a rejection: ' + decision.message);
        Assert.areEqual(expectedCode, decision.reasonCode, 'Wrong reason code.');
        Assert.isTrue(String.isNotBlank(decision.message), 'A rejection must carry a user message.');
        Assert.isFalse(decision.requiresTrackingEvent(), 'A rejected change must not produce a tracking event.');
    }

    @IsTest
    static void allowedTransitionUsesConfiguredEventType() {
        grant(false, false);
        ShipmentStatusPolicy.Decision decision = decide(policy(standardRows()), 'Requested', 'Quoted');

        Assert.areEqual(ShipmentStatusPolicy.Outcome.ALLOWED, decision.outcome);
        Assert.areEqual('Quoted', decision.trackingEventType);
        Assert.isTrue(decision.requiresTrackingEvent());
        Assert.isNull(decision.overriddenReasonCode);
    }

    @IsTest
    static void blankEventTypeDefaultsToTargetStatus() {
        grant(false, false);
        ShipmentStatusPolicy.Decision decision = decide(policy(standardRows()), 'Draft', 'Requested');

        Assert.areEqual(ShipmentStatusPolicy.Outcome.ALLOWED, decision.outcome);
        Assert.areEqual('Requested', decision.trackingEventType);
    }

    @IsTest
    static void creationAllowedOnlyForInitialStatuses() {
        grant(false, false);
        ShipmentStatusPolicy policy = policy(standardRows());

        ShipmentStatusPolicy.Decision draft = decide(policy, null, 'Draft');
        Assert.areEqual(ShipmentStatusPolicy.Outcome.ALLOWED, draft.outcome);
        Assert.areEqual('Created', draft.trackingEventType);
        Assert.isNull(draft.fromStatus);

        ShipmentStatusPolicy.Decision confirmed = decide(policy, null, 'Confirmed');
        assertRejected(confirmed, ShipmentStatusPolicy.INITIAL_STATUS_NOT_ALLOWED);
        Assert.areEqual(String.format(Label.eLogix_Status_Initial_Not_Allowed, new List<Object>{ null, 'Confirmed', 'Draft' }), confirmed.message);
    }

    @IsTest
    static void unlistedTransitionRejected() {
        grant(false, false);
        ShipmentStatusPolicy.Decision decision = decide(policy(standardRows()), 'Draft', 'Confirmed');

        assertRejected(decision, ShipmentStatusPolicy.TRANSITION_NOT_ALLOWED);
        Assert.areEqual(String.format(Label.eLogix_Status_Transition_Not_Allowed, new List<Object>{ 'Draft', 'Confirmed' }), decision.message);
    }

    @IsTest
    static void inactiveTransitionRejected() {
        grant(false, false);
        assertRejected(decide(policy(standardRows()), 'Draft', 'Cancelled'), ShipmentStatusPolicy.TRANSITION_INACTIVE);
    }

    @IsTest
    static void permissionGatedTransitionNeedsThePermission() {
        grant(false, false);
        assertRejected(decide(policy(standardRows()), 'Confirmed', 'Cancelled'), ShipmentStatusPolicy.PERMISSION_REQUIRED);

        grant(false, true);
        ShipmentStatusPolicy.Decision allowed = decide(policy(standardRows()), 'Confirmed', 'Cancelled');
        Assert.areEqual(ShipmentStatusPolicy.Outcome.ALLOWED, allowed.outcome);
        Assert.areEqual('Cancelled', allowed.trackingEventType);
    }

    @IsTest
    static void overrideAllowsUnlistedTransitionAsException() {
        grant(true, false);
        ShipmentStatusPolicy.Decision decision = decide(policy(standardRows()), 'Draft', 'Quoted');

        Assert.areEqual(ShipmentStatusPolicy.Outcome.ALLOWED_BY_OVERRIDE, decision.outcome);
        Assert.areEqual(ShipmentStatusPolicy.OVERRIDE_EVENT_TYPE, decision.trackingEventType);
        Assert.areEqual(ShipmentStatusPolicy.TRANSITION_NOT_ALLOWED, decision.overriddenReasonCode);
        Assert.isTrue(String.isNotBlank(decision.overriddenMessage));
        Assert.isTrue(decision.requiresTrackingEvent());
    }

    @IsTest
    static void overrideKeepsConfiguredEventTypeWhenARowExists() {
        grant(true, false);
        ShipmentStatusPolicy.Decision decision = decide(policy(standardRows()), 'Confirmed', 'Cancelled');

        Assert.areEqual(ShipmentStatusPolicy.Outcome.ALLOWED_BY_OVERRIDE, decision.outcome);
        Assert.areEqual('Cancelled', decision.trackingEventType);
        Assert.areEqual(ShipmentStatusPolicy.PERMISSION_REQUIRED, decision.overriddenReasonCode);
    }

    @IsTest
    static void overrideAllowsInactiveTransitionAndInitialStatus() {
        grant(true, false);
        ShipmentStatusPolicy policy = policy(standardRows());

        ShipmentStatusPolicy.Decision inactive = decide(policy, 'Draft', 'Cancelled');
        Assert.areEqual(ShipmentStatusPolicy.Outcome.ALLOWED_BY_OVERRIDE, inactive.outcome);
        Assert.areEqual(ShipmentStatusPolicy.TRANSITION_INACTIVE, inactive.overriddenReasonCode);
        Assert.areEqual(ShipmentStatusPolicy.OVERRIDE_EVENT_TYPE, inactive.trackingEventType);

        ShipmentStatusPolicy.Decision initial = decide(policy, null, 'Quoted');
        Assert.areEqual(ShipmentStatusPolicy.Outcome.ALLOWED_BY_OVERRIDE, initial.outcome);
        Assert.areEqual(ShipmentStatusPolicy.INITIAL_STATUS_NOT_ALLOWED, initial.overriddenReasonCode);
    }

    @IsTest
    static void hardRulesCannotBeOverriddenEvenWhenConfigured() {
        grant(true, true);
        List<Shipment_Status_Transition__mdt> rows = standardRows();
        // A misconfigured row must not reopen a final status or reverse a delivery.
        rows.add(row('Closed', 'Draft', 'Draft', null, true));
        rows.add(row('Delivered', 'Dispatched', 'Dispatched', null, true));
        ShipmentStatusPolicy policy = policy(rows);

        assertRejected(decide(policy, 'Closed', 'Draft'), ShipmentStatusPolicy.TERMINAL_STATUS);
        assertRejected(decide(policy, 'Cancelled', 'Confirmed'), ShipmentStatusPolicy.TERMINAL_STATUS);
        assertRejected(decide(policy, 'Delivered', 'Dispatched'), ShipmentStatusPolicy.DELIVERED_REVERSAL);
        assertRejected(decide(policy, 'Delivered', 'Out for Delivery'), ShipmentStatusPolicy.DELIVERED_REVERSAL);
        assertRejected(decide(policy, 'Delivered', 'Draft'), ShipmentStatusPolicy.DELIVERED_REVERSAL);

        ShipmentStatusPolicy.Decision terminal = decide(policy, 'Cancelled', 'Confirmed');
        Assert.areEqual(String.format(Label.eLogix_Status_Terminal, new List<Object>{ 'Cancelled', 'Confirmed' }), terminal.message);

        // Leaving Delivered forward is still governed by the table.
        Assert.areEqual(ShipmentStatusPolicy.Outcome.ALLOWED, decide(policy, 'Delivered', 'Closed').outcome);
    }

    @IsTest
    static void missingConfigurationFailsClosedForEveryone() {
        grant(true, true);
        assertRejected(decide(policy(new List<Shipment_Status_Transition__mdt>()), 'Draft', 'Requested'), ShipmentStatusPolicy.CONFIGURATION_MISSING);
        assertRejected(decide(policy(null), null, 'Draft'), ShipmentStatusPolicy.CONFIGURATION_MISSING);

        List<Shipment_Status_Transition__mdt> inactiveOnly = new List<Shipment_Status_Transition__mdt>{ row('Draft', 'Requested', null, null, false) };
        assertRejected(decide(policy(inactiveOnly), 'Draft', 'Requested'), ShipmentStatusPolicy.CONFIGURATION_MISSING);
    }

    @IsTest
    static void invalidConfigurationBlocksItsTransitionEvenUnderOverride() {
        grant(true, true);
        List<Shipment_Status_Transition__mdt> rows = standardRows();
        rows.add(row('Requested', 'Quoted', 'Quoted', null, true)); // second active row for the same pair
        rows.add(row('Quoted', 'On Hold', 'Beamed Up', null, true)); // unknown event type
        rows.add(row('Teleported', 'Draft', null, null, true)); // unknown from status
        ShipmentStatusPolicy policy = policy(rows);

        assertRejected(decide(policy, 'Requested', 'Quoted'), ShipmentStatusPolicy.CONFIGURATION_INVALID);
        assertRejected(decide(policy, 'Quoted', 'On Hold'), ShipmentStatusPolicy.CONFIGURATION_INVALID);
        Assert.isTrue(policy.invalidPairs.contains('Teleported>Draft'), 'Rows with unknown statuses are recorded as invalid.');
        // Valid rows are unaffected.
        Assert.areEqual(ShipmentStatusPolicy.Outcome.ALLOWED, decide(policy, 'Draft', 'Requested').outcome);
    }

    @IsTest
    static void blankTargetStatusRejected() {
        grant(true, true);
        assertRejected(decide(policy(standardRows()), 'Draft', null), ShipmentStatusPolicy.STATUS_REQUIRED);
        assertRejected(decide(policy(standardRows()), null, ' '), ShipmentStatusPolicy.STATUS_REQUIRED);
    }

    @IsTest
    static void unchangedStatusIsNoChange() {
        grant(false, false);
        Id shipmentId = TestDataFactory.fakeId(Shipment__c.SObjectType, 7);
        Shipment__c current = TestDataFactory.shipmentInMemory(shipmentId, 'Quoted', 0);
        Shipment__c previous = TestDataFactory.shipmentInMemory(shipmentId, 'Quoted', 0);

        List<ShipmentStatusPolicy.Decision> decisions = policy(standardRows())
            .evaluateStatusChanges(new List<Shipment__c>{ current }, new Map<Id, Shipment__c>{ shipmentId => previous });

        Assert.areEqual(ShipmentStatusPolicy.Outcome.NO_CHANGE, decisions[0].outcome);
        Assert.isFalse(decisions[0].requiresTrackingEvent());
        Assert.isFalse(decisions[0].isRejected());
        Assert.areEqual(shipmentId, decisions[0].shipmentId);
    }

    @IsTest
    static void itemGuardAppliesEvenUnderOverride() {
        grant(false, false);
        ShipmentStatusPolicy policy = policy(standardRows());
        assertRejected(decide(policy, 'Quoted', 'Confirmed', 0), ShipmentItemsRequiredGuard.ITEMS_REQUIRED);
        Assert.areEqual(ShipmentStatusPolicy.Outcome.ALLOWED, decide(policy, 'Quoted', 'Confirmed', 1).outcome);

        grant(true, false);
        ShipmentStatusPolicy.Decision overridden = decide(policy(standardRows()), 'Draft', 'Confirmed', 0);
        assertRejected(overridden, ShipmentItemsRequiredGuard.ITEMS_REQUIRED);
        Assert.isNull(overridden.overriddenReasonCode, 'A guard rejection clears the override details.');
    }

    @IsTest
    static void guardsReceiveOnlyAllowedChangesForTheirTargets() {
        grant(false, false);
        RecordingGuard guard = new RecordingGuard();
        ShipmentStatusPolicy policy = new ShipmentStatusPolicy(standardRows(), new List<ShipmentStatusGuard>{ guard, new SilentGuard() });
        List<ShipmentStatusPolicy.StatusChange> changes = new List<ShipmentStatusPolicy.StatusChange>{
            new ShipmentStatusPolicy.StatusChange(0, TestDataFactory.shipmentInMemory(null, 'Quoted', 1), 'Requested', 'Quoted'), // allowed, targeted
            new ShipmentStatusPolicy.StatusChange(1, TestDataFactory.shipmentInMemory(null, 'Quoted', 1), 'Draft', 'Quoted'), // rejected by table
            new ShipmentStatusPolicy.StatusChange(2, TestDataFactory.shipmentInMemory(null, 'Requested', 1), 'Draft', 'Requested') // allowed, not targeted
        };

        List<ShipmentStatusPolicy.Decision> decisions = policy.evaluate(changes);

        Assert.areEqual(new List<Integer>{ 0 }, guard.receivedIndexes);
        assertRejected(decisions[0], 'RECORDING_GUARD');
        assertRejected(decisions[1], ShipmentStatusPolicy.TRANSITION_NOT_ALLOWED);
        Assert.areEqual(ShipmentStatusPolicy.Outcome.ALLOWED, decisions[2].outcome);
    }

    @IsTest
    static void bulkEvaluationPreservesOrderAndIndexes() {
        grant(false, false);
        List<Shipment__c> records = new List<Shipment__c>();
        Map<Id, Shipment__c> oldById = new Map<Id, Shipment__c>();
        for (Integer i = 0; i < 200; i++) {
            Id shipmentId = TestDataFactory.fakeId(Shipment__c.SObjectType, i + 1);
            Boolean valid = Math.mod(i, 2) == 0;
            records.add(TestDataFactory.shipmentInMemory(shipmentId, valid ? 'Requested' : 'Delivered', 0));
            oldById.put(shipmentId, TestDataFactory.shipmentInMemory(shipmentId, 'Draft', 0));
        }

        List<ShipmentStatusPolicy.Decision> decisions = policy(standardRows()).evaluateStatusChanges(records, oldById);

        Assert.areEqual(200, decisions.size());
        for (Integer i = 0; i < 200; i++) {
            Assert.areEqual(i, decisions[i].index);
            Assert.areEqual(records[i].Id, decisions[i].shipmentId);
            Assert.areEqual(Math.mod(i, 2) == 0, decisions[i].isAllowed(), 'Decision ' + i);
        }
    }

    @IsTest
    static void deployedConfigurationLoadsWithoutErrors() {
        grant(false, false);
        ShipmentStatusPolicy policy = new ShipmentStatusPolicy();
        Assert.isTrue(policy.invalidPairs.isEmpty(), 'Deployed transitions must all be valid: ' + policy.invalidPairs);
        Assert.areEqual(ShipmentStatusPolicy.Outcome.ALLOWED, decide(policy, 'Draft', 'Requested').outcome);
    }

    private class RecordingGuard implements ShipmentStatusGuard {
        public List<Integer> receivedIndexes = new List<Integer>();

        public Set<String> targetStatuses() {
            return new Set<String>{ 'Quoted' };
        }

        public Map<Integer, ShipmentStatusPolicy.Violation> check(List<ShipmentStatusPolicy.StatusChange> changes) {
            Map<Integer, ShipmentStatusPolicy.Violation> violations = new Map<Integer, ShipmentStatusPolicy.Violation>();
            for (ShipmentStatusPolicy.StatusChange change : changes) {
                receivedIndexes.add(change.index);
                violations.put(change.index, new ShipmentStatusPolicy.Violation('RECORDING_GUARD', 'Recorded.'));
            }
            return violations;
        }
    }

    /** A guard with no targets is never called. */
    private class SilentGuard implements ShipmentStatusGuard {
        public Set<String> targetStatuses() {
            return new Set<String>();
        }

        public Map<Integer, ShipmentStatusPolicy.Violation> check(List<ShipmentStatusPolicy.StatusChange> changes) {
            throw new ELogixException('A guard without targets must not be called.');
        }
    }
}
