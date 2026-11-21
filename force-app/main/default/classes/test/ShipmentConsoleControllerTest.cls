/**
 * Phase 7: ShipmentConsoleController. Status options come from the real ShipmentStatusPolicy (decision
 * P5): only the trigger-only guard codes are treated as "validated on save"; every other rejection
 * hides the status; delivery statuses are never offered and refused on save. Saves still go through
 * ShipmentService and the Shipment__c trigger.
 */
@IsTest
private class ShipmentConsoleControllerTest {
  private static final String OPS = 'Console Ops Tester';
  private static final String OTHER_OPS = 'Console Other Ops Tester';
  private static final String NO_ROLE_OPS = 'Console No Role Ops Tester';
  private static final String SALES = 'Console Sales Tester';
  private static final String MANAGER = 'Console Manager Tester';

  @TestSetup
  static void setup() {
    Business_Unit__c businessUnit = TestDataFactory.createBusinessUnit(
      'BU-SCC'
    );
    TestDataFactory.createCustomer('CUST-SCC', businessUnit.Id);
    TestDataFactory.createUser(OPS, TestDataFactory.OPERATIONS);
    TestDataFactory.createUser(OTHER_OPS, TestDataFactory.OPERATIONS);
    TestDataFactory.createUserWithoutRole(
      NO_ROLE_OPS,
      TestDataFactory.OPERATIONS
    );
    TestDataFactory.createUser(SALES, TestDataFactory.SALES);
    TestDataFactory.createUser(MANAGER, TestDataFactory.LOGISTICS_MANAGER);
  }

  /** As the running user: Confirmed shipments with items. */
  private static List<Shipment__c> confirmed(Integer count) {
    Account customer = [
      SELECT Id, Business_Unit__c
      FROM Account
      WHERE Customer_Code__c = 'CUST-SCC'
    ];
    return TestDataFactory.confirmedShipments(
      count,
      customer.Id,
      customer.Business_Unit__c
    );
  }

  private static Map<String, ShipmentConsoleController.StatusOption> optionsOf(
    Id shipmentId
  ) {
    Map<String, ShipmentConsoleController.StatusOption> byValue = new Map<String, ShipmentConsoleController.StatusOption>();
    for (
      ShipmentConsoleController.StatusOption option : ShipmentConsoleController.getStatusOptions(
        shipmentId
      )
    ) {
      byValue.put(option.value, option);
    }
    return byValue;
  }

  private static String statusOf(Id shipmentId) {
    return [SELECT Status__c FROM Shipment__c WHERE Id = :shipmentId].Status__c;
  }

  /* ---------------- status options (P5) ---------------- */

  @IsTest
  static void optionsFollowThePolicyAndMarkSaveTimeGuards() {
    System.runAs(TestDataFactory.getUser(OPS)) {
      Shipment__c shipment = confirmed(1)[0];
      Map<String, ShipmentConsoleController.StatusOption> options = optionsOf(
        shipment.Id
      );

      ShipmentConsoleController.StatusOption ready = options.get(
        'Ready for Dispatch'
      );
      Assert.isNotNull(
        ready,
        'Rejected only by the allocation guard, which checks on save: offered. ' +
        options.keySet()
      );
      Assert.isTrue(ready.validatedOnSave);
      Assert.areEqual(Label.eLogix_Fleet_Allocation_Required, ready.note);

      ShipmentConsoleController.StatusOption hold = options.get('On Hold');
      Assert.isNotNull(hold, String.valueOf(options.keySet()));
      Assert.isFalse(hold.validatedOnSave);
      Assert.isFalse(hold.byOverride);

      Assert.isFalse(
        options.containsKey('Cancelled'),
        'PERMISSION_REQUIRED is never ignored.'
      );
      Assert.isFalse(
        options.containsKey('Draft'),
        'TRANSITION_NOT_ALLOWED is never ignored.'
      );
      Assert.isFalse(
        options.containsKey('Confirmed'),
        'The current status is not an option.'
      );
      for (String owned : ShipmentConsoleController.DELIVERY_OWNED) {
        Assert.isFalse(
          options.containsKey(owned),
          owned + ' belongs to the delivery actions.'
        );
      }
    }
  }

  @IsTest
  static void permissionHoldersSeeTheTransitionsTheyMayMake() {
    Shipment__c shipment;
    System.runAs(TestDataFactory.getUser(OPS)) {
      shipment = confirmed(1)[0];
    }
    System.runAs(TestDataFactory.getUser(MANAGER)) {
      ShipmentConsoleController.StatusOption cancel = optionsOf(shipment.Id)
        .get('Cancelled');
      Assert.isNotNull(
        cancel,
        'The Logistics Manager holds eLogix_Cancel_Confirmed_Shipment.'
      );
      Assert.isFalse(cancel.validatedOnSave);
      Assert.isFalse(cancel.byOverride);
    }
  }

  @IsTest
  static void terminalShipmentsOfferNoOptions() {
    System.runAs(TestDataFactory.getUser(OPS)) {
      Account customer = [
        SELECT Id, Business_Unit__c
        FROM Account
        WHERE Customer_Code__c = 'CUST-SCC'
      ];
      Shipment__c draft = TestDataFactory.buildShipment(
        customer.Id,
        customer.Business_Unit__c,
        'Draft'
      );
      insert draft;
      ServiceResult cancelled = ShipmentConsoleController.changeStatus(
        draft.Id,
        'Cancelled',
        'Customer withdrew the order.'
      );
      Assert.isTrue(cancelled.isSuccess, String.valueOf(cancelled.errors));

      Assert.isTrue(
        ShipmentConsoleController.getStatusOptions(draft.Id).isEmpty(),
        'TERMINAL_STATUS is never ignored.'
      );
    }
  }

