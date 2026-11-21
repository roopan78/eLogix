// eLogix ERP - Phase 3 post-deploy verification (pricing, quotation, approval, conversion).
//
// Runs against the live org as the executing user (an administrator holding eLogix_Administrator),
// then rolls everything back. Exercises live settings, formulas, validation rules and triggers.
//
//   sf apex run --file scripts/apex/verify-phase3-pricing.apex --target-org eLogixDev
//
// Expect "SMOKE SUMMARY checks=19 failures=0" in the output.

class Smoke {
    Integer checks = 0;
    Integer failures = 0;

    void check(String name, Boolean passed, String detail) {
        checks++;
        if (!passed) {
            failures++;
        }
        System.debug(LoggingLevel.ERROR, 'SMOKE ' + (passed ? 'PASS ' : 'FAIL ') + name + (passed ? '' : ' | ' + detail));
    }

    String firstError(Database.SaveResult result) {
        return result.isSuccess() ? '(saved)' : result.getErrors()[0].getMessage();
    }
}

Smoke smoke = new Smoke();
smoke.check(
    'pricing settings deployed (tax 12, validity 15, threshold 10)',
    SettingsService.getNumber('Default_Tax_Percent') == 12 &&
    SettingsService.getNumber('Quotation_Validity_Days') == 15 &&
    SettingsService.getNumber('Max_Discount_Percent_No_Approval') == 10,
    'settings differ'
);

