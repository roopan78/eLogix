// Deletes only deterministic DEMO- seed records. Remove dependent rows first; never use broad deletes.
Set<Id> customerIds = new Map<Id, Account>([
    SELECT Id FROM Account WHERE Customer_Code__c LIKE 'DEMO-CUST-%'
]).keySet();
List<Shipment_Request__c> demoRequests = new List<Shipment_Request__c>();
if (!customerIds.isEmpty()) {
    for (Shipment_Request__c request : [SELECT Id, Cargo_Description__c FROM Shipment_Request__c WHERE Customer__c IN :customerIds]) {
        if (request.Cargo_Description__c != null && request.Cargo_Description__c.startsWith('DEMO-REQ-')) demoRequests.add(request);
    }
}
Set<Id> requestIds = new Map<Id, Shipment_Request__c>(demoRequests).keySet();
List<Shipment__c> demoShipments = requestIds.isEmpty()
    ? new List<Shipment__c>()
    : [SELECT Id FROM Shipment__c WHERE Shipment_Request__c IN :requestIds];
Set<Id> shipmentIds = new Map<Id, Shipment__c>(demoShipments).keySet();
if (!shipmentIds.isEmpty()) {
    delete [SELECT Id FROM Shipment_Item__c WHERE Shipment__c IN :shipmentIds];
    delete demoShipments;
}

if (!requestIds.isEmpty()) {
    List<Quotation__c> demoQuotations = [SELECT Id FROM Quotation__c WHERE Shipment_Request__c IN :requestIds];
    Set<Id> quotationIds = new Map<Id, Quotation__c>(demoQuotations).keySet();
    if (!quotationIds.isEmpty()) {
        delete [SELECT Id FROM Quotation_Line__c WHERE Quotation__c IN :quotationIds];
        delete demoQuotations;
    }
    delete demoRequests;
}

delete [SELECT Id FROM Rate_Card__c WHERE Rate_Card_Code__c LIKE 'DEMO-%'];
delete [SELECT Id FROM Route__c WHERE Route_Code__c LIKE 'DEMO-%'];
delete [SELECT Id FROM Vehicle__c WHERE Vehicle_Number__c LIKE 'DEMO-%'];
delete [SELECT Id FROM Driver__c WHERE License_Number__c LIKE 'DEMO-%'];
delete [SELECT Id FROM Account WHERE Customer_Code__c LIKE 'DEMO-%'];
delete [SELECT Id FROM Business_Unit__c WHERE Business_Unit_Code__c LIKE 'DEMO-%'];
System.debug(LoggingLevel.INFO, 'PHASE9 DEMO cleanup complete: deleted records selected only by DEMO- keys.');
