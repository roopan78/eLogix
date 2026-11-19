@IsTest
private class PermissionServiceTest {
    private static final String OPS = 'Permission Ops Tester';
    private static final String MANAGER = 'Permission Manager Tester';

    @TestSetup
    static void setup() {
        TestDataFactory.createUser(OPS, TestDataFactory.OPERATIONS);
        TestDataFactory.createUser(MANAGER, TestDataFactory.LOGISTICS_MANAGER);
    }

    @IsTest
    static void reflectsRealPermissionSetAssignments() {
        System.runAs(TestDataFactory.getUser(OPS)) {
            Assert.isFalse(PermissionService.hasPermission(TestDataFactory.CANCEL_PERMISSION));
            Assert.isFalse(PermissionService.hasPermission(ShipmentStatusPolicy.OVERRIDE_PERMISSION));
        }
        System.runAs(TestDataFactory.getUser(MANAGER)) {
            Assert.isTrue(PermissionService.hasPermission(TestDataFactory.CANCEL_PERMISSION));
            Assert.isTrue(PermissionService.hasPermission(' ' + ShipmentStatusPolicy.OVERRIDE_PERMISSION + ' '), 'Names are trimmed.');
        }
    }

    @IsTest
    static void blankOrUnknownNamesAreFalse() {
        Assert.isFalse(PermissionService.hasPermission(null));
        Assert.isFalse(PermissionService.hasPermission(''));
        Assert.isFalse(PermissionService.hasPermission('eLogix_Not_A_Real_Permission'));
    }

    @IsTest
    static void testOverridesTakePrecedence() {
        System.runAs(TestDataFactory.getUser(MANAGER)) {
            PermissionService.testOverrides.put(TestDataFactory.CANCEL_PERMISSION, false);
            Assert.isFalse(PermissionService.hasPermission(TestDataFactory.CANCEL_PERMISSION));
        }
    }
}
