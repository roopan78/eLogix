// Phase 9 seed stage 2: create requests and price them through QuotationService.
Business_Unit__c unit = [SELECT Id FROM Business_Unit__c WHERE Business_Unit_Code__c = 'DEMO-SOUTH' LIMIT 1];
List<Account> customers = [SELECT Id, Customer_Code__c FROM Account WHERE Customer_Code__c LIKE 'DEMO-CUST-%' ORDER BY Customer_Code__c];
List<Route__c> routes = [SELECT Id, Route_Code__c, Origin__c, Destination__c FROM Route__c WHERE Route_Code__c LIKE 'DEMO-ROUTE-%' ORDER BY Route_Code__c];
System.assertEquals(10, customers.size(), 'Run seed stage 1 first.');
System.assertEquals(5, routes.size(), 'Run seed stage 1 first.');

Map<String, Shipment_Request__c> requestByKey = new Map<String, Shipment_Request__c>();
Set<Id> customerIds = new Map<Id, Account>(customers).keySet();
for (Shipment_Request__c request : [
    SELECT Id, Cargo_Description__c
    FROM Shipment_Request__c
    WHERE Customer__c IN :customerIds
]) {
    if (request.Cargo_Description__c != null && request.Cargo_Description__c.startsWith('DEMO-REQ-')) {
        requestByKey.put(request.Cargo_Description__c, request);
    }
}

List<Shipment_Request__c> inserts = new List<Shipment_Request__c>();
for (Integer i = 1; i <= 20; i++) {
    String suffix = i < 10 ? '0' + i : String.valueOf(i);
    String key = 'DEMO-REQ-' + suffix;
    if (requestByKey.containsKey(key)) continue;
    Integer customerIndex = Math.mod(i - 1, customers.size());
    Integer routeIndex = Math.mod(i - 1, routes.size());
    inserts.add(new Shipment_Request__c(
        Customer__c = customers[customerIndex].Id,
        Business_Unit__c = unit.Id,
        Route__c = routes[routeIndex].Id,
        Origin__c = routes[routeIndex].Origin__c,
        Destination__c = routes[routeIndex].Destination__c,
        Requested_Pickup_Date__c = Date.today().addDays(3 + Math.mod(i, 7)),
        Expected_Delivery_Date__c = Date.today().addDays(5 + Math.mod(i, 7)),
        Total_Weight__c = 250 + i * 25,
        Declared_Value__c = 50000 + i * 5000,
        Requested_Vehicle_Type__c = 'LCV',
        Priority__c = 'Standard',
        Status__c = 'Submitted',
        Cargo_Description__c = key,
        Special_Instructions__c = 'DEMO- Repeatable seed record'
    ));
}
if (!inserts.isEmpty()) insert inserts;

Set<Id> requestIds = new Set<Id>();
for (Shipment_Request__c request : [
    SELECT Id, Cargo_Description__c
    FROM Shipment_Request__c
    WHERE Customer__c IN :customerIds
]) {
    if (request.Cargo_Description__c != null && request.Cargo_Description__c.startsWith('DEMO-REQ-')) requestIds.add(request.Id);
}
Set<Id> quotedRequestIds = new Set<Id>();
for (Quotation__c quotation : [SELECT Shipment_Request__c FROM Quotation__c WHERE Shipment_Request__c IN :requestIds]) {
    quotedRequestIds.add(quotation.Shipment_Request__c);
}
List<Id> priceRequestIds = new List<Id>();
for (Id requestId : requestIds) if (!quotedRequestIds.contains(requestId)) priceRequestIds.add(requestId);
if (!priceRequestIds.isEmpty()) {
    ServiceResult result = new QuotationService().createFromRequests(priceRequestIds);
    System.assertEquals(0, result.errors.size(), 'QuotationService errors: ' + result.errors);
}

List<Id> draftQuotationIds = new List<Id>();
for (Quotation__c quotation : [SELECT Id FROM Quotation__c WHERE Shipment_Request__c IN :requestIds AND Status__c = 'Draft']) {
    draftQuotationIds.add(quotation.Id);
}
if (!draftQuotationIds.isEmpty()) {
    ServiceResult submitted = new QuotationService().submitForApproval(draftQuotationIds);
    System.assertEquals(0, submitted.errors.size(), 'Quotation approval submission errors: ' + submitted.errors);
}

List<Quotation__c> sent = new List<Quotation__c>();
for (Quotation__c quotation : [SELECT Id FROM Quotation__c WHERE Shipment_Request__c IN :requestIds AND Status__c = 'Approved']) {
    sent.add(new Quotation__c(Id = quotation.Id, Status__c = 'Sent'));
}
if (!sent.isEmpty()) update sent;
List<Quotation__c> accepted = new List<Quotation__c>();
for (Quotation__c quotation : [SELECT Id FROM Quotation__c WHERE Shipment_Request__c IN :requestIds AND Status__c = 'Sent']) {
    accepted.add(new Quotation__c(Id = quotation.Id, Status__c = 'Accepted'));
}
if (!accepted.isEmpty()) update accepted;
System.debug(LoggingLevel.INFO, 'PHASE9 SEED 2 complete: requests=' + requestIds.size() + ' acceptedQuotations=' + [SELECT count() FROM Quotation__c WHERE Shipment_Request__c IN :requestIds AND Status__c = 'Accepted']);
