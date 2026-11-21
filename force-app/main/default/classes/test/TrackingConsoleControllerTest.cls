/**
 * Phase 7: TrackingConsoleController. Reads honour sharing; manual events go through
 * TrackingService.recordEvents and are always recorded with the Manual source.
 */
@IsTest
private class TrackingConsoleControllerTest {
  private static final String OPS = 'Tracking Console Ops Tester';
  private static final String OTHER_OPS = 'Tracking Console Other Ops Tester';
  private static final String FLEET = 'Tracking Console Fleet Tester';
  private static final String SALES = 'Tracking Console Sales Tester';

  @TestSetup
  static void setup() {
    Business_Unit__c businessUnit = TestDataFactory.createBusinessUnit(
      'BU-TCC'
    );
    Account customer = TestDataFactory.createCustomer(
      'CUST-TCC',
      businessUnit.Id
    );
    TestDataFactory.createUser(OPS, TestDataFactory.OPERATIONS);
    TestDataFactory.createUser(OTHER_OPS, TestDataFactory.OPERATIONS);
    TestDataFactory.createUser(FLEET, TestDataFactory.FLEET);
    TestDataFactory.createUser(SALES, TestDataFactory.SALES);

    // Shipment 0 goes In Transit; shipment 1 stays Confirmed.
    List<Shipment__c> shipments;
    System.runAs(TestDataFactory.getUser(OPS)) {
      shipments = TestDataFactory.confirmedShipments(
        2,
        customer.Id,
        businessUnit.Id
      );
      update new Shipment__c(
        Id = shipments[0].Id,
        Pickup_Date__c = Date.today()
      );
    }
    System.runAs(TestDataFactory.getUser(FLEET)) {
      Vehicle__c vehicle = TestDataFactory.buildVehicle(
        'TN-TCC-1',
        businessUnit.Id
      );
      Driver__c driver = TestDataFactory.buildDriver(
        'DL-TCC-1',
        businessUnit.Id
      );
      insert vehicle;
      insert driver;
      ServiceResult allocated = new FleetAllocationService()
        .allocate(
          new List<AllocationRequest>{
            new AllocationRequest(shipments[0].Id, vehicle.Id, driver.Id)
          }
        );
      Assert.isTrue(allocated.isSuccess, String.valueOf(allocated.errors));
    }
    System.runAs(TestDataFactory.getUser(OPS)) {
      TestDataFactory.advance(
        new List<Shipment__c>{ new Shipment__c(Id = shipments[0].Id) },
        new List<String>{ 'Ready for Dispatch', 'Dispatched', 'In Transit' }
      );
    }
  }

  private static Shipment__c shipmentIn(String status) {
    return [SELECT Id FROM Shipment__c WHERE Status__c = :status LIMIT 1];
  }

  @IsTest
  static void timelineListsTheShipmentHistoryNewestFirst() {
    Id shipmentId = shipmentIn('In Transit').Id;
    System.runAs(TestDataFactory.getUser(OPS)) {
      List<Tracking_Event__c> timeline = TrackingConsoleController.getTimeline(
        shipmentId
      );
      Assert.areEqual(
        [SELECT COUNT() FROM Tracking_Event__c WHERE Shipment__c = :shipmentId],
        timeline.size()
      );
      Assert.isTrue(
        timeline.size() >= 6,
        'Created through In Transit: ' + timeline.size()
      );
      for (Integer i = 1; i < timeline.size(); i++) {
        Assert.isTrue(
          timeline[i - 1].Event_Timestamp__c >= timeline[i].Event_Timestamp__c,
          'Newest first.'
        );
      }
    }
    System.runAs(TestDataFactory.getUser(OTHER_OPS)) {
      List<Tracking_Event__c> sharedTimeline = TrackingConsoleController.getTimeline(
        shipmentId
      );
      Assert.areEqual(
        [SELECT COUNT() FROM Tracking_Event__c WHERE Shipment__c = :shipmentId],
        sharedTimeline.size(),
        'Operations users share shipment history through the approved role rule.'
      );
    }
  }

  @IsTest
  static void activeShipmentsAreThoseOnTheRoad() {
    System.runAs(TestDataFactory.getUser(OPS)) {
      List<Shipment__c> active = TrackingConsoleController.getActiveShipments();
      Assert.areEqual(
        1,
        active.size(),
        'The Confirmed shipment is not on the road.'
      );
      Assert.areEqual('In Transit', active[0].Status__c);
      Assert.areEqual('TN-TCC-1', active[0].Vehicle__r.Vehicle_Number__c);
    }
    System.runAs(TestDataFactory.getUser(OTHER_OPS)) {
      List<Shipment__c> sharedActive = TrackingConsoleController.getActiveShipments();
      Assert.areEqual(
        1,
        sharedActive.size(),
        'Operations users share shipments through the approved role rule.'
      );
      Assert.areEqual('In Transit', sharedActive[0].Status__c);
    }
  }

  @IsTest
  static void manualEventsAreAlwaysRecordedAsManual() {
    Id shipmentId = shipmentIn('In Transit').Id;
    System.runAs(TestDataFactory.getUser(OPS)) {
      TrackingEventRequest request = new TrackingEventRequest(
        shipmentId,
        'Location Update',
        'Krishnagiri toll plaza'
      );
      request.source = 'GPS Integration'; // a spoofed source is replaced
      request.externalEventId = 'SPOOF-1';
      request.remarks = 'Driver called in.';
      request.eventTimestamp = System.now().addMinutes(2); // newer than the last status change, to the second
      ServiceResult result = TrackingConsoleController.recordEvent(request);
      Assert.isTrue(result.isSuccess, String.valueOf(result.errors));

      Tracking_Event__c event = [
        SELECT Source__c, Location__c, Event_Key__c
        FROM Tracking_Event__c
        WHERE Id = :result.recordIds[0]
      ];
      Assert.areEqual(TrackingService.SOURCE_MANUAL, event.Source__c);
      Assert.areEqual('Krishnagiri toll plaza', event.Location__c);
      Assert.isFalse(
        event.Event_Key__c != null && event.Event_Key__c.contains('SPOOF-1'),
        'No integration idempotency key from the UI.'
      );
      Assert.areEqual(
        'Krishnagiri toll plaza',
        [SELECT Latest_Location__c FROM Shipment__c WHERE Id = :shipmentId]
        .Latest_Location__c
      );
      Assert.areEqual(
        'In Transit',
        [SELECT Status__c FROM Shipment__c WHERE Id = :shipmentId].Status__c
      );
    }
  }

  @IsTest
  static void statusEventsAndUnauthorisedUsersAreRefused() {
    Id shipmentId = shipmentIn('In Transit').Id;
    System.runAs(TestDataFactory.getUser(OPS)) {
      ServiceResult statusEvent = TrackingConsoleController.recordEvent(
        new TrackingEventRequest(shipmentId, 'Delivered', 'Hosur')
      );
      Assert.isFalse(
        statusEvent.isSuccess,
        'Status events come only from status changes.'
      );
    }
    System.runAs(TestDataFactory.getUser(SALES)) {
      try {
        TrackingConsoleController.recordEvent(
          new TrackingEventRequest(shipmentId, 'Location Update', 'Hosur')
        );
        Assert.fail('Sales Executives cannot create tracking events.');
      } catch (AuraHandledException e) {
        Assert.areEqual(Label.eLogix_Access_Denied, e.getMessage());
      }
    }
    Assert.areEqual(
      0,
      [
        SELECT COUNT()
        FROM Tracking_Event__c
        WHERE Event_Type__c = 'Location Update'
      ]
    );
  }
}
