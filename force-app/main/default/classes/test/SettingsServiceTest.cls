@IsTest
private class SettingsServiceTest {
    @IsTest
    static void readsDeployedSettings() {
        Assert.areEqual(12, SettingsService.getNumber('Default_Tax_Percent'));
        Assert.areEqual('On Delivery', SettingsService.getText('Default_Billing_Milestone'));
        Assert.isFalse(SettingsService.getBoolean('Allow_Advance_Payments'));
    }

    @IsTest
    static void missingSettingFailsClosed() {
        for (String name : new List<String>{ 'Not_A_Setting', '', null }) {
            try {
                SettingsService.getNumber(name);
                Assert.fail('A missing setting must throw.');
            } catch (ConfigurationException e) {
                Assert.areEqual(SettingsService.SETTING_MISSING, e.code);
                Assert.areEqual(String.format(Label.eLogix_Setting_Missing, new List<Object>{ name }), e.getMessage());
            }
        }
    }

    @IsTest
    static void emptyValueFailsClosed() {
        SettingsService.testOverrides.put('Empty_Setting', new eLogix_Setting__mdt());
        try {
            SettingsService.getNumber('Empty_Setting');
            Assert.fail('An empty number must throw.');
        } catch (ConfigurationException e) {
            Assert.areEqual(SettingsService.SETTING_MISSING, e.code);
        }
        try {
            SettingsService.getText('Empty_Setting');
            Assert.fail('An empty text must throw.');
        } catch (ConfigurationException e) {
            Assert.areEqual(SettingsService.SETTING_MISSING, e.code);
        }
        Assert.isFalse(SettingsService.getBoolean('Empty_Setting'), 'An unset checkbox reads as false.');
    }

    @IsTest
    static void testOverridesReplaceDeployedValues() {
        SettingsService.testOverrides.put('Default_Tax_Percent', new eLogix_Setting__mdt(Number_Value__c = 18));
        Assert.areEqual(18, SettingsService.getNumber('Default_Tax_Percent'));
    }
}
