/**
 * FreightCalculationService: component arithmetic, rate card selection, totals mirror and the
 * discount threshold. Reference lane (TestDataFactory): Chennai to Bangalore, 350 km, 500 kg,
 * declared value 200,000, LCV card (base 2,000; 3.50/kg; 12.00/km; fuel 10%; insurance 0.5%).
 *
 *   weight 1,750.00 + distance 4,200.00 + base 2,000.00 = line haul 7,950.00
 *   fuel 795.00, insurance 1,000.00, freight charges 9,745.00, tax 12% 1,169.40, total 10,914.40
 */
@IsTest
private class FreightCalculationServiceTest {
    private static Integer sequence = 0;

    private static FreightRequest request(String vehicleType, Decimal weight, Decimal distance, Decimal declared, Date pricingDate) {
        FreightRequest request = new FreightRequest();
        request.key = 'R' + (sequence++);
        request.vehicleType = vehicleType;
        request.weightKg = weight;
        request.distanceKm = distance;
        request.declaredValue = declared;
        request.pricingDate = pricingDate;
        return request;
    }

    private static FreightRequest referenceRequest() {
        return request('LCV', 500, 350, 200000, Date.today());
    }

    private static Rate_Card__c card(String code) {
        Rate_Card__c card = TestDataFactory.buildRateCard(code, 'LCV');
        card.Id = TestDataFactory.fakeId(Rate_Card__c.SObjectType, ++sequence);
        return card;
    }

    /* ---------------- component arithmetic ---------------- */

    @IsTest
    static void referenceLaneComponents() {
        FreightBreakdown breakdown = FreightCalculationService.calculate(referenceRequest(), card('RC-REF'), 12);

        Assert.isTrue(breakdown.isPriced);
        Assert.areEqual(2000.00, breakdown.baseFreight);
        Assert.areEqual(0.00, breakdown.minimumUplift);
        Assert.areEqual(1750.00, breakdown.weightCharge);
        Assert.areEqual(4200.00, breakdown.distanceCharge);
        Assert.areEqual(795.00, breakdown.fuelSurcharge, 'Fuel is 10% of the line haul 7,950.');
        Assert.areEqual(1000.00, breakdown.insuranceCharge, 'Insurance is 0.5% of the declared value 200,000.');
        Assert.areEqual(9745.00, breakdown.freightCharges());
        Assert.areEqual(12, breakdown.taxPercent);
    }

    @IsTest
    static void minimumFreightUpliftIsRecordedInBaseAndRaisesFuel() {
        Rate_Card__c rateCard = card('RC-MIN');
        rateCard.Minimum_Freight__c = 10000;

        FreightBreakdown breakdown = FreightCalculationService.calculate(referenceRequest(), rateCard, 12);

        Assert.areEqual(2000.00, breakdown.rateCardBaseFreight);
        Assert.areEqual(2050.00, breakdown.minimumUplift, 'Line haul 7,950 is raised to the 10,000 minimum.');
        Assert.areEqual(4050.00, breakdown.baseFreight, 'The uplift is recorded in base freight (decision Q7).');
        Assert.areEqual(1000.00, breakdown.fuelSurcharge, 'Fuel applies after the uplift (decision Q5).');
        Assert.areEqual(1000.00, breakdown.insuranceCharge, 'Insurance is unaffected by the minimum.');
    }

    @IsTest
    static void minimumBelowLineHaulChangesNothing() {
        Rate_Card__c rateCard = card('RC-MIN-LOW');
        rateCard.Minimum_Freight__c = 7950; // exactly the line haul
        FreightBreakdown breakdown = FreightCalculationService.calculate(referenceRequest(), rateCard, 12);
        Assert.areEqual(0.00, breakdown.minimumUplift);
        Assert.areEqual(2000.00, breakdown.baseFreight);
    }

    @IsTest
    static void componentsRoundHalfUpToTwoDecimals() {
        Rate_Card__c rateCard = card('RC-ROUND');
        rateCard.Base_Freight__c = 0;
        rateCard.Rate_Per_KG__c = 1.005; // 1 kg -> 1.005 -> 1.01 under HALF_UP (1.00 under HALF_EVEN)
        rateCard.Rate_Per_KM__c = 0.125; // 1 km -> 0.125 -> 0.13
        rateCard.Fuel_Surcharge_Percent__c = 0;
        rateCard.Insurance_Percent__c = 0.5; // 1 x 0.5% = 0.005 -> 0.01

        FreightBreakdown breakdown = FreightCalculationService.calculate(request('LCV', 1, 1, 1, Date.today()), rateCard, 12);

        Assert.areEqual(1.01, breakdown.weightCharge);
        Assert.areEqual(0.13, breakdown.distanceCharge);
        Assert.areEqual(0.01, breakdown.insuranceCharge);
        Assert.areEqual(2, breakdown.weightCharge.scale());
    }

