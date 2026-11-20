/**
 * Phase 7: DeliveryConsoleController, the UI path for Out for Delivery, Delivered and Failed Delivery
 * (decision P5). Every action is DeliveryService's, including its access checks.
 */
@IsTest
private class DeliveryConsoleControllerTest {
    private static final String OPS = 'Delivery Console Ops Tester';
    private static final String FLEET = 'Delivery Console Fleet Tester';
    private static final String MANAGER = 'Delivery Console Manager Tester';
    private static final String SALES = 'Delivery Console Sales Tester';

    @TestSetup
    static void setup() {
        Business_Unit__c businessUnit = TestDataFactory.createBusinessUnit('BU-DCC');
        Account customer = TestDataFactory.createCustomer('CUST-DCC', businessUnit.Id);
        TestDataFactory.createUser(OPS, TestDataFactory.OPERATIONS);
        TestDataFactory.createUser(FLEET, TestDataFactory.FLEET);
        TestDataFactory.createUser(MANAGER, TestDataFactory.LOGISTICS_MANAGER);
        TestDataFactory.createUser(SALES, TestDataFactory.SALES);

        // Two shipments In Transit on Active trips (pickup today), owned by the Operations Executive.
        List<Shipment__c> shipments;
        System.runAs(TestDataFactory.getUser(OPS)) {
            shipments = TestDataFactory.confirmedShipments(2, customer.Id, businessUnit.Id);
            update new List<Shipment__c>{
                new Shipment__c(Id = shipments[0].Id, Pickup_Date__c = Date.today()),
                new Shipment__c(Id = shipments[1].Id, Pickup_Date__c = Date.today())
            };
        }
        System.runAs(TestDataFactory.getUser(FLEET)) {
            List<Vehicle__c> vehicles = new List<Vehicle__c>{
                TestDataFactory.buildVehicle('TN-DCC-1', businessUnit.Id),
                TestDataFactory.buildVehicle('TN-DCC-2', businessUnit.Id)
            };
            List<Driver__c> drivers = new List<Driver__c>{
                TestDataFactory.buildDriver('DL-DCC-1', businessUnit.Id),
                TestDataFactory.buildDriver('DL-DCC-2', businessUnit.Id)
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
    }

    private static List<Id> inTransit() {
        return new List<Id>(new Map<Id, Shipment__c>([SELECT Id FROM Shipment__c WHERE Status__c = 'In Transit' ORDER BY Name]).keySet());
    }

    private static String statusOf(Id shipmentId) {
        return [SELECT Status__c FROM Shipment__c WHERE Id = :shipmentId].Status__c;
    }

    @IsTest
    static void deliveryRunsThroughTheControllerToDeliveredAndVerified() {
        Id shipmentId = inTransit()[0];
        Id proofId;
        System.runAs(TestDataFactory.getUser(OPS)) {
            ServiceResult started = DeliveryConsoleController.startAttempt(shipmentId);
            Assert.isTrue(started.isSuccess, String.valueOf(started.errors));
            Assert.areEqual('Out for Delivery', statusOf(shipmentId));

            ProofOfDeliveryRequest proof = new ProofOfDeliveryRequest(shipmentId, 'Ms Lakshmi, stores');
            proof.deliveryNotes = 'Two crates, seals intact.';
            ServiceResult recorded = DeliveryConsoleController.recordProof(proof);
            Assert.isTrue(recorded.isSuccess, String.valueOf(recorded.errors));
            proofId = recorded.recordIds[0];
            TestDataFactory.attachEvidence(proofId);

            ServiceResult confirmed = DeliveryConsoleController.confirmDelivery(shipmentId);
            Assert.isTrue(confirmed.isSuccess, String.valueOf(confirmed.errors));
            Assert.areEqual('Delivered', statusOf(shipmentId));

            DeliveryConsoleController.DeliveryState state = DeliveryConsoleController.getDeliveryState(shipmentId);
            Assert.areEqual(1, state.attempts.size());
            Assert.areEqual('Delivered', state.attempts[0].Delivery_Status__c);
            Assert.areEqual(1, state.proofs.size());
            Assert.areEqual(proofId, state.proofs[0].Id);

            try {
                DeliveryConsoleController.verifyProof(proofId);
                Assert.fail('Only the Logistics Manager verifies proofs.');
            } catch (AuraHandledException e) {
                Assert.areEqual(Label.eLogix_Access_Denied, e.getMessage());
            }
        }

        update new Shipment__c(
            Id = shipmentId,
            OwnerId = TestDataFactory.getUser(MANAGER).Id
        );
        
        System.runAs(TestDataFactory.getUser(MANAGER)) {
            ServiceResult verified = DeliveryConsoleController.verifyProof(proofId);
            Assert.isTrue(verified.isSuccess, String.valueOf(verified.errors));
        }
        Assert.isNotNull([SELECT Verified_By__c FROM Proof_of_Delivery__c WHERE Id = :proofId].Verified_By__c);
    }

    @IsTest
    static void failedAttemptsAreRecordedThroughTheService() {
        Id shipmentId = inTransit()[1];
        System.runAs(TestDataFactory.getUser(OPS)) {
            DeliveryConsoleController.startAttempt(shipmentId);
            ServiceResult noReason = DeliveryConsoleController.recordFailure(new DeliveryFailureRequest(shipmentId, null));
            Assert.isFalse(noReason.isSuccess, 'The service requires a failure reason.');

            DeliveryFailureRequest failure = new DeliveryFailureRequest(shipmentId, 'Consignee Unavailable');
            failure.notes = 'Gate closed after 6 pm.';
            ServiceResult failed = DeliveryConsoleController.recordFailure(failure);
            Assert.isTrue(failed.isSuccess, String.valueOf(failed.errors));
            Assert.areEqual('Failed Delivery', statusOf(shipmentId));
            Assert.areEqual('Failed', DeliveryConsoleController.getDeliveryState(shipmentId).attempts[0].Delivery_Status__c);
        }
    }

    @IsTest
    static void usersWithoutDeliveryAccessAreDenied() {
        Id shipmentId = inTransit()[0];
        System.runAs(TestDataFactory.getUser(SALES)) {
            try {
                DeliveryConsoleController.startAttempt(shipmentId);
                Assert.fail('Sales Executives have no delivery access.');
            } catch (AuraHandledException e) {
                Assert.areEqual(Label.eLogix_Access_Denied, e.getMessage());
            }
            try {
                DeliveryConsoleController.getDeliveryState(shipmentId);
                Assert.fail('Sales Executives cannot read delivery attempts.');
            } catch (AuraHandledException e) {
                Assert.isTrue(String.isNotBlank(e.getMessage()));
            }
        }
        Assert.areEqual(0, [SELECT COUNT() FROM Delivery__c]);
        Assert.areEqual('In Transit', statusOf(shipmentId));
    }
}
