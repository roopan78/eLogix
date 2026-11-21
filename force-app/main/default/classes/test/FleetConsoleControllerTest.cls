/**
 * Phase 7: FleetConsoleController. Candidate lists are a convenience filter; FleetAllocationService
 * remains the only path that allocates or releases, with its permission and object-access checks.
 */
@IsTest
private class FleetConsoleControllerTest {
    private static final String OPS = 'Fleet Console Ops Tester';
    private static final String FLEET = 'Fleet Console Fleet Tester';
    private static final String SALES = 'Fleet Console Sales Tester';

    @TestSetup
    static void setup() {
        Business_Unit__c businessUnit = TestDataFactory.createBusinessUnit('BU-FCC');
        TestDataFactory.createCustomer('CUST-FCC', businessUnit.Id);
        TestDataFactory.createUser(OPS, TestDataFactory.OPERATIONS);
        TestDataFactory.createUser(FLEET, TestDataFactory.FLEET);
        TestDataFactory.createUser(SALES, TestDataFactory.SALES);
        System.runAs(TestDataFactory.getUser(FLEET)) {
            Vehicle__c small = TestDataFactory.buildVehicle('TN-FCC-SMALL', businessUnit.Id);
            small.Capacity__c = 100;
            Vehicle__c inactive = TestDataFactory.buildVehicle('TN-FCC-OFF', businessUnit.Id);
            inactive.Status__c = 'Inactive';
            insert new List<Vehicle__c>{ TestDataFactory.buildVehicle('TN-FCC-1', businessUnit.Id), small, inactive };
            Driver__c away = TestDataFactory.buildDriver('DL-FCC-OFF', businessUnit.Id);
            away.Status__c = 'Inactive';
            insert new List<Driver__c>{ TestDataFactory.buildDriver('DL-FCC-1', businessUnit.Id), away };
        }
    }

    private static Shipment__c confirmedShipment() {
        Shipment__c shipment;
        System.runAs(TestDataFactory.getUser(OPS)) {
            Account customer = [SELECT Id, Business_Unit__c FROM Account WHERE Customer_Code__c = 'CUST-FCC'];
            shipment = TestDataFactory.confirmedShipments(1, customer.Id, customer.Business_Unit__c)[0];
        }
        return shipment;
    }

    private static AllocationRequest requestFor(Id shipmentId) {
        return new AllocationRequest(
            shipmentId,
            [SELECT Id FROM Vehicle__c WHERE Vehicle_Number__c = 'TN-FCC-1'].Id,
            [SELECT Id FROM Driver__c WHERE License_Number__c = 'DL-FCC-1'].Id
        );
    }

    @IsTest
    static void contextSuggestsOnlyAllocatableCandidatesWithCapacity() {
        Shipment__c shipment = confirmedShipment();
        System.runAs(TestDataFactory.getUser(FLEET)) {
            FleetConsoleController.AllocationContext context = FleetConsoleController.getAllocationContext(shipment.Id);
            Assert.areEqual(shipment.Id, context.shipment.Id);
            Assert.isNull(context.openAssignment);
            Assert.isTrue(context.canAllocate);
            Assert.isFalse(context.canCorrect, 'The Fleet Manager does not hold eLogix_Correct_Dispatched_Allocation.');
            Assert.areEqual(1, context.vehicles.size(), 'Too small and inactive vehicles are not suggested: ' + context.vehicles);
            Assert.areEqual('TN-FCC-1', context.vehicles[0].Vehicle_Number__c);
            Assert.areEqual(1, context.drivers.size(), String.valueOf(context.drivers));
            Assert.areEqual('DL-FCC-1', context.drivers[0].License_Number__c);
        }
    }

    @IsTest
    static void allocateAndReleaseGoThroughTheService() {
        Shipment__c shipment = confirmedShipment();
        System.runAs(TestDataFactory.getUser(FLEET)) {
            ServiceResult allocated = FleetConsoleController.allocate(requestFor(shipment.Id));
            Assert.isTrue(allocated.isSuccess, String.valueOf(allocated.errors));

            FleetConsoleController.AllocationContext context = FleetConsoleController.getAllocationContext(shipment.Id);
            Assert.areEqual('Planned', context.openAssignment.Status__c);
            Assert.areEqual('TN-FCC-1', context.openAssignment.Vehicle__r.Vehicle_Number__c);

            ServiceResult again = FleetConsoleController.allocate(requestFor(shipment.Id));
            Assert.isFalse(again.isSuccess, 'Allocation rules stay in the service.');
            Assert.isTrue(String.isNotBlank(again.errors[0].code) && String.isNotBlank(again.errors[0].message), String.valueOf(again.errors));
            Assert.areEqual(1, [SELECT COUNT() FROM Vehicle_Assignment__c WHERE Shipment__c = :shipment.Id]);

            ServiceResult released = FleetConsoleController.release(context.openAssignment.Id);
            Assert.isTrue(released.isSuccess, String.valueOf(released.errors));
        }
        Assert.areEqual('Cancelled', [SELECT Status__c FROM Vehicle_Assignment__c WHERE Shipment__c = :shipment.Id].Status__c);
    }

    @IsTest
    static void usersWithoutTheAllocatePermissionAreDenied() {
        Shipment__c shipment = confirmedShipment();
        AllocationRequest request = requestFor(shipment.Id);
        System.runAs(TestDataFactory.getUser(OPS)) {
            Assert.isFalse(FleetConsoleController.getAllocationContext(shipment.Id).canAllocate);
            for (Integer attempt = 0; attempt < 3; attempt++) {
                try {
                    if (attempt == 0) {
                        FleetConsoleController.allocate(request);
                    } else if (attempt == 1) {
                        FleetConsoleController.reallocate(request);
                    } else {
                        FleetConsoleController.correctDispatchedAllocation(request);
                    }
                    Assert.fail('Operations Executives cannot allocate (attempt ' + attempt + ').');
                } catch (AuraHandledException e) {
                    Assert.areEqual(Label.eLogix_Access_Denied, e.getMessage());
                }
            }
        }
        Assert.areEqual(0, [SELECT COUNT() FROM Vehicle_Assignment__c]);
    }

    @IsTest
    static void fleetBoardNeedsFleetObjectAccess() {
        System.runAs(TestDataFactory.getUser(FLEET)) {
            FleetConsoleController.FleetOverview overview = FleetConsoleController.getFleetOverview();
            Assert.areEqual(3, overview.vehicles.size());
            Assert.areEqual(2, overview.drivers.size());
        }
        System.runAs(TestDataFactory.getUser(SALES)) {
            try {
                FleetConsoleController.getFleetOverview();
                Assert.fail('Sales Executives have no vehicle or driver access.');
            } catch (AuraHandledException e) {
                Assert.isTrue(String.isNotBlank(e.getMessage()));
            }
        }
    }
}
