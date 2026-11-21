/**
 * Phase 9 record-level access regression. Requires the generated roles and owner-based sharing rules
 * to be deployed. Queries run in USER_MODE so both object permission and record sharing are applied.
 */
@IsTest
private class RoleSharingAccessTest {
  @IsTest
  static void salesOwnedRequestsAndQuotationsAreSharedToOperationsAndCustomerService() {
    User sales = roleUser(
      'Sales',
      'eLogix_Sales_Executive',
      'eLogix_Sales_Executive'
    );
    User operations = roleUser(
      'Operations',
      'eLogix_Operations_Executive',
      'eLogix_Operations_Executive'
    );
    User service = roleUser(
      'CustomerService',
      'eLogix_Customer_Service_Executive',
      'eLogix_Customer_Service_Executive'
    );
    Business_Unit__c unit = TestDataFactory.createBusinessUnit(
      'DEMO-ROLE-SHARE'
    );
    Account customer = TestDataFactory.createCustomer(
      'DEMO-ROLE-SHARE',
      unit.Id
    );
    Route__c route = TestDataFactory.createRoute('DEMO-ROLE-SHARE', 350);
    Rate_Card__c card = TestDataFactory.buildRateCard('DEMO-ROLE-SHARE', 'LCV');
    insert card;

    Id requestId;
    Id quotationId;
    System.runAs(sales) {
      Shipment_Request__c request = new Shipment_Request__c(
        Customer__c = customer.Id,
        Business_Unit__c = unit.Id,
        Route__c = route.Id,
        Origin__c = 'Chennai',
        Destination__c = 'Bangalore',
        Requested_Pickup_Date__c = Date.today().addDays(3),
        Expected_Delivery_Date__c = Date.today().addDays(5),
        Total_Weight__c = 500,
        Declared_Value__c = 200000,
        Requested_Vehicle_Type__c = 'LCV',
        Priority__c = 'Standard',
        Status__c = 'Submitted',
        Cargo_Description__c = 'DEMO-ROLE-SHARE'
      );
      insert request;
      requestId = request.Id;
      ServiceResult created = new QuotationService()
        .createFromRequests(new List<Id>{ request.Id });
      Assert.isTrue(
        created.isSuccess,
        'Sales should create a quotation from its request: ' + created.errors
      );
      quotationId = created.recordIds[0];
    }

    System.runAs(operations) {
      Assert.areEqual(
        1,
        [
          SELECT COUNT()
          FROM Shipment_Request__c
          WHERE Id = :requestId
          WITH USER_MODE
        ]
      );
      Assert.areEqual(
        1,
        [
          SELECT COUNT()
          FROM Quotation__c
          WHERE Id = :quotationId
          WITH USER_MODE
        ]
      );
      UserRecordAccess access = [
        SELECT RecordId, HasReadAccess, HasEditAccess
        FROM UserRecordAccess
        WHERE UserId = :operations.Id AND RecordId = :requestId
      ];
      Assert.isTrue(
        access.HasReadAccess,
        'Operations receives the Shipment Request read sharing rule.'
      );
      Assert.isFalse(
        access.HasEditAccess,
        'Read sharing must not grant request edits to Operations.'
      );
    }
    System.runAs(service) {
      Assert.areEqual(
        1,
        [
          SELECT COUNT()
          FROM Shipment_Request__c
          WHERE Id = :requestId
          WITH USER_MODE
        ]
      );
      Assert.areEqual(
        1,
        [
          SELECT COUNT()
          FROM Quotation__c
          WHERE Id = :quotationId
          WITH USER_MODE
        ]
      );
    }
  }

  @IsTest
  static void operationsOwnedShipmentIsSharedReadOnlyToFinance() {
    User operations = roleUser(
      'ShipmentOperations',
      'eLogix_Operations_Executive',
      'eLogix_Operations_Executive'
    );
    User finance = roleUser(
      'ShipmentFinance',
      'eLogix_Finance_Executive',
      'eLogix_Finance_Executive'
    );
    User warehouse = roleUser(
      'ShipmentWarehouse',
      'eLogix_Warehouse_Manager',
      'eLogix_Warehouse_Manager'
    );
    User service = roleUser(
      'ShipmentCustomerService',
      'eLogix_Customer_Service_Executive',
      'eLogix_Customer_Service_Executive'
    );
    User sales = roleUser(
      'ShipmentSales',
      'eLogix_Sales_Executive',
      'eLogix_Sales_Executive'
    );
    Business_Unit__c unit = TestDataFactory.createBusinessUnit(
      'DEMO-SHIP-SHARE'
    );
    Account customer = TestDataFactory.createCustomer(
      'DEMO-SHIP-SHARE',
      unit.Id
    );
    Route__c route = TestDataFactory.createRoute('DEMO-SHIP-SHARE', 350);

    Id shipmentId;
    System.runAs(operations) {
      Shipment__c shipment = TestDataFactory.buildShipment(
        customer.Id,
        unit.Id,
        'Draft'
      );
      shipment.Route__c = route.Id;
      insert shipment;
      shipmentId = shipment.Id;
    }
    System.runAs(finance) {
      Assert.areEqual(
        1,
        [SELECT COUNT() FROM Shipment__c WHERE Id = :shipmentId WITH USER_MODE]
      );
      UserRecordAccess access = [
        SELECT RecordId, HasReadAccess, HasEditAccess
        FROM UserRecordAccess
        WHERE UserId = :finance.Id AND RecordId = :shipmentId
      ];
      Assert.isTrue(
        access.HasReadAccess,
        'Finance receives the Shipment read sharing rule.'
      );
      Assert.isFalse(
        access.HasEditAccess,
        'Read sharing must not grant edit access to Finance.'
      );
    }
    System.runAs(warehouse) {
      Assert.areEqual(
        1,
        [SELECT COUNT() FROM Shipment__c WHERE Id = :shipmentId WITH USER_MODE]
      );
    }
    System.runAs(service) {
      Assert.areEqual(
        1,
        [SELECT COUNT() FROM Shipment__c WHERE Id = :shipmentId WITH USER_MODE]
      );
    }
    System.runAs(sales) {
      Assert.areEqual(
        0,
        [SELECT COUNT() FROM Shipment__c WHERE Id = :shipmentId WITH USER_MODE],
        'Sales has object read permission but no Shipment sharing rule.'
      );
    }
  }

  private static User roleUser(
    String lastName,
    String roleName,
    String permissionSetName
  ) {
    UserRole role = [
      SELECT Id
      FROM UserRole
      WHERE DeveloperName = :roleName
      LIMIT 1
    ];
    User user = TestDataFactory.createUser(lastName, permissionSetName);
    Assert.areEqual(
      role.Id,
      user.UserRoleId,
      'Test users must carry the matching eLogix role.'
    );
    return user;
  }
}