  @IsTest
  static void shipmentsTheUserCannotSeeAreNotFound() {
    Shipment__c shipment;
    System.runAs(TestDataFactory.getUser(OPS)) {
      shipment = confirmed(1)[0];
    }
    System.runAs(TestDataFactory.getUser(NO_ROLE_OPS)) {
      try {
        ShipmentConsoleController.getStatusOptions(shipment.Id);
        Assert.fail('A roleless Operations user has no Shipment role sharing.');
      } catch (AuraHandledException e) {
        Assert.areEqual(
          String.format(
            Label.eLogix_Tracking_Shipment_Not_Found,
            new List<Object>{ shipment.Id }
          ),
          e.getMessage()
        );
      }
    }
  }

  /* ---------------- status changes ---------------- */

  @IsTest
  static void changeStatusDelegatesToTheServiceAndTrigger() {
    System.runAs(TestDataFactory.getUser(OPS)) {
      Shipment__c shipment = confirmed(1)[0];

      ServiceResult held = ShipmentConsoleController.changeStatus(
        shipment.Id,
        'On Hold',
        'Awaiting customs papers.'
      );
      Assert.isTrue(held.isSuccess, String.valueOf(held.errors));
      Shipment__c saved = [
        SELECT Status__c, Hold_Reason__c
        FROM Shipment__c
        WHERE Id = :shipment.Id
      ];
      Assert.areEqual('On Hold', saved.Status__c);
      Assert.areEqual('Awaiting customs papers.', saved.Hold_Reason__c);
      Assert.areEqual(
        1,
        [
          SELECT COUNT()
          FROM Tracking_Event__c
          WHERE Shipment__c = :shipment.Id AND To_Status__c = 'On Hold'
        ]
      );
    }
  }

  @IsTest
  static void saveTimeGuardsStillRejectOnSave() {
    System.runAs(TestDataFactory.getUser(OPS)) {
      Shipment__c shipment = confirmed(1)[0];
      ServiceResult result = ShipmentConsoleController.changeStatus(
        shipment.Id,
        'Ready for Dispatch',
        null
      );

      Assert.isFalse(
        result.isSuccess,
        'Offered as validated on save, and the trigger refuses it without an allocation.'
      );
      Assert.isTrue(String.isNotBlank(result.errors[0].message));
      Assert.areEqual('Confirmed', statusOf(shipment.Id));
      Assert.areEqual(
        0,
        [
          SELECT COUNT()
          FROM Tracking_Event__c
          WHERE
            Shipment__c = :shipment.Id
            AND To_Status__c = 'Ready for Dispatch'
        ]
      );
    }
  }

  @IsTest
  static void deliveryStatusesAreRefusedWithoutTouchingTheShipment() {
    System.runAs(TestDataFactory.getUser(MANAGER)) {
      Shipment__c shipment = confirmed(1)[0];
      for (
        String owned : new List<String>{
          'Out for Delivery',
          'Delivered',
          ' Failed Delivery '
        }
      ) {
        ServiceResult result = ShipmentConsoleController.changeStatus(
          shipment.Id,
          owned,
          null
        );
        Assert.isFalse(result.isSuccess);
        Assert.areEqual(
          ShipmentConsoleController.DELIVERY_ACTION_REQUIRED,
          result.errors[0].code
        );
        Assert.areEqual(shipment.Id, result.errors[0].recordId);
      }
      Assert.areEqual('Confirmed', statusOf(shipment.Id));
    }
  }

  @IsTest
  static void usersWithoutEditAccessCannotChangeStatus() {
    Shipment__c shipment;
    System.runAs(TestDataFactory.getUser(OPS)) {
      shipment = confirmed(1)[0];
    }
    System.runAs(TestDataFactory.getUser(SALES)) {
      ServiceResult result = ShipmentConsoleController.changeStatus(
        shipment.Id,
        'On Hold',
        'Not allowed.'
      );
      Assert.isFalse(
        result.isSuccess,
        'Sales Executives have read-only shipment access.'
      );
    }
    Assert.areEqual('Confirmed', statusOf(shipment.Id));
  }

  /* ---------------- list ---------------- */

  @IsTest
  static void listRespectsSharingAndFilters() {
    System.runAs(TestDataFactory.getUser(OPS)) {
      List<Shipment__c> mine = confirmed(2);
      ShipmentConsoleController.changeStatus(mine[0].Id, 'On Hold', 'Waiting.');

      Assert.areEqual(
        2,
        ShipmentConsoleController.getShipments(null, null, null).size()
      );
      List<Shipment__c> held = ShipmentConsoleController.getShipments(
        'On Hold',
        null,
        50
      );
      Assert.areEqual(1, held.size());
      Assert.areEqual(mine[0].Id, held[0].Id);
      Assert.areEqual(
        2,
        ShipmentConsoleController.getShipments('Not A Status', 'bangal', 500)
          .size(),
        'Unknown status ignored; search matches the destination.'
      );
      Assert.areEqual(
        0,
        ShipmentConsoleController.getShipments(null, 'Kolkata', 10).size()
      );
      Assert.areEqual(
        1,
        ShipmentConsoleController.getShipments(null, null, 1).size()
      );
    }
    System.runAs(TestDataFactory.getUser(OTHER_OPS)) {
      Assert.areEqual(
        2,
        ShipmentConsoleController.getShipments(null, null, null).size(),
        'Operations users share shipments through the approved role rule.'
      );
    }
    System.runAs(TestDataFactory.getUser(MANAGER)) {
      Assert.areEqual(
        2,
        ShipmentConsoleController.getShipments(null, null, null).size(),
        'View All.'
      );
    }
  }
}
