/**
 * Test data for eLogix Apex tests. Builds records that satisfy the deployed validation rules, and
 * role users on the Standard Platform User profile (the org has free Salesforce Platform licenses
 * but few full Salesforce licenses).
 *
 * System.runAs enforces sharing but not CRUD or FLS on plain DML. Tests that need CRUD and FLS go
 * through services that use user-mode operations or describe checks.
 */
@IsTest
public class TestDataFactory {
    public static final String OPERATIONS = 'eLogix_Operations_Executive';
    public static final String LOGISTICS_MANAGER = 'eLogix_Logistics_Manager';
    public static final String SALES = 'eLogix_Sales_Executive';
    /** Holds only eLogix_Bypass_Validation_Rules. Used to create records that break a validation rule, as legacy data can. */
    public static final String DATA_MIGRATION = 'eLogix_Data_Migration';
    public static final String TEST_USER_DOMAIN = '@test.elogix.example';
    public static final String CANCEL_PERMISSION = 'eLogix_Cancel_Confirmed_Shipment';

    public static Business_Unit__c createBusinessUnit(String code) {
        Business_Unit__c businessUnit = new Business_Unit__c(
            Name = 'Test Business Unit ' + code,
            Business_Unit_Code__c = code,
            Region__c = 'South',
            Is_Active__c = true
        );
        insert businessUnit;
        return businessUnit;
    }

    public static Account createCustomer(String code, Id businessUnitId) {
        Account customer = new Account(
            Name = 'Test Customer ' + code,
            Customer_Code__c = code,
            BillingStreet = '12 Anna Salai',
            BillingCity = 'Chennai',
            BillingPostalCode = '600002',
            Phone = '+91 44 2345 6789',
            Is_Active_Customer__c = true,
            Business_Unit__c = businessUnitId
        );
        insert customer;
        return customer;
    }

    /** A valid Chennai to Bangalore shipment, not inserted. */
    public static Shipment__c buildShipment(Id customerId, Id businessUnitId, String status) {
        return new Shipment__c(
            Customer__c = customerId,
            Business_Unit__c = businessUnitId,
            Origin__c = 'Chennai',
            Destination__c = 'Bangalore',
            Weight__c = 500,
            Distance__c = 350,
            Pickup_Date__c = Date.today().addDays(1),
            Expected_Delivery_Date__c = Date.today().addDays(3),
            Priority__c = 'Standard',
            Status__c = status
        );
    }

    public static List<Shipment__c> buildShipments(Integer count, Id customerId, Id businessUnitId, String status) {
        List<Shipment__c> shipments = new List<Shipment__c>();
        for (Integer i = 0; i < count; i++) {
            shipments.add(buildShipment(customerId, businessUnitId, status));
        }
        return shipments;
    }

    /** One item per shipment, not inserted. */
    public static List<Shipment_Item__c> buildItems(List<Shipment__c> shipments) {
        List<Shipment_Item__c> items = new List<Shipment_Item__c>();
        for (Shipment__c shipment : shipments) {
            items.add(
                new Shipment_Item__c(
                    Shipment__c = shipment.Id,
                    Item_Name__c = 'Industrial pump',
                    SKU__c = 'SKU-PUMP-01',
                    Quantity__c = 2,
                    Weight__c = 50,
                    Declared_Value__c = 10000,
                    Package_Type__c = 'Crate'
                )
            );
        }
        return items;
    }

    /** A Standard Platform User with the given eLogix permission sets, inserted without mixed-DML errors. */
    public static User createUser(String lastName, List<String> permissionSetNames) {
        Profile platformProfile = [SELECT Id FROM Profile WHERE Name = 'Standard Platform User' LIMIT 1];
        String unique = EncodingUtil.convertToHex(Crypto.generateAesKey(128)).left(12);
        User user = new User(
            ProfileId = platformProfile.Id,
            FirstName = 'eLogix',
            LastName = lastName,
            Alias = ('el' + unique).left(8),
            Email = 'elogix.tester@example.com',
            Username = 'elogix.' + unique + TEST_USER_DOMAIN,
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_IN',
            TimeZoneSidKey = 'Asia/Kolkata'
        );
        System.runAs(new User(Id = UserInfo.getUserId())) {
            insert user;
            List<PermissionSet> permissionSets = [SELECT Id FROM PermissionSet WHERE Name IN :permissionSetNames];
            Assert.areEqual(permissionSetNames.size(), permissionSets.size(), 'Every requested permission set must exist in the org.');
            List<PermissionSetAssignment> assignments = new List<PermissionSetAssignment>();
            for (PermissionSet permissionSet : permissionSets) {
                assignments.add(new PermissionSetAssignment(AssigneeId = user.Id, PermissionSetId = permissionSet.Id));
            }
            insert assignments;
        }
        return user;
    }

    public static User createUser(String lastName, String permissionSetName) {
        return createUser(lastName, new List<String>{ permissionSetName });
    }

    /** A user created earlier in the test (for example in @TestSetup), found by last name. */
    public static User getUser(String lastName) {
        return [SELECT Id FROM User WHERE LastName = :lastName AND Username LIKE :('%' + TEST_USER_DOMAIN) LIMIT 1];
    }

    /**
     * An in-memory shipment, which can carry read-only fields such as the Item_Count__c roll-up.
     * For pure unit tests of the policy and guards.
     */
    public static Shipment__c shipmentInMemory(Id shipmentId, String status, Integer itemCount) {
        Map<String, Object> fields = new Map<String, Object>{
            'attributes' => new Map<String, Object>{ 'type' => 'Shipment__c' },
            'Status__c' => status,
            'Item_Count__c' => itemCount
        };
        if (shipmentId != null) {
            fields.put('Id', shipmentId);
        }
        return (Shipment__c) JSON.deserialize(JSON.serialize(fields), Shipment__c.class);
    }

    /** A syntactically valid, never-persisted record Id. */
    public static Id fakeId(Schema.SObjectType type, Integer sequence) {
        String suffix = String.valueOf(sequence);
        return Id.valueOf(type.getDescribe().getKeyPrefix() + '0'.repeat(12 - suffix.length()) + suffix);
    }

    /** Runs the next shipment updates through allowed transitions, one DML per step. */
    public static void advance(List<Shipment__c> shipments, List<String> statuses) {
        for (String status : statuses) {
            for (Shipment__c shipment : shipments) {
                shipment.Status__c = status;
            }
            update shipments;
        }
    }
}
