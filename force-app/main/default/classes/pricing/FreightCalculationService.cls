/**
 * The single home of eLogix pricing arithmetic (CLAUDE.md section 5, Freight rules).
 *
 *   quote()                      selects the applicable rate card and prices each component
 *   quotationTotals()            mirrors the Quotation__c Subtotal / Tax / Total formulas
 *   isDiscountWithinThreshold()  the discount approval threshold (decisions Q12, Q13)
 *
 * No rate, percentage, tax or threshold is hardcoded: rates come from Rate_Card__c, tax and the
 * threshold from eLogix_Setting__mdt. Percent values are held as Apex values (12 means 12%) and
 * divided by 100 exactly once, here. Components are rounded to 2 decimals HALF_UP (decision Q15).
 * See docs/PRICING_IMPLEMENTATION.md for the worked reference lane.
 */
public with sharing class FreightCalculationService {
    public static final String RATE_CARD_NOT_FOUND = 'RATE_CARD_NOT_FOUND';
    public static final String RATE_CARD_AMBIGUOUS = 'RATE_CARD_AMBIGUOUS';
    public static final String PRICING_INPUT_INVALID = 'PRICING_INPUT_INVALID';

    @TestVisible
    private static final String TAX_SETTING = 'Default_Tax_Percent';
    @TestVisible
    private static final String DISCOUNT_THRESHOLD_SETTING = 'Max_Discount_Percent_No_Approval';

    private static final Integer MONEY_SCALE = 2;
    private static final Decimal ONE_HUNDRED = 100;
    private static final Decimal ZERO = 0;

    /* ------------------------------------------------------------------ */
    /* Quote                                                               */
    /* ------------------------------------------------------------------ */

    /**
     * Prices each request against the applicable rate card. One query for the whole batch.
     * Returns one breakdown per request, in input order. Unpriceable requests carry an error code
     * and a labelled message; they do not stop the others. Throws ConfigurationException when the
     * tax setting is missing (fail closed).
     */
    public List<FreightBreakdown> quote(List<FreightRequest> requests) {
        List<FreightBreakdown> breakdowns = new List<FreightBreakdown>();
        if (requests == null || requests.isEmpty()) {
            return breakdowns;
        }
        Decimal taxPercent = SettingsService.getNumber(TAX_SETTING);

        Set<String> vehicleTypes = new Set<String>();
        Date earliest;
        Date latest;
        for (FreightRequest request : requests) {
            if (invalidInput(request) != null) {
                continue;
            }
            vehicleTypes.add(request.vehicleType);
            earliest = earliest == null || request.pricingDate < earliest ? request.pricingDate : earliest;
            latest = latest == null || request.pricingDate > latest ? request.pricingDate : latest;
        }
        List<Rate_Card__c> candidates = new RateCardSelector().selectEffectiveCandidates(vehicleTypes, earliest, latest);

        for (FreightRequest request : requests) {
            String invalidField = invalidInput(request);
            if (invalidField != null) {
                breakdowns.add(
                    FreightBreakdown.failure(
                        request?.key,
                        PRICING_INPUT_INVALID,
                        String.format(Label.eLogix_Pricing_Input_Invalid, new List<Object>{ invalidField })
                    )
                );
                continue;
            }
            RateCardChoice choice = chooseRateCard(request, candidates);
            if (choice.card == null) {
                breakdowns.add(FreightBreakdown.failure(request.key, choice.errorCode, choice.errorMessage));
            } else {
                breakdowns.add(calculate(request, choice.card, taxPercent));
            }
        }
        return breakdowns;
    }

    /** Name of the first missing or invalid input, or null when the request can be priced. */
    private static String invalidInput(FreightRequest request) {
        if (request == null) {
            return 'request';
        }
        if (String.isBlank(request.vehicleType)) {
            return 'vehicle type';
        }
        if (request.weightKg == null || request.weightKg <= 0) {
            return 'weight';
        }
        if (request.distanceKm == null || request.distanceKm <= 0) {
            return 'distance';
        }
        if (request.pricingDate == null) {
            return 'pricing date';
        }
        return null;
    }

    /* ------------------------------------------------------------------ */
    /* Rate card selection (decisions Q9, Q10)                             */
    /* ------------------------------------------------------------------ */

    /**
     * Eligible: active, same vehicle type, effective on the pricing date (both ends inclusive),
     * card business unit blank or equal to the request's, card region blank or equal to the
     * request's. Ranking: specificity (business unit 2, region 1), then lowest Selection_Priority__c,
     * then latest Effective_From__c. An exact tie at the top fails closed as ambiguous.
     */
    @TestVisible
    private static RateCardChoice chooseRateCard(FreightRequest request, List<Rate_Card__c> candidates) {
        Rate_Card__c best;
        Boolean tied = false;
        for (Rate_Card__c card : candidates) {
            if (!isEligible(card, request)) {
                continue;
            }
            if (best == null) {
                best = card;
                tied = false;
                continue;
            }
            Integer order = compareRank(card, best);
            if (order < 0) {
                best = card;
                tied = false;
            } else if (order == 0) {
                tied = true;
            }
        }
        String dateText = request.pricingDate.format();
        if (best == null) {
            return new RateCardChoice(
                null,
                RATE_CARD_NOT_FOUND,
                String.format(Label.eLogix_Rate_Card_Not_Found, new List<Object>{ request.vehicleType, dateText })
            );
        }
        if (tied) {
            return new RateCardChoice(
                null,
                RATE_CARD_AMBIGUOUS,
                String.format(Label.eLogix_Rate_Card_Ambiguous, new List<Object>{ request.vehicleType, dateText })
            );
        }
        return new RateCardChoice(best, null, null);
    }

    private static Boolean isEligible(Rate_Card__c card, FreightRequest request) {
        return card.Is_Active__c == true &&
            card.Vehicle_Type__c == request.vehicleType &&
            card.Effective_From__c != null &&
            card.Effective_From__c <= request.pricingDate &&
            (card.Effective_To__c == null || card.Effective_To__c >= request.pricingDate) &&
            (card.Business_Unit__c == null || card.Business_Unit__c == request.businessUnitId) &&
            (String.isBlank(card.Region__c) || card.Region__c == request.region);
    }

    /** Negative when a ranks above b, positive when below, 0 for an exact tie. */
    private static Integer compareRank(Rate_Card__c a, Rate_Card__c b) {
        Integer specificityA = specificity(a);
        Integer specificityB = specificity(b);
        if (specificityA != specificityB) {
            return specificityA > specificityB ? -1 : 1;
        }
        // A blank priority ranks after every set priority.
        if (a.Selection_Priority__c != b.Selection_Priority__c) {
            if (a.Selection_Priority__c == null) {
                return 1;
            }
            if (b.Selection_Priority__c == null) {
                return -1;
            }
            return a.Selection_Priority__c < b.Selection_Priority__c ? -1 : 1;
        }
        if (a.Effective_From__c != b.Effective_From__c) {
            return a.Effective_From__c > b.Effective_From__c ? -1 : 1;
        }
        return 0;
    }

    private static Integer specificity(Rate_Card__c card) {
        return (card.Business_Unit__c != null ? 2 : 0) + (String.isNotBlank(card.Region__c) ? 1 : 0);
    }

    /* ------------------------------------------------------------------ */
    /* Component arithmetic (decisions Q5, Q6, Q7, Q15)                    */
    /* ------------------------------------------------------------------ */

    @TestVisible
    private static FreightBreakdown calculate(FreightRequest request, Rate_Card__c card, Decimal taxPercent) {
        FreightBreakdown breakdown = new FreightBreakdown();
        breakdown.key = request.key;
        breakdown.isPriced = true;
        breakdown.rateCardId = card.Id;
        breakdown.taxPercent = taxPercent;

        Decimal base = money(card.Base_Freight__c);
        breakdown.weightCharge = money(request.weightKg * orZero(card.Rate_Per_KG__c));
        breakdown.distanceCharge = money(request.distanceKm * orZero(card.Rate_Per_KM__c));
        Decimal lineHaul = base + breakdown.weightCharge + breakdown.distanceCharge;

        // Q7: the minimum applies to base + weight + distance; the uplift is recorded in base freight.
        breakdown.rateCardBaseFreight = base;
        breakdown.minimumUplift = money(greater(ZERO, orZero(card.Minimum_Freight__c) - lineHaul));
        breakdown.baseFreight = base + breakdown.minimumUplift;
        Decimal lineHaulAfterMinimum = lineHaul + breakdown.minimumUplift;

        // Q5: fuel on the line haul after the uplift. Q6: insurance on the declared cargo value.
        breakdown.fuelSurcharge = money(lineHaulAfterMinimum * fraction(card.Fuel_Surcharge_Percent__c));
        breakdown.insuranceCharge = money(orZero(request.declaredValue) * fraction(card.Insurance_Percent__c));
        return breakdown;
    }

    /* ------------------------------------------------------------------ */
    /* Quotation totals (mirror of the Quotation__c formulas, decision Q14) */
    /* ------------------------------------------------------------------ */

    /**
     * Same arithmetic as the deployed formulas:
     *   Subtotal = charges + all lines - discount
     *   Tax      = MAX(0, charges + taxable lines - discount) x tax %
     *   Total    = Subtotal + MAX(0, charges + taxable lines - discount) x tax %
     * Each result is rounded once, at the end, as a currency formula is.
     */
    public static QuotationTotals quotationTotals(
        Decimal freightCharges,
        Decimal lineTotal,
        Decimal taxableLineTotal,
        Decimal discount,
        Decimal taxPercent
    ) {
        Decimal subtotal = orZero(freightCharges) + orZero(lineTotal) - orZero(discount);
        Decimal taxBase = greater(ZERO, orZero(freightCharges) + orZero(taxableLineTotal) - orZero(discount));
        Decimal tax = taxBase * fraction(taxPercent);
        QuotationTotals totals = new QuotationTotals();
        totals.subtotal = money(subtotal);
        totals.taxAmount = money(tax);
        totals.totalAmount = money(subtotal + tax);
        return totals;
    }

    /* ------------------------------------------------------------------ */
    /* Discount approval threshold (decisions Q12, Q13, Q19)               */
    /* ------------------------------------------------------------------ */

    /**
     * True when the total discount is at or below Max_Discount_Percent_No_Approval percent of gross
     * freight. Gross = freight components + positive additional lines, before discount and tax.
     * Total discount = header discount + |negative Discount lines|.
     *
     * @param lineTotal          net sum of all lines (the Line_Total__c roll-up)
     * @param discountLineTotal  sum of Discount-type lines (zero or negative)
     */
    public static Boolean isDiscountWithinThreshold(
        Decimal freightCharges,
        Decimal lineTotal,
        Decimal discountLineTotal,
        Decimal headerDiscount
    ) {
        Decimal discountLines = orZero(discountLineTotal);
        Decimal gross = orZero(freightCharges) + orZero(lineTotal) - discountLines;
        Decimal totalDiscount = orZero(headerDiscount) + discountLines.abs();
        return totalDiscount <= gross * fraction(discountThresholdPercent());
    }

    /** The configured threshold in percent (10 means 10%). Throws ConfigurationException when missing. */
    public static Decimal discountThresholdPercent() {
        return SettingsService.getNumber(DISCOUNT_THRESHOLD_SETTING);
    }

    /* ------------------------------------------------------------------ */
    /* Helpers and types                                                   */
    /* ------------------------------------------------------------------ */

    private static Decimal money(Decimal value) {
        return orZero(value).setScale(MONEY_SCALE, System.RoundingMode.HALF_UP);
    }

    private static Decimal fraction(Decimal percent) {
        return orZero(percent) / ONE_HUNDRED;
    }

    private static Decimal orZero(Decimal value) {
        return value == null ? ZERO : value;
    }

    private static Decimal greater(Decimal a, Decimal b) {
        return a >= b ? a : b;
    }

    public class QuotationTotals {
        public Decimal subtotal;
        public Decimal taxAmount;
        public Decimal totalAmount;
    }

    @TestVisible
    private class RateCardChoice {
        public Rate_Card__c card;
        public String errorCode;
        public String errorMessage;

        public RateCardChoice(Rate_Card__c card, String errorCode, String errorMessage) {
            this.card = card;
            this.errorCode = errorCode;
            this.errorMessage = errorMessage;
        }
    }
}
