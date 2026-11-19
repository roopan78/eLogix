// eLogix ERP - Phase 1 metadata verification.
//
// Exercises the deployed data model end to end (roll-ups, formulas, validation rules, unique keys,
// custom metadata) and rolls everything back, so it consumes no data storage and can be re-run.
//
//   sf apex run --file scripts/apex/verify-phase1-metadata.apex --target-org eLogixDev
//
// Read the "SMOKE" debug lines; the last one is the summary. Run as a user holding
// eLogix_Administrator and NOT eLogix_Data_Migration (the bypass would mask validation checks).
Savepoint sp = Database.setSavepoint();
List<String> results = new List<String>();
Integer failures = 0;

// Returns the first error message of a failed DML, or null if the DML succeeded.
// (Anonymous Apex cannot declare methods that capture locals, so a helper class is used.)
class Probe {
    String insertError(SObject record) {
        Database.SaveResult r = Database.insert(record, false);
        return r.isSuccess() ? null : r.getErrors()[0].getMessage();
    }
    String updateError(SObject record) {
        Database.SaveResult r = Database.update(record, false);
        return r.isSuccess() ? null : r.getErrors()[0].getMessage();
    }
}
Probe probe = new Probe();

try {
    Business_Unit__c bu = new Business_Unit__c(Name = 'Smoke South', Business_Unit_Code__c = 'SMK-S', Region__c = 'South');
    insert bu;

    Account customer = new Account(Name = 'Smoke Customer', Customer_Code__c = 'SMK-C1', BillingStreet = '1 Anna Salai',
        BillingCity = 'Chennai', BillingPostalCode = '600002', Phone = '+91 44 0000 0000', Business_Unit__c = bu.Id);
    insert customer;

    // --- Validation: mandatory customer info
    String err = probe.insertError(new Account(Name = 'Bad Customer', Customer_Code__c = 'SMK-C2'));
    results.add((err != null ? 'PASS' : 'FAIL') + ' ACC_Customer_Mandatory_Info -> ' + err);
    if (err == null) failures++;

    // --- Validation: inactive customer cannot raise a request
    Account inactive = new Account(Name = 'Inactive Customer', Customer_Code__c = 'SMK-C3', BillingStreet = 'x', BillingCity = 'Madurai',
        BillingPostalCode = '625001', Phone = '1', Is_Active_Customer__c = false);
    insert inactive;
    err = probe.insertError(new Shipment_Request__c(Customer__c = inactive.Id, Business_Unit__c = bu.Id, Origin__c = 'Madurai',
        Destination__c = 'Chennai', Requested_Pickup_Date__c = Date.today().addDays(1)));
    results.add((err != null ? 'PASS' : 'FAIL') + ' SR_Customer_Must_Be_Active -> ' + err);
    if (err == null) failures++;

    // --- Valid request; delivery-before-pickup rejected
    Shipment_Request__c sr = new Shipment_Request__c(Customer__c = customer.Id, Business_Unit__c = bu.Id, Origin__c = 'Chennai',
        Destination__c = 'Bangalore', Requested_Pickup_Date__c = Date.today().addDays(1), Expected_Delivery_Date__c = Date.today().addDays(2),
        Total_Weight__c = 1200);
    insert sr;
    sr = [SELECT Request_Number__c, Status__c FROM Shipment_Request__c WHERE Id = :sr.Id];
    results.add((sr.Request_Number__c.startsWith('SR-') && sr.Status__c == 'Draft' ? 'PASS' : 'FAIL') + ' Request number ' + sr.Request_Number__c + ', default status ' + sr.Status__c);
    err = probe.insertError(new Shipment_Request__c(Customer__c = customer.Id, Business_Unit__c = bu.Id, Origin__c = 'Chennai',
        Destination__c = 'Hyderabad', Requested_Pickup_Date__c = Date.today().addDays(3), Expected_Delivery_Date__c = Date.today().addDays(2)));
    results.add((err != null ? 'PASS' : 'FAIL') + ' SR_Delivery_After_Pickup -> ' + err);
    if (err == null) failures++;

    // --- Quotation: roll-up of lines and formula totals
    // Phase 3 rules (QuotationDomain): a quotation must be priced (rate card set) and its request must be
    // Submitted or Under Review. The formula components below are still set directly to test the formulas.
    update new Shipment_Request__c(Id = sr.Id, Status__c = 'Submitted');
    Rate_Card__c qtCard = new Rate_Card__c(Name = 'Smoke Quote Card', Rate_Card_Code__c = 'SMK-RC-QT', Vehicle_Type__c = 'LCV',
        Base_Freight__c = 5000, Rate_Per_KG__c = 1, Rate_Per_KM__c = 10, Effective_From__c = Date.today());
    insert qtCard;
    Quotation__c qt = new Quotation__c(Shipment_Request__c = sr.Id, Rate_Card__c = qtCard.Id, Base_Freight__c = 5000, Weight_Charge__c = 1200, Distance_Charge__c = 3500,
        Fuel_Surcharge__c = 485, Insurance_Charge__c = 100, Discount__c = 285, Tax_Percent__c = 12);
    insert qt;
    insert new Quotation_Line__c(Quotation__c = qt.Id, Charge_Type__c = 'Loading', Amount__c = 500);
    qt = [SELECT Line_Total__c, Subtotal__c, Tax_Amount__c, Total_Amount__c, Customer_Name__c FROM Quotation__c WHERE Id = :qt.Id];
    // 5000+1200+3500+485+100+500-285 = 10500 ; tax 12% = 1260 ; total 11760
    Boolean qtOk = qt.Line_Total__c == 500 && qt.Subtotal__c == 10500 && qt.Tax_Amount__c == 1260 && qt.Total_Amount__c == 11760 && qt.Customer_Name__c == 'Smoke Customer';
    results.add((qtOk ? 'PASS' : 'FAIL') + ' Quotation totals: lines=' + qt.Line_Total__c + ' subtotal=' + qt.Subtotal__c + ' tax=' + qt.Tax_Amount__c + ' total=' + qt.Total_Amount__c + ' customer=' + qt.Customer_Name__c);
    if (!qtOk) failures++;
    err = probe.insertError(new Quotation_Line__c(Quotation__c = qt.Id, Charge_Type__c = 'Toll', Amount__c = -10));
    results.add((err != null ? 'PASS' : 'FAIL') + ' QTL_Amount_Sign_Matches_Type -> ' + err);
    if (err == null) failures++;

    // --- Shipment: weight rule, item roll-ups, delayed formula
    err = probe.insertError(new Shipment__c(Customer__c = customer.Id, Business_Unit__c = bu.Id, Origin__c = 'Chennai', Destination__c = 'Bangalore',
        Weight__c = 0, Distance__c = 350));
    results.add((err != null ? 'PASS' : 'FAIL') + ' SHP_Weight_Must_Be_Positive -> ' + err);
    if (err == null) failures++;

    Shipment__c shp = new Shipment__c(Customer__c = customer.Id, Business_Unit__c = bu.Id, Shipment_Request__c = sr.Id, Quotation__c = qt.Id,
        Origin__c = 'Chennai', Destination__c = 'Bangalore', Weight__c = 1200, Distance__c = 350,
        Pickup_Date__c = Date.today().addDays(-3), Expected_Delivery_Date__c = Date.today().addDays(-1));
    insert shp;
    insert new List<Shipment_Item__c>{
        new Shipment_Item__c(Shipment__c = shp.Id, Item_Name__c = 'Textile bales', Quantity__c = 20, Weight__c = 800, Declared_Value__c = 150000),
        new Shipment_Item__c(Shipment__c = shp.Id, Item_Name__c = 'Machine spares', Quantity__c = 5, Weight__c = 400, Declared_Value__c = 90000)
    };
    insert new Freight_Charge__c(Shipment__c = shp.Id, Charge_Type__c = 'Toll', Amount__c = 750);
    shp = [SELECT Shipment_Number__c, Status__c, Item_Count__c, Total_Item_Weight__c, Total_Declared_Value__c, Additional_Charges__c, Is_Delayed__c, Is_Billable__c FROM Shipment__c WHERE Id = :shp.Id];
    Boolean shpOk = shp.Status__c == 'Draft' && shp.Item_Count__c == 2 && shp.Total_Item_Weight__c == 1200 && shp.Total_Declared_Value__c == 240000
        && shp.Additional_Charges__c == 750 && shp.Is_Delayed__c == true && shp.Is_Billable__c == false;
    results.add((shpOk ? 'PASS' : 'FAIL') + ' Shipment ' + shp.Shipment_Number__c + ': status=' + shp.Status__c + ' items=' + shp.Item_Count__c + ' itemWeight=' + shp.Total_Item_Weight__c
        + ' declared=' + shp.Total_Declared_Value__c + ' extraCharges=' + shp.Additional_Charges__c + ' delayed=' + shp.Is_Delayed__c + ' billable=' + shp.Is_Billable__c);
    if (!shpOk) failures++;

    // --- Tracking events are immutable
    Tracking_Event__c te = new Tracking_Event__c(Shipment__c = shp.Id, Event_Type__c = 'Created', Event_Timestamp__c = System.now(), Source__c = 'Apex Service');
    insert te;
    te.Remarks__c = 'tamper';
    err = probe.updateError(te);
    results.add((err != null ? 'PASS' : 'FAIL') + ' TE_Events_Are_Immutable -> ' + err);
    if (err == null) failures++;

    // --- Fleet: open maintenance roll-up with multi-value filter, allocatable formula
    Vehicle__c veh = new Vehicle__c(Name = 'Smoke Truck', Vehicle_Number__c = 'TN-01-SM-0001', Vehicle_Type__c = 'Container Truck', Capacity__c = 9000,
        Business_Unit__c = bu.Id, Registration_Expiry__c = Date.today().addYears(1), Insurance_Expiry__c = Date.today().addMonths(6));
    insert veh;
    insert new List<Vehicle_Maintenance__c>{
        new Vehicle_Maintenance__c(Vehicle__c = veh.Id, Maintenance_Type__c = 'Preventive', Scheduled_Date__c = Date.today().addDays(5)),
        new Vehicle_Maintenance__c(Vehicle__c = veh.Id, Maintenance_Type__c = 'Oil Change', Scheduled_Date__c = Date.today().addDays(-10), Status__c = 'Completed', Completion_Date__c = Date.today().addDays(-9)),
        new Vehicle_Maintenance__c(Vehicle__c = veh.Id, Maintenance_Type__c = 'Inspection', Scheduled_Date__c = Date.today().addDays(-2), Status__c = 'Cancelled')
    };
    veh = [SELECT Open_Maintenance_Count__c, Is_Allocatable__c, Is_Documents_Valid__c FROM Vehicle__c WHERE Id = :veh.Id];
    Boolean vehOk = veh.Open_Maintenance_Count__c == 1 && veh.Is_Allocatable__c && veh.Is_Documents_Valid__c;
    results.add((vehOk ? 'PASS' : 'FAIL') + ' Vehicle: openMaintenance=' + veh.Open_Maintenance_Count__c + ' (expected 1: Completed and Cancelled excluded) allocatable=' + veh.Is_Allocatable__c);
    if (!vehOk) failures++;

    // --- Warehouse: stock invariants and roll-ups
    Warehouse__c wh = new Warehouse__c(Name = 'Smoke WH', Warehouse_Code__c = 'SMK-WH1', Location__c = 'Sriperumbudur', Business_Unit__c = bu.Id);
    insert wh;
    Inventory__c inv = new Inventory__c(Name = 'Smoke SKU', Warehouse__c = wh.Id, SKU__c = 'SKU-1', Product_Name__c = 'Cartons', Available_Quantity__c = 100, Reserved_Quantity__c = 20, Reorder_Level__c = 90, Unit_Value__c = 50);
    insert inv;
    inv.Reserved_Quantity__c = 150;
    err = probe.updateError(inv);
    results.add((err != null ? 'PASS' : 'FAIL') + ' STK_Reserved_Within_Available -> ' + err);
    if (err == null) failures++;
    inv = [SELECT Net_Available_Quantity__c, Is_Below_Reorder__c, Stock_Value__c FROM Inventory__c WHERE Id = :inv.Id];
    wh = [SELECT SKU_Count__c, Total_Available_Quantity__c, Total_Reserved_Quantity__c FROM Warehouse__c WHERE Id = :wh.Id];
    Boolean whOk = inv.Net_Available_Quantity__c == 80 && inv.Is_Below_Reorder__c && inv.Stock_Value__c == 5000 && wh.SKU_Count__c == 1 && wh.Total_Available_Quantity__c == 100 && wh.Total_Reserved_Quantity__c == 20;
    results.add((whOk ? 'PASS' : 'FAIL') + ' Inventory net=' + inv.Net_Available_Quantity__c + ' belowReorder=' + inv.Is_Below_Reorder__c + ' value=' + inv.Stock_Value__c + ' | Warehouse skus=' + wh.SKU_Count__c + ' avail=' + wh.Total_Available_Quantity__c + ' reserved=' + wh.Total_Reserved_Quantity__c);
    if (!whOk) failures++;

    // --- Finance: invoice roll-ups only count completed payments; duplicate invoice key rejected
    Invoice__c invc = new Invoice__c(Shipment__c = shp.Id, Customer__c = customer.Id, Billing_Milestone__c = 'On Delivery', Invoice_Key__c = shp.Id + ':On Delivery',
        Invoice_Date__c = Date.today(), Due_Date__c = Date.today().addDays(30));
    insert invc;
    insert new List<Invoice_Line__c>{
        new Invoice_Line__c(Invoice__c = invc.Id, Charge_Type__c = 'Base Freight', Amount__c = 10000, Tax_Percent__c = 12, Tax_Amount__c = 1200),
        new Invoice_Line__c(Invoice__c = invc.Id, Charge_Type__c = 'Toll', Amount__c = 750, Tax_Percent__c = 12, Tax_Amount__c = 90)
    };
    insert new List<Payment__c>{
        new Payment__c(Invoice__c = invc.Id, Payment_Reference__c = 'SMK-PAY-1', Payment_Date__c = Date.today(), Amount__c = 5000, Payment_Method__c = 'UPI', Status__c = 'Completed'),
        new Payment__c(Invoice__c = invc.Id, Payment_Reference__c = 'SMK-PAY-2', Payment_Date__c = Date.today(), Amount__c = 2000, Payment_Method__c = 'UPI', Status__c = 'Pending')
    };
    invc = [SELECT Invoice_Number__c, Subtotal__c, Tax__c, Total_Amount__c, Paid_Amount__c, Balance_Amount__c FROM Invoice__c WHERE Id = :invc.Id];
    Boolean invOk = invc.Subtotal__c == 10750 && invc.Tax__c == 1290 && invc.Total_Amount__c == 12040 && invc.Paid_Amount__c == 5000 && invc.Balance_Amount__c == 7040;
    results.add((invOk ? 'PASS' : 'FAIL') + ' Invoice ' + invc.Invoice_Number__c + ': subtotal=' + invc.Subtotal__c + ' tax=' + invc.Tax__c + ' total=' + invc.Total_Amount__c + ' paid=' + invc.Paid_Amount__c + ' balance=' + invc.Balance_Amount__c);
    if (!invOk) failures++;
    err = probe.insertError(new Invoice__c(Shipment__c = shp.Id, Customer__c = customer.Id, Billing_Milestone__c = 'On Delivery', Invoice_Key__c = shp.Id + ':On Delivery', Invoice_Date__c = Date.today()));
    results.add((err != null ? 'PASS' : 'FAIL') + ' Duplicate Invoice_Key__c rejected -> ' + err);
    if (err == null) failures++;

    // --- Returns: approval required before pickup scheduling
    err = probe.insertError(new Return_Request__c(Original_Shipment__c = shp.Id, Customer__c = customer.Id, Return_Reason__c = 'Damaged in Transit',
        Return_Type__c = 'Full Return', Pickup_Address__c = 'Bangalore', Status__c = 'Pickup Scheduled'));
    results.add((err != null ? 'PASS' : 'FAIL') + ' RET_Approval_Before_Pickup -> ' + err);
    if (err == null) failures++;

    // --- Pricing: percent fields are validated as fractions (12% valid, 150% rejected)
    Rate_Card__c rc = new Rate_Card__c(Name = 'Smoke LCV', Rate_Card_Code__c = 'SMK-RC-LCV', Vehicle_Type__c = 'LCV', Base_Freight__c = 2500,
        Rate_Per_KG__c = 1.5, Rate_Per_KM__c = 18, Fuel_Surcharge_Percent__c = 12, Insurance_Percent__c = 0.5, Effective_From__c = Date.today().addMonths(-1));
    err = probe.insertError(rc);
    results.add((err == null ? 'PASS' : 'FAIL') + ' Rate card with 12% fuel surcharge accepted -> ' + err);
    if (err != null) failures++;
    rc = [SELECT Is_Currently_Effective__c FROM Rate_Card__c WHERE Rate_Card_Code__c = 'SMK-RC-LCV'];
    results.add((rc.Is_Currently_Effective__c ? 'PASS' : 'FAIL') + ' Rate card currently effective=' + rc.Is_Currently_Effective__c);
    if (!rc.Is_Currently_Effective__c) failures++;
    err = probe.insertError(new Rate_Card__c(Name = 'Smoke Bad', Rate_Card_Code__c = 'SMK-RC-BAD', Vehicle_Type__c = 'LCV', Base_Freight__c = 1,
        Rate_Per_KG__c = 1, Rate_Per_KM__c = 1, Fuel_Surcharge_Percent__c = 150, Effective_From__c = Date.today()));
    results.add((err != null ? 'PASS' : 'FAIL') + ' RC_Percentages_In_Range rejects 150% -> ' + err);
    if (err == null) failures++;

    // --- Configuration metadata readable from Apex
    Integer transitions = [SELECT COUNT() FROM Shipment_Status_Transition__mdt WHERE Is_Active__c = true];
    eLogix_Setting__mdt tax = eLogix_Setting__mdt.getInstance('Default_Tax_Percent');
    Boolean cfgOk = transitions == 46 && tax != null && tax.Number_Value__c == 12;
    results.add((cfgOk ? 'PASS' : 'FAIL') + ' CMDT: active transitions=' + transitions + ' Default_Tax_Percent=' + (tax == null ? null : tax.Number_Value__c));
    if (!cfgOk) failures++;
} catch (Exception e) {
    results.add('FAIL unexpected exception: ' + e.getTypeName() + ': ' + e.getMessage() + ' @ ' + e.getStackTraceString());
    failures++;
} finally {
    Database.rollback(sp);
}

// Informational only (not counted as a check): the Indian demo expects INR and Asia/Kolkata.
System.debug(LoggingLevel.ERROR, 'SMOKE INFO org currency=' + UserInfo.getDefaultCurrency() + ' user time zone=' + UserInfo.getTimeZone().getID());
for (String line : results) System.debug(LoggingLevel.ERROR, 'SMOKE ' + line);
System.debug(LoggingLevel.ERROR, 'SMOKE SUMMARY checks=' + results.size() + ' failures=' + failures);
