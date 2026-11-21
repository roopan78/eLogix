// Phase 9 seed stage 1: deterministic master data. Run as an admin with eLogix_Administrator.
// Every stage is a separate `sf apex run` transaction. Upserts use unique external-ID fields.
Business_Unit__c unit = new Business_Unit__c(
    Name = 'DEMO- South Region',
    Business_Unit_Code__c = 'DEMO-SOUTH',
    Region__c = 'South',
    Is_Active__c = true,
    Head_Office_Location__c = 'Chennai'
);
upsert unit Business_Unit_Code__c;

List<Account> customers = new List<Account>();
for (Integer i = 1; i <= 10; i++) {
    String suffix = i < 10 ? '0' + i : String.valueOf(i);
    customers.add(new Account(
        Name = 'DEMO- Customer ' + suffix,
        Customer_Code__c = 'DEMO-CUST-' + suffix,
        BillingStreet = '12 Anna Salai',
        BillingCity = 'Chennai',
        BillingPostalCode = '600002',
        Phone = '+91 44 2345 6789',
        Is_Active_Customer__c = true,
        Business_Unit__c = unit.Id
    ));
}
upsert customers Customer_Code__c;

List<String> origins = new List<String>{ 'Chennai', 'Madurai', 'Chennai', 'Bangalore', 'Madurai' };
List<String> destinations = new List<String>{ 'Bangalore', 'Coimbatore', 'Hyderabad', 'Mumbai', 'Chennai' };
List<Integer> distances = new List<Integer>{ 350, 215, 625, 980, 460 };
List<Route__c> routes = new List<Route__c>();
for (Integer i = 0; i < origins.size(); i++) {
    String suffix = i < 9 ? '0' + String.valueOf(i + 1) : String.valueOf(i + 1);
    routes.add(new Route__c(
        Name = 'DEMO- ' + origins[i] + ' to ' + destinations[i],
        Route_Code__c = 'DEMO-ROUTE-' + suffix,
        Origin__c = origins[i],
        Destination__c = destinations[i],
        Distance__c = distances[i],
        Estimated_Transit_Hours__c = 8 + i * 2,
        Status__c = 'Active'
    ));
}
upsert routes Route_Code__c;

List<Rate_Card__c> cards = new List<Rate_Card__c>();
for (Integer i = 1; i <= 5; i++) {
    String suffix = '0' + i;
    cards.add(new Rate_Card__c(
        Name = 'DEMO- LCV Rate ' + suffix,
        Rate_Card_Code__c = 'DEMO-RATE-' + suffix,
        Vehicle_Type__c = 'LCV',
        Business_Unit__c = unit.Id,
        Region__c = 'South',
        Base_Freight__c = 2000 + i * 100,
        Rate_Per_KG__c = 3.50,
        Rate_Per_KM__c = 12.00,
        Fuel_Surcharge_Percent__c = 10,
        Insurance_Percent__c = 0.5,
        Minimum_Freight__c = 0,
        Effective_From__c = Date.today().addDays(-30),
        Is_Active__c = true,
        // Keep DEMO cards in a deterministic priority order so equal-specificity cards never tie.
        Selection_Priority__c = 10 + i
    ));
}
upsert cards Rate_Card_Code__c;

List<Vehicle__c> vehicles = new List<Vehicle__c>();
List<Driver__c> drivers = new List<Driver__c>();
for (Integer i = 1; i <= 10; i++) {
    String suffix = i < 10 ? '0' + i : String.valueOf(i);
    vehicles.add(new Vehicle__c(
        Name = 'DEMO- Truck ' + suffix,
        Vehicle_Number__c = 'DEMO-VEH-' + suffix,
        Vehicle_Type__c = 'LCV',
        Capacity__c = 1000,
        Business_Unit__c = unit.Id,
        Registration_Expiry__c = Date.today().addDays(365),
        Insurance_Expiry__c = Date.today().addDays(365),
        Status__c = 'Available'
    ));
    drivers.add(new Driver__c(
        Name = 'DEMO- Driver ' + suffix,
        License_Number__c = 'DEMO-LIC-' + suffix,
        License_Expiry__c = Date.today().addDays(365),
        Business_Unit__c = unit.Id,
        Status__c = 'Available'
    ));
}
upsert vehicles Vehicle_Number__c;
upsert drivers License_Number__c;
System.debug(LoggingLevel.INFO, 'PHASE9 SEED 1 complete: unit=1 customers=10 routes=5 rateCards=5 vehicles=10 drivers=10');
