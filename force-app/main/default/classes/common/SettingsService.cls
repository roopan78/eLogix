/**
 * Typed access to eLogix_Setting__mdt, so that no business threshold is hardcoded in Apex.
 *
 * Reads use getInstance(), which costs no SOQL. A missing record or an empty value throws
 * ConfigurationException: eLogix fails closed rather than inventing a default.
 */
public inherited sharing class SettingsService {
    public static final String SETTING_MISSING = 'SETTING_MISSING';

    /** Pure unit tests only: replaces a setting record by developer name. */
    @TestVisible
    private static Map<String, eLogix_Setting__mdt> testOverrides = new Map<String, eLogix_Setting__mdt>();

    public static Decimal getNumber(String developerName) {
        Decimal value = getSetting(developerName).Number_Value__c;
        if (value == null) {
            throw missing(developerName);
        }
        return value;
    }

    public static String getText(String developerName) {
        String value = getSetting(developerName).Text_Value__c;
        if (String.isBlank(value)) {
            throw missing(developerName);
        }
        return value;
    }

    public static Boolean getBoolean(String developerName) {
        return getSetting(developerName).Boolean_Value__c == true;
    }

    private static eLogix_Setting__mdt getSetting(String developerName) {
        if (String.isBlank(developerName)) {
            throw missing(developerName);
        }
        if (testOverrides.containsKey(developerName)) {
            return testOverrides.get(developerName);
        }
        eLogix_Setting__mdt setting = eLogix_Setting__mdt.getInstance(developerName);
        if (setting == null) {
            throw missing(developerName);
        }
        return setting;
    }

    private static ELogixException missing(String developerName) {
        return new ConfigurationException(String.format(Label.eLogix_Setting_Missing, new List<Object>{ developerName }))
            .withCode(SETTING_MISSING);
    }
}