    @IsTest
    static void percentagesAreDividedByOneHundredExactlyOnce() {
        Rate_Card__c rateCard = card('RC-PCT');
        rateCard.Base_Freight__c = 1000;
        rateCard.Rate_Per_KG__c = 0;
        rateCard.Rate_Per_KM__c = 0;
        rateCard.Fuel_Surcharge_Percent__c = 12;
        rateCard.Insurance_Percent__c = 1;

        FreightBreakdown breakdown = FreightCalculationService.calculate(request('LCV', 1, 1, 50000, Date.today()), rateCard, 12);

        Assert.areEqual(120.00, breakdown.fuelSurcharge, '12% of 1,000.');
        Assert.areEqual(500.00, breakdown.insuranceCharge, '1% of 50,000.');
    }

    @IsTest
    static void blankDeclaredValueAndPercentagesGiveZero() {
        Rate_Card__c rateCard = card('RC-BLANK');
        rateCard.Fuel_Surcharge_Percent__c = null;
        rateCard.Insurance_Percent__c = null;
        rateCard.Minimum_Freight__c = null;

        FreightBreakdown breakdown = FreightCalculationService.calculate(request('LCV', 500, 350, null, Date.today()), rateCard, 12);

        Assert.areEqual(0.00, breakdown.fuelSurcharge);
        Assert.areEqual(0.00, breakdown.insuranceCharge, 'Blank declared value gives zero insurance (decision Q6).');
        Assert.areEqual(0.00, breakdown.minimumUplift);
    }

    @IsTest
    static void invalidInputsAreReportedPerRequest() {
        List<FreightRequest> requests = new List<FreightRequest>{
            request(null, 500, 350, 0, Date.today()),
            request('LCV', 0, 350, 0, Date.today()),
            request('LCV', 500, null, 0, Date.today()),
            request('LCV', 500, 350, 0, null),
            null
        };

        List<FreightBreakdown> breakdowns = new FreightCalculationService().quote(requests);

        Assert.areEqual(5, breakdowns.size());
        for (FreightBreakdown breakdown : breakdowns) {
            Assert.isFalse(breakdown.isPriced);
            Assert.areEqual(FreightCalculationService.PRICING_INPUT_INVALID, breakdown.errorCode);
        }
        Assert.areEqual(String.format(Label.eLogix_Pricing_Input_Invalid, new List<Object>{ 'weight' }), breakdowns[1].errorMessage);
    }

    @IsTest
    static void missingTaxSettingFailsClosed() {
        SettingsService.testOverrides.put(FreightCalculationService.TAX_SETTING, new eLogix_Setting__mdt());
        try {
            new FreightCalculationService().quote(new List<FreightRequest>{ referenceRequest() });
            Assert.fail('Pricing must not invent a tax rate.');
        } catch (ConfigurationException e) {
            Assert.areEqual(SettingsService.SETTING_MISSING, e.code);
        }
    }

    /* ---------------- rate card selection (decisions Q9, Q10) ---------------- */

    private static FreightCalculationService.RateCardChoice choose(FreightRequest request, List<Rate_Card__c> cards) {
        return FreightCalculationService.chooseRateCard(request, cards);
    }

    @IsTest
    static void ineligibleCardsAreIgnored() {
        Date today = Date.today();
        Rate_Card__c wrongVehicle = card('RC-TRUCK');
        wrongVehicle.Vehicle_Type__c = 'Container Truck';
        Rate_Card__c inactive = card('RC-INACTIVE');
        inactive.Is_Active__c = false;
        Rate_Card__c expired = card('RC-EXPIRED');
        expired.Effective_To__c = today.addDays(-1);
        Rate_Card__c future = card('RC-FUTURE');
        future.Effective_From__c = today.addDays(1);
        Rate_Card__c otherUnit = card('RC-OTHER-BU');
        otherUnit.Business_Unit__c = TestDataFactory.fakeId(Business_Unit__c.SObjectType, 99);
        Rate_Card__c otherRegion = card('RC-NORTH');
        otherRegion.Region__c = 'North';

        FreightRequest request = referenceRequest();
        request.businessUnitId = TestDataFactory.fakeId(Business_Unit__c.SObjectType, 1);
        request.region = 'South';
        FreightCalculationService.RateCardChoice choice = choose(
            request,
            new List<Rate_Card__c>{ wrongVehicle, inactive, expired, future, otherUnit, otherRegion }
        );

        Assert.isNull(choice.card);
        Assert.areEqual(FreightCalculationService.RATE_CARD_NOT_FOUND, choice.errorCode);
        Assert.areEqual(
            String.format(Label.eLogix_Rate_Card_Not_Found, new List<Object>{ 'LCV', today.format() }),
            choice.errorMessage
        );
    }

