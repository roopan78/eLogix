@IsTest
private class ShipmentItemsRequiredGuardTest {
    private static ShipmentStatusPolicy.StatusChange change(Integer index, Integer itemCount) {
        return new ShipmentStatusPolicy.StatusChange(index, TestDataFactory.shipmentInMemory(null, 'Confirmed', itemCount), 'Quoted', 'Confirmed');
    }

    @IsTest
    static void targetsConfirmedOnly() {
        Assert.areEqual(new Set<String>{ 'Confirmed' }, new ShipmentItemsRequiredGuard().targetStatuses());
    }

    @IsTest
    static void rejectsShipmentsWithoutItems() {
        Map<Integer, ShipmentStatusPolicy.Violation> violations = new ShipmentItemsRequiredGuard()
            .check(new List<ShipmentStatusPolicy.StatusChange>{ change(0, 0), change(1, null), change(2, 1), change(3, 3) });

        Assert.areEqual(new Set<Integer>{ 0, 1 }, violations.keySet());
        Assert.areEqual(ShipmentItemsRequiredGuard.ITEMS_REQUIRED, violations.get(0).code);
        Assert.areEqual(Label.eLogix_Shipment_Items_Required, violations.get(1).message);
    }

    @IsTest
    static void missingRecordCountsAsNoItems() {
        ShipmentStatusPolicy.StatusChange withoutRecord = new ShipmentStatusPolicy.StatusChange(5, null, 'Quoted', 'Confirmed');
        Map<Integer, ShipmentStatusPolicy.Violation> violations = new ShipmentItemsRequiredGuard()
            .check(new List<ShipmentStatusPolicy.StatusChange>{ withoutRecord });
        Assert.isTrue(violations.containsKey(5));
    }
}
