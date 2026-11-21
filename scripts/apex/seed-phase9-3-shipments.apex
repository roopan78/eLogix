// Phase 9 seed stage 3: convert accepted quotations, add items, and confirm through the service.
Set<Id> customerIds = new Map<Id, Account>([
    SELECT Id FROM Account WHERE Customer_Code__c LIKE 'DEMO-CUST-%'
]).keySet();
Set<Id> requestIds = new Set<Id>();
for (Shipment_Request__c request : [SELECT Id, Cargo_Description__c FROM Shipment_Request__c WHERE Customer__c IN :customerIds]) {
    if (request.Cargo_Description__c != null && request.Cargo_Description__c.startsWith('DEMO-REQ-')) requestIds.add(request.Id);
}
Map<Id, Quotation__c> quotations = new Map<Id, Quotation__c>([
    SELECT Id, Shipment_Request__c
    FROM Quotation__c
    WHERE Shipment_Request__c IN :requestIds AND Status__c = 'Accepted'
]);
System.assertEquals(20, quotations.size(), 'Run seed stages 1 and 2 first; all demo quotations must be Accepted.');
Set<Id> quotationIds = quotations.keySet();
Set<Id> convertedQuotationIds = new Set<Id>();
for (Shipment__c existing : [SELECT Quotation__c FROM Shipment__c WHERE Quotation__c IN :quotationIds]) {
    convertedQuotationIds.add(existing.Quotation__c);
}
List<Id> quotationIdsToConvert = new List<Id>();
for (Id quotationId : quotationIds) if (!convertedQuotationIds.contains(quotationId)) quotationIdsToConvert.add(quotationId);
if (!quotationIdsToConvert.isEmpty()) {
    ServiceResult converted = new QuotationService().convertToShipment(quotationIdsToConvert);
    System.assertEquals(0, converted.errors.size(), 'Quotation conversion errors: ' + converted.errors);
}

List<Shipment_Item__c> items = new List<Shipment_Item__c>();
List<Id> idsToConfirm = new List<Id>();
Integer confirmedOrSelectedCount = 0;
for (Shipment__c shipment : [
    SELECT Id, Status__c, Item_Count__c
    FROM Shipment__c
    WHERE Quotation__c IN :quotationIds
    ORDER BY Shipment_Number__c
]) {
    if (shipment.Status__c == 'Confirmed') {
        confirmedOrSelectedCount++;
        continue;
    }
    if (shipment.Status__c != 'Quoted' || confirmedOrSelectedCount >= 15) continue;
    confirmedOrSelectedCount++;
    if (shipment.Item_Count__c == null || shipment.Item_Count__c == 0) {
        items.add(new Shipment_Item__c(
            Shipment__c = shipment.Id,
            Item_Name__c = 'Industrial pump',
            SKU__c = 'DEMO-SKU-PUMP',
            Quantity__c = 1,
            Weight__c = 50,
            Declared_Value__c = 10000,
            Package_Type__c = 'Crate'
        ));
    }
    if (shipment.Status__c == 'Quoted') idsToConfirm.add(shipment.Id);
}
if (!items.isEmpty()) insert items;
if (!idsToConfirm.isEmpty()) {
    List<ShipmentService.StatusChangeRequest> confirmed = new List<ShipmentService.StatusChangeRequest>();
    for (Id shipmentId : idsToConfirm) confirmed.add(new ShipmentService.StatusChangeRequest(shipmentId, 'Confirmed', null));
    ServiceResult confirmedResult = new ShipmentService().changeStatus(confirmed);
    System.assertEquals(0, confirmedResult.errors.size(), 'Accepted quotation shipments must confirm: ' + confirmedResult.errors);
}
Set<Id> seededShipmentIds = new Map<Id, Shipment__c>([
    SELECT Id FROM Shipment__c WHERE Quotation__c IN :quotationIds
]).keySet();
System.debug(LoggingLevel.INFO, 'PHASE9 SEED 3 complete: shipments=' + seededShipmentIds.size() + ' confirmed=' + [SELECT count() FROM Shipment__c WHERE Id IN :seededShipmentIds AND Status__c = 'Confirmed'] + ' quoted=' + [SELECT count() FROM Shipment__c WHERE Id IN :seededShipmentIds AND Status__c = 'Quoted'] + ' trackingEvents=' + [SELECT count() FROM Tracking_Event__c WHERE Shipment__c IN :seededShipmentIds]);