Savepoint savepoint = Database.setSavepoint();
try {
    Business_Unit__c businessUnit = new Business_Unit__c(Name = 'Smoke Business Unit P3', Business_Unit_Code__c = 'SMOKE-P3', Region__c = 'South', Is_Active__c = true);
    insert businessUnit;
    Account customer = new Account(Name = 'Smoke Phase Three Textiles', Is_Active_Customer__c = true);
    insert customer;
    Route__c route = new Route__c(Name = 'Smoke Chennai - Bangalore', Route_Code__c = 'SMOKE-RT-P3', Origin__c = 'Chennai', Destination__c = 'Bangalore', Distance__c = 350, Status__c = 'Active');
    insert route;
    Rate_Card__c card = new Rate_Card__c(
        Name = 'Smoke LCV',
        Rate_Card_Code__c = 'SMOKE-RC-P3',
        Vehicle_Type__c = 'LCV',
        Base_Freight__c = 2000,
        Rate_Per_KG__c = 3.5,
        Rate_Per_KM__c = 12,
        Fuel_Surcharge_Percent__c = 10,
        Insurance_Percent__c = 0.5,
        Effective_From__c = Date.today().addDays(-30),
        Is_Active__c = true,
        Selection_Priority__c = 10
    );
    insert card;
    System.debug(LoggingLevel.ERROR, 'SMOKE INFO rate card region after insert without a region = ' + [SELECT Region__c FROM Rate_Card__c WHERE Id = :card.Id].Region__c);

    Shipment_Request__c request = new Shipment_Request__c(
        Customer__c = customer.Id,
        Business_Unit__c = businessUnit.Id,
        Route__c = route.Id,
        Origin__c = 'Chennai',
        Destination__c = 'Bangalore',
        Requested_Pickup_Date__c = Date.today().addDays(3),
        Expected_Delivery_Date__c = Date.today().addDays(5),
        Total_Weight__c = 500,
        Declared_Value__c = 200000,
        Requested_Vehicle_Type__c = 'LCV',
        Status__c = 'Submitted'
    );
    insert request;

    QuotationService service = new QuotationService();
    ServiceResult created = service.createFromRequests(new List<Id>{ request.Id });
    smoke.check('quotation created from the request', created.isSuccess && created.recordIds.size() == 1, String.valueOf(created.errors));
    Id quotationId = created.recordIds[0];
    Quotation__c quotation = [
        SELECT Base_Freight__c, Weight_Charge__c, Distance_Charge__c, Fuel_Surcharge__c, Insurance_Charge__c, Tax_Percent__c,
            Subtotal__c, Tax_Amount__c, Total_Amount__c, Status__c, Shipment_Request__r.Status__c
        FROM Quotation__c WHERE Id = :quotationId
    ];
    smoke.check(
        'reference lane components (2000 / 1750 / 4200 / 795 / 1000)',
        quotation.Base_Freight__c == 2000 && quotation.Weight_Charge__c == 1750 && quotation.Distance_Charge__c == 4200 &&
        quotation.Fuel_Surcharge__c == 795 && quotation.Insurance_Charge__c == 1000 && quotation.Tax_Percent__c == 12,
        String.valueOf(quotation)
    );
    smoke.check(
        'formula totals (9745.00 / 1169.40 / 10914.40)',
        quotation.Subtotal__c == 9745 && quotation.Tax_Amount__c == 1169.40 && quotation.Total_Amount__c == 10914.40,
        quotation.Subtotal__c + ' / ' + quotation.Tax_Amount__c + ' / ' + quotation.Total_Amount__c
    );
    smoke.check('request moved to Quoted', quotation.Shipment_Request__r.Status__c == 'Quoted', quotation.Shipment_Request__r.Status__c);

    Shipment_Request__c otherRequest = request.clone(false, true);
    insert otherRequest;
    Database.SaveResult repoint = Database.update(new Quotation__c(Id = quotationId, Shipment_Request__c = otherRequest.Id), false);
    smoke.check('quotation cannot be re-pointed to another request (A1)', smoke.firstError(repoint) == Label.eLogix_Quotation_Request_Immutable, smoke.firstError(repoint));

    insert new List<Quotation_Line__c>{
        new Quotation_Line__c(Quotation__c = quotationId, Charge_Type__c = 'Toll', Amount__c = 500, Is_Taxable__c = true),
        new Quotation_Line__c(Quotation__c = quotationId, Charge_Type__c = 'Loading', Amount__c = 300, Is_Taxable__c = false)
    };
    Quotation__c withLines = [
        SELECT Base_Freight__c, Weight_Charge__c, Distance_Charge__c, Fuel_Surcharge__c, Insurance_Charge__c,
            Line_Total__c, Taxable_Line_Total__c, Discount__c, Tax_Percent__c, Subtotal__c, Tax_Amount__c, Total_Amount__c
        FROM Quotation__c WHERE Id = :quotationId
    ];
    FreightCalculationService.QuotationTotals expected = FreightCalculationService.quotationTotals(
        9745, withLines.Line_Total__c, withLines.Taxable_Line_Total__c, withLines.Discount__c, withLines.Tax_Percent__c
    );
    smoke.check(
        'non-taxable line excluded from tax; Apex mirror equals formulas (Q14)',
        withLines.Taxable_Line_Total__c == 500 && withLines.Tax_Amount__c == 1229.40 &&
        expected.subtotal == withLines.Subtotal__c && expected.taxAmount == withLines.Tax_Amount__c && expected.totalAmount == withLines.Total_Amount__c,
        withLines.Tax_Amount__c + ' vs ' + expected.taxAmount + ', ' + withLines.Total_Amount__c + ' vs ' + expected.totalAmount
    );

    update new Quotation__c(Id = quotationId, Discount__c = 2000);
    service.submitForApproval(new List<Id>{ quotationId });
    smoke.check('19% discount goes to Pending Approval', [SELECT Status__c FROM Quotation__c WHERE Id = :quotationId].Status__c == 'Pending Approval', 'not pending');

    ServiceResult selfApproval = service.approve(new List<Id>{ quotationId });
    smoke.check('owner cannot approve own quotation (Q17)', !selfApproval.isSuccess && selfApproval.errors[0].code == QuotationService.SELF_APPROVAL, String.valueOf(selfApproval.errors));

    Database.SaveResult bypass = Database.update(new Quotation__c(Id = quotationId, Status__c = 'Approved'), false);
    smoke.check('status label alone cannot approve above threshold', !bypass.isSuccess() && smoke.firstError(bypass).contains('must be approved'), smoke.firstError(bypass));

    Database.SaveResult skip = Database.update(new Quotation__c(Id = quotationId, Status__c = 'Sent'), false);
    smoke.check('Pending Approval -> Sent is not an allowed transition', !skip.isSuccess() && smoke.firstError(skip).contains('cannot move from'), smoke.firstError(skip));

    Database.SaveResult discountChange = Database.update(new Quotation__c(Id = quotationId, Discount__c = 100), false);
    smoke.check('discount locked after Draft (Q18)', smoke.firstError(discountChange) == Label.eLogix_Quotation_Locked, smoke.firstError(discountChange));

    Database.SaveResult lateLine = Database.insert(new Quotation_Line__c(Quotation__c = quotationId, Charge_Type__c = 'Other', Amount__c = 10), false);
    smoke.check('lines locked after Draft (validation rule)', !lateLine.isSuccess() && smoke.firstError(lateLine).contains('only be added or changed while the quotation is in Draft'), smoke.firstError(lateLine));

    ServiceResult rejected = service.reject(new List<Id>{ quotationId }, 'Discount too high for this lane.');
    Quotation__c afterReject = [SELECT Status__c, Notes__c FROM Quotation__c WHERE Id = :quotationId];
    smoke.check('rejection returns to Draft with the reason (Q22)', rejected.isSuccess && afterReject.Status__c == 'Draft' && afterReject.Notes__c.contains('Discount too high'), String.valueOf(rejected.errors));

    update new Quotation__c(Id = quotationId, Discount__c = 0);
    service.submitForApproval(new List<Id>{ quotationId });
    update new Quotation__c(Id = quotationId, Status__c = 'Sent');
    update new Quotation__c(Id = quotationId, Status__c = 'Accepted');
    Quotation__c accepted = [SELECT Status__c, Total_Amount__c, Shipment_Request__r.Status__c FROM Quotation__c WHERE Id = :quotationId];
    smoke.check('within threshold: auto-approved, sent, accepted; request Approved', accepted.Status__c == 'Accepted' && accepted.Shipment_Request__r.Status__c == 'Approved', accepted.Status__c + ' / ' + accepted.Shipment_Request__r.Status__c);

    ServiceResult converted = service.convertToShipment(new List<Id>{ quotationId });
    Shipment__c shipment = converted.isSuccess
        ? [SELECT Status__c, Freight_Amount__c, Shipment_Request__r.Status__c, (SELECT Event_Type__c FROM Tracking_Events__r) FROM Shipment__c WHERE Id = :converted.recordIds[0]]
        : null;
    smoke.check(
        'converted to a Quoted shipment with Created event; request Converted',
        shipment != null && shipment.Status__c == 'Quoted' && shipment.Freight_Amount__c == accepted.Total_Amount__c &&
        shipment.Tracking_Events__r.size() == 1 && shipment.Tracking_Events__r[0].Event_Type__c == 'Created' &&
        shipment.Shipment_Request__r.Status__c == 'Converted',
        String.valueOf(converted.errors)
    );

    ServiceResult again = service.convertToShipment(new List<Id>{ quotationId });
    smoke.check('second conversion refused (Q20)', !again.isSuccess && again.errors[0].code == QuotationService.QUOTATION_ALREADY_CONVERTED, String.valueOf(again.errors));

    try {
        new QuotationDomain().syncRequestStatuses();
        smoke.check('request sync refused outside the trigger', false, 'no exception');
    } catch (AuthorizationException e) {
        smoke.check('request sync refused outside the trigger', e.code == QuotationDomain.REQUEST_SYNC_TRIGGER_ONLY, e.code);
    }
} finally {
    Database.rollback(savepoint);
}
smoke.check('no rows left behind', [SELECT COUNT() FROM Quotation__c] + [SELECT COUNT() FROM Shipment__c] + [SELECT COUNT() FROM Rate_Card__c WHERE Rate_Card_Code__c = 'SMOKE-RC-P3'] == 0, 'rows remain');
System.debug(LoggingLevel.ERROR, 'SMOKE SUMMARY checks=' + smoke.checks + ' failures=' + smoke.failures);