    @IsTest
    static void effectiveDatesAreInclusiveOnThePricingDate() {
        Date pricingDate = Date.today().addDays(3);
        Rate_Card__c startsThatDay = card('RC-STARTS');
        startsThatDay.Effective_From__c = pricingDate;
        Rate_Card__c endsThatDay = card('RC-ENDS');
        endsThatDay.Effective_From__c = pricingDate.addDays(-10);
        endsThatDay.Effective_To__c = pricingDate;
        endsThatDay.Selection_Priority__c = 20;

        FreightRequest request = request('LCV', 500, 350, 0, pricingDate);
        Assert.areEqual(startsThatDay.Id, choose(request, new List<Rate_Card__c>{ startsThatDay }).card.Id);
        Assert.areEqual(endsThatDay.Id, choose(request, new List<Rate_Card__c>{ endsThatDay }).card.Id);
        // The pricing date, not today, decides (decision Q9): a card starting tomorrow-plus applies to a later pickup.
        Assert.isNull(choose(referenceRequest(), new List<Rate_Card__c>{ startsThatDay }).card);
    }

    @IsTest
    static void specificityBeatsPriority() {
        Id unitId = TestDataFactory.fakeId(Business_Unit__c.SObjectType, 1);
        Rate_Card__c generic = card('RC-GENERIC');
        generic.Selection_Priority__c = 1;
        Rate_Card__c regional = card('RC-SOUTH');
        regional.Region__c = 'South';
        regional.Selection_Priority__c = 50;
        Rate_Card__c unitCard = card('RC-BU');
        unitCard.Business_Unit__c = unitId;
        unitCard.Selection_Priority__c = 90;
        Rate_Card__c unitAndRegion = card('RC-BU-SOUTH');
        unitAndRegion.Business_Unit__c = unitId;
        unitAndRegion.Region__c = 'South';
        unitAndRegion.Selection_Priority__c = 99;

        FreightRequest request = referenceRequest();
        request.businessUnitId = unitId;
        request.region = 'South';

        Assert.areEqual(regional.Id, choose(request, new List<Rate_Card__c>{ generic, regional }).card.Id, 'Region beats generic.');
        Assert.areEqual(unitCard.Id, choose(request, new List<Rate_Card__c>{ generic, regional, unitCard }).card.Id, 'Business unit beats region.');
        Assert.areEqual(
            unitAndRegion.Id,
            choose(request, new List<Rate_Card__c>{ generic, regional, unitCard, unitAndRegion }).card.Id,
            'Business unit and region beats business unit alone.'
        );
    }

    @IsTest
    static void priorityThenLatestEffectiveFromBreakTies() {
        Rate_Card__c low = card('RC-P5');
        low.Selection_Priority__c = 5;
        Rate_Card__c high = card('RC-P10');
        high.Selection_Priority__c = 10;
        Assert.areEqual(low.Id, choose(referenceRequest(), new List<Rate_Card__c>{ high, low }).card.Id);

        Rate_Card__c older = card('RC-OLD');
        older.Effective_From__c = Date.today().addDays(-60);
        Rate_Card__c newer = card('RC-NEW');
        newer.Effective_From__c = Date.today().addDays(-5);
        Assert.areEqual(newer.Id, choose(referenceRequest(), new List<Rate_Card__c>{ older, newer }).card.Id);

        Rate_Card__c noPriority = card('RC-NOPRIO');
        noPriority.Selection_Priority__c = null;
        Assert.areEqual(high.Id, choose(referenceRequest(), new List<Rate_Card__c>{ noPriority, high }).card.Id, 'A blank priority ranks last.');
    }

    @IsTest
    static void equalTopCandidatesFailAsAmbiguous() {
        Rate_Card__c first = card('RC-A');
        Rate_Card__c second = card('RC-B');
        Rate_Card__c worse = card('RC-C');
        worse.Selection_Priority__c = 50;

        FreightCalculationService.RateCardChoice choice = choose(referenceRequest(), new List<Rate_Card__c>{ worse, first, second });

        Assert.isNull(choice.card);
        Assert.areEqual(FreightCalculationService.RATE_CARD_AMBIGUOUS, choice.errorCode);

        // A strictly better card later in the list resolves the tie.
        Rate_Card__c better = card('RC-D');
        better.Selection_Priority__c = 1;
        Assert.areEqual(better.Id, choose(referenceRequest(), new List<Rate_Card__c>{ first, second, better }).card.Id);
    }

