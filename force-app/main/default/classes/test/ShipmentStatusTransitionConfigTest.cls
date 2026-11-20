/**
 * Integrity of the deployed Shipment_Status_Transition__mdt records. These tests read the real
 * configuration, so a bad metadata edit fails the next deployment instead of reaching users.
 */
@IsTest
private class ShipmentStatusTransitionConfigTest {
    private static List<Shipment_Status_Transition__mdt> activeRows() {
        List<Shipment_Status_Transition__mdt> rows = new List<Shipment_Status_Transition__mdt>();
        for (Shipment_Status_Transition__mdt row : Shipment_Status_Transition__mdt.getAll().values()) {
            if (row.Is_Active__c) {
                rows.add(row);
            }
        }
        return rows;
    }

    @IsTest
    static void everyActiveRowUsesValidValues() {
        Set<String> statuses = ShipmentStatusPolicy.validStatuses();
        Set<String> eventTypes = ShipmentStatusPolicy.validTrackingEventTypes();
        Set<String> customPermissions = new Set<String>();
        for (CustomPermission permission : [SELECT DeveloperName FROM CustomPermission]) {
            customPermissions.add(permission.DeveloperName);
        }

        List<Shipment_Status_Transition__mdt> rows = activeRows();
        Assert.isFalse(rows.isEmpty(), 'Status transitions must be deployed.');
        for (Shipment_Status_Transition__mdt row : rows) {
            String name = row.DeveloperName;
            Assert.isTrue(statuses.contains(row.To_Status__c), name + ': unknown To_Status__c');
            Assert.isTrue(String.isBlank(row.From_Status__c) || statuses.contains(row.From_Status__c), name + ': unknown From_Status__c');
            String eventType = String.isBlank(row.Tracking_Event_Type__c) ? row.To_Status__c : row.Tracking_Event_Type__c;
            Assert.isTrue(eventTypes.contains(eventType), name + ': unknown tracking event type');
            Assert.isTrue(
                String.isBlank(row.Required_Permission__c) || customPermissions.contains(row.Required_Permission__c),
                name + ': unknown custom permission'
            );
        }
    }

    @IsTest
    static void noActiveRowBreaksAHardRule() {
        for (Shipment_Status_Transition__mdt row : activeRows()) {
            Assert.isFalse(ShipmentStatusPolicy.TERMINAL_STATUSES.contains(row.From_Status__c), row.DeveloperName + ' leaves a final status.');
            Assert.isFalse(
                row.From_Status__c == ShipmentStatusPolicy.DELIVERED && ShipmentStatusPolicy.PRE_DELIVERY_STATUSES.contains(row.To_Status__c),
                row.DeveloperName + ' reverses a delivery.'
            );
        }
    }

    @IsTest
    static void everyStatusIsReachableAndEveryOpenStatusHasAnExit() {
        Map<String, Set<String>> targetsByFrom = new Map<String, Set<String>>();
        Set<String> reached = new Set<String>();
        for (Shipment_Status_Transition__mdt row : activeRows()) {
            if (String.isBlank(row.From_Status__c)) {
                reached.add(row.To_Status__c);
                continue;
            }
            if (!targetsByFrom.containsKey(row.From_Status__c)) {
                targetsByFrom.put(row.From_Status__c, new Set<String>());
            }
            targetsByFrom.get(row.From_Status__c).add(row.To_Status__c);
        }
        Assert.isFalse(reached.isEmpty(), 'At least one initial status must be configured.');

        List<String> queue = new List<String>(reached);
        while (!queue.isEmpty()) {
            String status = queue.remove(0);
            if (targetsByFrom.containsKey(status)) {
                for (String target : targetsByFrom.get(status)) {
                    if (reached.add(target)) {
                        queue.add(target);
                    }
                }
            }
        }

        for (String status : ShipmentStatusPolicy.validStatuses()) {
            Assert.isTrue(reached.contains(status), status + ' cannot be reached from any initial status.');
            if (!ShipmentStatusPolicy.TERMINAL_STATUSES.contains(status)) {
                Assert.isTrue(targetsByFrom.containsKey(status), status + ' has no outgoing transition.');
            }
        }
    }

    @IsTest
    static void deployedLifecycleBehavesAsDocumented() {
        PermissionService.testOverrides.put(ShipmentStatusPolicy.OVERRIDE_PERMISSION, false);
        PermissionService.testOverrides.put(TestDataFactory.CANCEL_PERMISSION, false);
        // The deployed transitions with the item guard only. The Phase 4 allocation guard needs a
        // persisted assignment, which in-memory records cannot have; FleetAllocationServiceTest walks
        // the same path with real records. Here we only prove the default guard set includes it.
        Boolean allocationGuarded = false;
        for (ShipmentStatusGuard guard : ShipmentStatusPolicy.defaultGuards()) {
            allocationGuarded |= guard instanceof ShipmentAllocationGuard;
        }
        Assert.isTrue(allocationGuarded, 'Ready for Dispatch must be guarded by the fleet allocation check (Phase 4, Q10).');
        ShipmentStatusPolicy policy = new ShipmentStatusPolicy(
            Shipment_Status_Transition__mdt.getAll().values(),
            new List<ShipmentStatusGuard>{ new ShipmentItemsRequiredGuard() }
        );
        List<String> path = new List<String>{
            'Draft',
            'Requested',
            'Quoted',
            'Confirmed',
            'Ready for Dispatch',
            'Dispatched',
            'In Transit',
            'Out for Delivery',
            'Delivered',
            'Closed'
        };
        List<ShipmentStatusPolicy.StatusChange> changes = new List<ShipmentStatusPolicy.StatusChange>();
        changes.add(new ShipmentStatusPolicy.StatusChange(0, TestDataFactory.shipmentInMemory(null, 'Draft', 1), null, 'Draft'));
        for (Integer i = 1; i < path.size(); i++) {
            changes.add(new ShipmentStatusPolicy.StatusChange(i, TestDataFactory.shipmentInMemory(null, path[i], 1), path[i - 1], path[i]));
        }
        for (ShipmentStatusPolicy.Decision decision : policy.evaluate(changes)) {
            Assert.areEqual(ShipmentStatusPolicy.Outcome.ALLOWED, decision.outcome, decision.fromStatus + ' -> ' + decision.toStatus + ': ' + decision.message);
        }

        List<ShipmentStatusPolicy.Decision> gated = policy.evaluate(
            new List<ShipmentStatusPolicy.StatusChange>{
                new ShipmentStatusPolicy.StatusChange(0, TestDataFactory.shipmentInMemory(null, 'Cancelled', 1), 'Confirmed', 'Cancelled'),
                new ShipmentStatusPolicy.StatusChange(1, TestDataFactory.shipmentInMemory(null, 'Cancelled', 1), 'Draft', 'Cancelled')
            }
        );
        Assert.areEqual(ShipmentStatusPolicy.PERMISSION_REQUIRED, gated[0].reasonCode, 'Cancelling after confirmation needs a permission.');
        Assert.areEqual(ShipmentStatusPolicy.Outcome.ALLOWED, gated[1].outcome, 'Cancelling a draft is free.');
    }
}
