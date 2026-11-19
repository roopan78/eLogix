@IsTest
private class ServiceResultTest {
    @IsTest
    static void okCarriesRecordIdsAndNoErrors() {
        Id recordId = TestDataFactory.fakeId(Shipment__c.SObjectType, 1);
        ServiceResult result = ServiceResult.ok(new List<Id>{ recordId });

        Assert.isTrue(result.isSuccess);
        Assert.areEqual(new List<Id>{ recordId }, result.recordIds);
        Assert.isTrue(ServiceResult.ok(null).recordIds.isEmpty());
    }

    @IsTest
    static void errorsAreKeptPerRequestIndex() {
        Id first = TestDataFactory.fakeId(Shipment__c.SObjectType, 1);
        ServiceResult result = new ServiceResult()
            .addRecordId(first)
            .addRecordId(null)
            .addError('A', 'First problem.', 1, null)
            .addError('B', 'Second problem.', 2, first)
            .addError('C', 'Third problem.', 1, null);

        Assert.isFalse(result.isSuccess);
        Assert.areEqual(1, result.recordIds.size(), 'Null record ids are ignored.');
        Assert.areEqual(2, result.errorsFor(1).size());
        Assert.areEqual('C', result.errorsFor(1)[1].code);
        Assert.areEqual(first, result.errorsFor(2)[0].recordId);
        Assert.isTrue(result.errorsFor(0).isEmpty());
    }
}
