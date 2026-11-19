/**
 * SOQL for Rate_Card__c. User mode: a user who cannot read rate cards cannot price.
 */
public inherited sharing class RateCardSelector {
    /**
     * Active cards for the given vehicle types whose effective range overlaps [fromDate, toDate].
     * One query for a whole pricing batch; FreightCalculationService ranks the candidates per request.
     */
    public List<Rate_Card__c> selectEffectiveCandidates(Set<String> vehicleTypes, Date fromDate, Date toDate) {
        if (vehicleTypes == null || vehicleTypes.isEmpty() || fromDate == null || toDate == null) {
            return new List<Rate_Card__c>();
        }
        return [
            SELECT
                Id,
                Name,
                Rate_Card_Code__c,
                Vehicle_Type__c,
                Business_Unit__c,
                Region__c,
                Base_Freight__c,
                Rate_Per_KG__c,
                Rate_Per_KM__c,
                Fuel_Surcharge_Percent__c,
                Insurance_Percent__c,
                Minimum_Freight__c,
                Effective_From__c,
                Effective_To__c,
                Is_Active__c,
                Selection_Priority__c
            FROM Rate_Card__c
            WHERE
                Is_Active__c = TRUE
                AND Vehicle_Type__c IN :vehicleTypes
                AND Effective_From__c <= :toDate
                AND (Effective_To__c = NULL
                OR Effective_To__c >= :fromDate)
            WITH USER_MODE
            ORDER BY Rate_Card_Code__c
        ];
    }
}
