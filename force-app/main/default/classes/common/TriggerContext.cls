/**
 * The trigger that is executing now, as "Object.OPERATION" (for example "Shipment__c.BEFORE_UPDATE"),
 * or null outside a trigger. Selectors whose reads ignore sharing use it to refuse any caller outside
 * the trigger contexts they were built for (Phase 4 audit fix 5, reused by Phase 5).
 */
public inherited sharing class TriggerContext {
    public static String current() {
        if (!Trigger.isExecuting || Trigger.operationType == null) {
            return null;
        }
        List<SObject> records = Trigger.new != null ? Trigger.new : Trigger.old;
        if (records == null) {
            return null;
        }
        return String.valueOf(records.getSObjectType()) + '.' + Trigger.operationType.name();
    }

    /** Throws AuthorizationException with the given code unless the current trigger is one of the permitted ones. */
    public static void require(Set<String> permitted, String code) {
        String context = current();
        if (context == null || !permitted.contains(context)) {
            throw new AuthorizationException(Label.eLogix_Access_Denied).withCode(code);
        }
    }
}
