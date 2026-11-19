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

    /* ------------------------------------------------------------------ */
    /* Phase 3: pricing and quotation builders                             */
    /* ------------------------------------------------------------------ */

    public static final String CUSTOMER_SERVICE = 'eLogix_Customer_Service_Executive';
    public static final String APPROVE_QUOTATION_PERMISSION = 'eLogix_Approve_Quotation';

    /** Reference lane: Chennai to Bangalore, 350 km. */
    public static Route__c createRoute(String code, Decimal distanceKm) {
        Route__c route = new Route__c(
            Name = 'Chennai - Bangalore ' + code,
            Route_Code__c = code,
            Origin__c = 'Chennai',
            Destination__c = 'Bangalore',
            Distance__c = distanceKm,
            Estimated_Transit_Hours__c = 9,
            Status__c = 'Active'
        );
        insert route;
        return route;
    }

    /**
     * Reference LCV card used across the Phase 3 tests: base 2,000; 3.50 per kg; 12.00 per km;
     * fuel 10%; insurance 0.5% of declared value; no minimum; effective from 30 days ago, open-ended.
     * Not inserted, so tests can adjust it first.
     */
    public static Rate_Card__c buildRateCard(String code, String vehicleType) {
        return new Rate_Card__c(
            Name = 'Rate Card ' + code,
            Rate_Card_Code__c = code,
            Vehicle_Type__c = vehicleType,
            Base_Freight__c = 2000,
            Rate_Per_KG__c = 3.5,
            Rate_Per_KM__c = 12,
            Fuel_Surcharge_Percent__c = 10,
            Insurance_Percent__c = 0.5,
            Minimum_Freight__c = 0,
            Effective_From__c = Date.today().addDays(-30),
            Is_Active__c = true,
            Selection_Priority__c = 10
        );
    }

    /**
     * A quotable request on the reference lane: 500 kg, declared value 200,000, LCV, pickup in 3 days.
     * Not inserted.
     */
    public static Shipment_Request__c buildShipmentRequest(Id customerId, Id businessUnitId, Id routeId, String status) {
        return new Shipment_Request__c(
            Customer__c = customerId,
            Business_Unit__c = businessUnitId,
            Route__c = routeId,
            Origin__c = 'Chennai',
            Destination__c = 'Bangalore',
            Requested_Pickup_Date__c = Date.today().addDays(3),
            Expected_Delivery_Date__c = Date.today().addDays(5),
            Total_Weight__c = 500,
            Declared_Value__c = 200000,
            Requested_Vehicle_Type__c = 'LCV',
            Priority__c = 'Standard',
            Status__c = status
        );
    }

    public static List<Shipment_Request__c> buildShipmentRequests(Integer count, Id customerId, Id businessUnitId, Id routeId, String status) {
        List<Shipment_Request__c> requests = new List<Shipment_Request__c>();
        for (Integer i = 0; i < count; i++) {
            requests.add(buildShipmentRequest(customerId, businessUnitId, routeId, status));
        }
        return requests;
    }

    public static List<Id> idsOf(List<SObject> records) {
        List<Id> ids = new List<Id>();
        for (SObject record : records) {
            ids.add(record.Id);
        }
        return ids;
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
