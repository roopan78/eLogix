/**
 * Custom permission checks for the running user.
 *
 * No caching across calls: callers that check the same permission many times in one operation
 * (for example the status policy over 200 records) keep a local cache for that operation.
 */
public inherited sharing class PermissionService {
    /** Pure unit tests only: forces the result for a permission name, ignoring real assignments. */
    @TestVisible
    private static Map<String, Boolean> testOverrides = new Map<String, Boolean>();

    /** True when the running user holds the custom permission. Never throws; unknown names return false. */
    public static Boolean hasPermission(String customPermissionApiName) {
        if (String.isBlank(customPermissionApiName)) {
            return false;
        }
        String name = customPermissionApiName.trim();
        if (testOverrides.containsKey(name)) {
            return testOverrides.get(name) == true;
        }
        return FeatureManagement.checkPermission(name);
    }
}
