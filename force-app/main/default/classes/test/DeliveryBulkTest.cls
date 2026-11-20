/**
 * Phase 5 bulk: 200 shipments through attempt, proof, evidence and confirmation in single calls, with
 * query and DML counts independent of the batch size. The 200 in-transit shipments are built in
 * @TestSetup, which has its own governor limits.
 */
@IsTest
private class DeliveryBulkTest {
    private static final String OPS = 'Bulk Delivery Ops';
    private static final String FLEET = 'Bulk Delivery Fleet';
    private static final Integer SIZE = 200;

    @TestSetup
    static void setup() {
        Business_Unit__c businessUnit = TestDataFactory.createBusinessUnit('BU-DB');
        Account customer = TestDataFactory.createCustomer('CUST-DB', businessUnit.Id);
        User ops = TestDataFactory.createUser(OPS, TestDataFactory.OPERATIONS);
        User fleet = TestDataFactory.createUser(FLEET, TestDataFactory.FLEET);
        List<Shipment__c> shipments;
        System.runAs(ops) {
            shipments = TestDataFactory.confirmedShipments(SIZE, customer.Id, businessUnit.Id);
            for (Shipment__c shipment : shipments) {
                shipment.Pickup_Date__c = Date.today();
            }
            update shipments;
        }
        List<Vehicle__c> vehicles = new List<Vehicle__c>();
        List<Driver__c> drivers = new List<Driver__c>();
        for (Integer i = 0; i < SIZE; i++) {
            vehicles.add(TestDataFactory.buildVehicle('TN-DB-' + i, businessUnit.Id));
            drivers.add(TestDataFactory.buildDriver('DL-DB-' + i, businessUnit.Id));
        }
        System.runAs(fleet) {
            insert vehicles;
            insert drivers;
            List<AllocationRequest> requests = new List<AllocationRequest>();
            for (Integer i = 0; i < SIZE; i++) {
                requests.add(new AllocationRequest(shipments[i].Id, vehicles[i].Id, drivers[i].Id));
            }
            Assert.isTrue(new FleetAllocationService().allocate(requests).isSuccess);
        }
        System.runAs(ops) {
            List<Shipment__c> moves = new List<Shipment__c>();
            for (Shipment__c shipment : shipments) {
                moves.add(new Shipment__c(Id = shipment.Id));
            }
            TestDataFactory.advance(moves, new List<String>{ 'Ready for Dispatch', 'Dispatched', 'In Transit' });
        }
    }

    @IsTest
    static void twoHundredDeliveriesInSingleCalls() {
        List<Id> shipmentIds = new List<Id>(new Map<Id, Shipment__c>([SELECT Id FROM Shipment__c]).keySet());
        Assert.areEqual(SIZE, shipmentIds.size());
        Map<String, Integer> queries = new Map<String, Integer>();
        Map<String, Integer> statements = new Map<String, Integer>();

        System.runAs(TestDataFactory.getUser(OPS)) {
            Test.startTest();
            DeliveryService service = new DeliveryService();

            Integer q = Limits.getQueries();
            Integer d = Limits.getDmlStatements();
            ServiceResult started = service.startAttempts(shipmentIds);
            queries.put('start', Limits.getQueries() - q);
            statements.put('start', Limits.getDmlStatements() - d);
            Assert.isTrue(started.isSuccess, String.valueOf(started.errors));

            List<ProofOfDeliveryRequest> proofs = new List<ProofOfDeliveryRequest>();
            for (Id shipmentId : shipmentIds) {
                proofs.add(new ProofOfDeliveryRequest(shipmentId, 'Dock receiver'));
            }
            q = Limits.getQueries();
            d = Limits.getDmlStatements();
            ServiceResult recorded = service.recordProofs(proofs);
            queries.put('proof', Limits.getQueries() - q);
            statements.put('proof', Limits.getDmlStatements() - d);
            Assert.isTrue(recorded.isSuccess, String.valueOf(recorded.errors));

            List<ContentVersion> evidence = new List<ContentVersion>();
            for (Id proofId : recorded.recordIds) {
                evidence.add(new ContentVersion(Title = 'Photo', PathOnClient = 'photo.jpg', VersionData = Blob.valueOf('x'), FirstPublishLocationId = proofId));
            }
            insert evidence;

            q = Limits.getQueries();
            d = Limits.getDmlStatements();
            ServiceResult confirmed = service.confirmDeliveries(shipmentIds);
            queries.put('confirm', Limits.getQueries() - q);
            statements.put('confirm', Limits.getDmlStatements() - d);
            Assert.isTrue(confirmed.isSuccess, String.valueOf(confirmed.errors));
            Test.stopTest();
        }

        // Bounded by the number of steps, not by the 200 records (no SOQL or DML per record).
        for (String operation : queries.keySet()) {
            Assert.isTrue(queries.get(operation) <= 15, operation + ' queries: ' + queries.get(operation));
            Assert.isTrue(statements.get(operation) <= 10, operation + ' DML statements: ' + statements.get(operation));
        }
        System.debug(LoggingLevel.INFO, 'Phase 5 bulk 200: queries=' + queries + ' dml=' + statements);
        Assert.areEqual(SIZE, [SELECT COUNT() FROM Shipment__c WHERE Status__c = 'Delivered']);
        Assert.areEqual(SIZE, [SELECT COUNT() FROM Delivery__c WHERE Delivery_Status__c = 'Delivered' AND Attempt_Number__c = 1]);
        Assert.areEqual(SIZE, [SELECT COUNT() FROM Vehicle_Assignment__c WHERE Status__c = 'Completed']);
        Assert.areEqual(SIZE, [SELECT COUNT() FROM Tracking_Event__c WHERE To_Status__c = 'Delivered']);
    }
}