    @IsTest
    static void quotingTwoHundredRequestsUsesOneQuery() {
        List<Rate_Card__c> cards = new List<Rate_Card__c>{
            TestDataFactory.buildRateCard('RC-LCV', 'LCV'),
            TestDataFactory.buildRateCard('RC-MINI', 'Mini Truck'),
            TestDataFactory.buildRateCard('RC-CONT', 'Container Truck')
        };
        insert cards;
        List<String> types = new List<String>{ 'LCV', 'Mini Truck', 'Container Truck' };
        List<FreightRequest> requests = new List<FreightRequest>();
        for (Integer i = 0; i < 200; i++) {
            FreightRequest pricing = request(types[Math.mod(i, 3)], 500, 350, 200000, Date.today().addDays(Math.mod(i, 5)));
            // Inserted cards take the eLogix_Region value-set default (South), so they are South-specific.
            pricing.region = 'South';
            requests.add(pricing);
        }

        Test.startTest();
        Integer queriesBefore = Limits.getQueries();
        Integer dmlBefore = Limits.getDmlStatements();
        List<FreightBreakdown> breakdowns = new FreightCalculationService().quote(requests);
        Integer queries = Limits.getQueries() - queriesBefore;
        Integer dml = Limits.getDmlStatements() - dmlBefore;
        Test.stopTest();

        Assert.areEqual(1, queries, 'One rate card query for the whole batch.');
        Assert.areEqual(0, dml, 'Pricing performs no DML.');
        for (Integer i = 0; i < 200; i++) {
            Assert.isTrue(breakdowns[i].isPriced, 'Not priced: ' + breakdowns[i].errorMessage);
            Assert.areEqual(requests[i].key, breakdowns[i].key, 'Order and keys are preserved.');
            Assert.areEqual(9745.00, breakdowns[i].freightCharges());
        }
    }

    /* ---------------- totals mirror and discount threshold ---------------- */

    @IsTest
    static void totalsMirrorHonoursTaxableLinesAndNeverTaxesBelowZero() {
        // 9,745 charges; lines: taxable 500, non-taxable 300, taxable discount line -200; header discount 100.
        FreightCalculationService.QuotationTotals totals = FreightCalculationService.quotationTotals(9745, 600, 300, 100, 12);
        Assert.areEqual(10245.00, totals.subtotal);
        Assert.areEqual(1193.40, totals.taxAmount, '12% of 9,745 + 300 - 100.');
        Assert.areEqual(11438.40, totals.totalAmount);

        FreightCalculationService.QuotationTotals noTax = FreightCalculationService.quotationTotals(100, 500, 0, 150, 12);
        Assert.areEqual(0.00, noTax.taxAmount, 'Discount larger than the taxable base gives zero tax, not negative tax.');
        Assert.areEqual(450.00, noTax.totalAmount);
    }

    @IsTest
    static void discountThresholdBoundary() {
        // Default setting: 10% of gross freight.
        Assert.isTrue(FreightCalculationService.isDiscountWithinThreshold(1000, 0, 0, 100), 'Exactly 10% needs no approval.');
        Assert.isFalse(FreightCalculationService.isDiscountWithinThreshold(1000, 0, 0, 100.01), 'Above 10% needs approval.');
        // Lines: +200 charge and -50 discount (net 150). Gross 1,200; discount = header + 50.
        Assert.isTrue(FreightCalculationService.isDiscountWithinThreshold(1000, 150, -50, 70), '120 of 1,200 is exactly 10%.');
        Assert.isFalse(FreightCalculationService.isDiscountWithinThreshold(1000, 150, -50, 70.01));
        Assert.isTrue(FreightCalculationService.isDiscountWithinThreshold(0, 0, 0, 0));
        Assert.isFalse(FreightCalculationService.isDiscountWithinThreshold(0, 0, 0, 1));
        Assert.areEqual(10, FreightCalculationService.discountThresholdPercent());
    }

    @IsTest
    static void thresholdComesFromConfiguration() {
        SettingsService.testOverrides.put(
            FreightCalculationService.DISCOUNT_THRESHOLD_SETTING,
            new eLogix_Setting__mdt(Number_Value__c = 20)
        );
        Assert.isTrue(FreightCalculationService.isDiscountWithinThreshold(1000, 0, 0, 200));
        Assert.isFalse(FreightCalculationService.isDiscountWithinThreshold(1000, 0, 0, 200.01));
    }
}
