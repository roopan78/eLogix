/**
 * Decides whether shipment status changes are allowed.
 *
 * The allowed transitions are data: Shipment_Status_Transition__mdt, read with getAll() (no SOQL).
 * A blank From_Status__c marks an allowed initial status. The policy is pure: no SOQL, no DML, no
 * addError. It returns one Decision per change, in input order, and the caller acts on them.
 * Because it is stateless, the after-trigger re-evaluates instead of receiving state from the
 * before-trigger.
 *
 * Evaluation order (docs/APEX_ARCHITECTURE.md section 5.2):
 *   1 status required, 2 configuration present (fail closed), 3 hard rules, 4 row well-formed,
 *   5 transition exists, 6 transition active, 7 required permission, 8 guards.
 * The override permission skips only steps 5 to 7. Hard rules and guards always apply
 * (architecture decisions D1 and D2).
 */
public with sharing class ShipmentStatusPolicy {
    public static final String OVERRIDE_PERMISSION = 'eLogix_Override_Shipment_Status';
    public static final String OVERRIDE_EVENT_TYPE = 'Exception';

    public static final String STATUS_REQUIRED = 'STATUS_REQUIRED';
    public static final String CONFIGURATION_MISSING = 'CONFIGURATION_MISSING';
    public static final String CONFIGURATION_INVALID = 'CONFIGURATION_INVALID';
    public static final String TERMINAL_STATUS = 'TERMINAL_STATUS';
    public static final String DELIVERED_REVERSAL = 'DELIVERED_REVERSAL';
    public static final String INITIAL_STATUS_NOT_ALLOWED = 'INITIAL_STATUS_NOT_ALLOWED';
    public static final String TRANSITION_NOT_ALLOWED = 'TRANSITION_NOT_ALLOWED';
    public static final String TRANSITION_INACTIVE = 'TRANSITION_INACTIVE';
    public static final String PERMISSION_REQUIRED = 'PERMISSION_REQUIRED';

    /**
     * Hard rules from CLAUDE.md section 5 ("Cancelled shipments cannot be processed further",
     * "Delivered shipments cannot be dispatched again"). They are business invariants rather
     * than configuration, so they live in code and no permission can skip them.
     */
    @TestVisible
    private static final Set<String> TERMINAL_STATUSES = new Set<String>{ 'Closed', 'Cancelled' };
    @TestVisible
    private static final String DELIVERED = 'Delivered';
    @TestVisible
    private static final Set<String> PRE_DELIVERY_STATUSES = new Set<String>{
        'Draft',
        'Requested',
        'Quoted',
        'Confirmed',
        'Ready for Dispatch',
        'Dispatched',
        'In Transit',
        'Out for Delivery'
    };

    public enum Outcome {
        ALLOWED,
        ALLOWED_BY_OVERRIDE,
        REJECTED,
        NO_CHANGE
    }

    private final Map<String, Shipment_Status_Transition__mdt> activeByPair = new Map<String, Shipment_Status_Transition__mdt>();
    private final Set<String> inactivePairs = new Set<String>();
    @TestVisible
    private final Set<String> invalidPairs = new Set<String>();
    private final List<String> initialStatuses = new List<String>();
    private final List<ShipmentStatusGuard> guards;
    private Integer activeRowCount = 0;

    public ShipmentStatusPolicy() {
        this(Shipment_Status_Transition__mdt.getAll().values(), defaultGuards());
    }

    @TestVisible
    private ShipmentStatusPolicy(List<Shipment_Status_Transition__mdt> rows, List<ShipmentStatusGuard> guards) {
        this.guards = guards == null ? new List<ShipmentStatusGuard>() : guards;
        loadConfiguration(rows == null ? new List<Shipment_Status_Transition__mdt>() : rows);
    }

    public static List<ShipmentStatusGuard> defaultGuards() {
        return new List<ShipmentStatusGuard>{ new ShipmentItemsRequiredGuard(), new ShipmentAllocationGuard(), new ShipmentDeliveryGuard() };
    }

    /** Active values of Shipment__c.Status__c. */
    public static Set<String> validStatuses() {
        return activeValues(Shipment__c.Status__c);
    }

    /** Active values of Tracking_Event__c.Event_Type__c. */
    public static Set<String> validTrackingEventTypes() {
        return activeValues(Tracking_Event__c.Event_Type__c);
    }

    /* ------------------------------------------------------------------ */
    /* Evaluation                                                          */
    /* ------------------------------------------------------------------ */

    /** Creation: every record is checked against the allowed initial statuses. */
    public List<Decision> evaluateCreation(List<Shipment__c> records) {
        List<StatusChange> changes = new List<StatusChange>();
        for (Integer i = 0; i < records.size(); i++) {
            changes.add(new StatusChange(i, records[i], null, records[i].Status__c));
        }
        return evaluate(changes);
    }

    /** Update: records whose status did not change get a NO_CHANGE decision. */
    public List<Decision> evaluateStatusChanges(List<Shipment__c> records, Map<Id, Shipment__c> oldById) {
        List<StatusChange> changes = new List<StatusChange>();
        for (Integer i = 0; i < records.size(); i++) {
            Shipment__c previous = oldById == null ? null : oldById.get(records[i].Id);
            changes.add(new StatusChange(i, records[i], previous == null ? null : previous.Status__c, records[i].Status__c));
        }
        return evaluate(changes);
    }

    /**
     * Evaluates explicit changes. A blank fromStatus means creation. Each change needs a unique
     * index; guard violations are matched back to changes by index.
     */
    public List<Decision> evaluate(List<StatusChange> changes) {
        List<Decision> decisions = new List<Decision>();
        Map<Integer, Decision> decisionByIndex = new Map<Integer, Decision>();
        Map<String, Boolean> permissionCache = new Map<String, Boolean>();
        for (StatusChange change : changes) {
            Decision decision = decide(change, permissionCache);
            decisions.add(decision);
            decisionByIndex.put(change.index, decision);
        }
        applyGuards(changes, decisionByIndex);
        return decisions;
    }

    private Decision decide(StatusChange change, Map<String, Boolean> permissionCache) {
        Decision decision = new Decision(change);
        String fromStatus = String.isBlank(change.fromStatus) ? null : change.fromStatus;
        String toStatus = change.toStatus;

        // 1. A status is required.
        if (String.isBlank(toStatus)) {
            return decision.reject(STATUS_REQUIRED, Label.eLogix_Status_Required);
        }
        if (fromStatus != null && fromStatus.equals(toStatus)) {
            return decision.noChange();
        }
        // 2. Fail closed when no active transition is configured at all.
        if (activeRowCount == 0) {
            return decision.reject(CONFIGURATION_MISSING, Label.eLogix_Status_Configuration_Missing);
        }
        // 3. Hard rules: no permission can skip these.
        if (fromStatus != null && TERMINAL_STATUSES.contains(fromStatus)) {
            return decision.reject(TERMINAL_STATUS, format(Label.eLogix_Status_Terminal, fromStatus, toStatus, null));
        }
        if (DELIVERED.equals(fromStatus) && PRE_DELIVERY_STATUSES.contains(toStatus)) {
            return decision.reject(DELIVERED_REVERSAL, format(Label.eLogix_Status_Delivered_Reversal, fromStatus, toStatus, null));
        }
        // 4. A malformed or ambiguous configuration row blocks its transition.
        String key = pairKey(fromStatus, toStatus);
        if (invalidPairs.contains(key)) {
            return decision.reject(CONFIGURATION_INVALID, format(Label.eLogix_Status_Configuration_Invalid, fromStatus, toStatus, null));
        }

        // 5 to 7. Transition table checks; the override permission may skip these.
        Shipment_Status_Transition__mdt row = activeByPair.get(key);
        String tableCode;
        String tableMessage;
        if (row == null && inactivePairs.contains(key)) {
            tableCode = TRANSITION_INACTIVE;
            tableMessage = format(Label.eLogix_Status_Transition_Inactive, fromStatus, toStatus, null);
        } else if (row == null && fromStatus == null) {
            tableCode = INITIAL_STATUS_NOT_ALLOWED;
            tableMessage = format(Label.eLogix_Status_Initial_Not_Allowed, fromStatus, toStatus, String.join(initialStatuses, ', '));
        } else if (row == null) {
            tableCode = TRANSITION_NOT_ALLOWED;
            tableMessage = format(Label.eLogix_Status_Transition_Not_Allowed, fromStatus, toStatus, null);
        } else if (String.isNotBlank(row.Required_Permission__c) && !hasPermission(row.Required_Permission__c, permissionCache)) {
            tableCode = PERMISSION_REQUIRED;
            tableMessage = format(Label.eLogix_Status_Permission_Required, fromStatus, toStatus, null);
        }

        if (tableCode == null) {
            return decision.allow(Outcome.ALLOWED, eventTypeFor(row));
        }
        if (hasPermission(OVERRIDE_PERMISSION, permissionCache)) {
            Decision overridden = decision.allow(Outcome.ALLOWED_BY_OVERRIDE, row == null ? OVERRIDE_EVENT_TYPE : eventTypeFor(row));
            overridden.overriddenReasonCode = tableCode;
            overridden.overriddenMessage = tableMessage;
            return overridden;
        }
        return decision.reject(tableCode, tableMessage);
    }

    /** 8. Guards see only allowed changes, including overrides, and may reject them. */
    private void applyGuards(List<StatusChange> changes, Map<Integer, Decision> decisionByIndex) {
        for (ShipmentStatusGuard guard : guards) {
            Set<String> targets = guard.targetStatuses();
            if (targets == null || targets.isEmpty()) {
                continue;
            }
            List<StatusChange> candidates = new List<StatusChange>();
            for (StatusChange change : changes) {
                Decision decision = decisionByIndex.get(change.index);
                if (decision.isAllowed() && targets.contains(change.toStatus)) {
                    candidates.add(change);
                }
            }
            if (candidates.isEmpty()) {
                continue;
            }
            Map<Integer, Violation> violations = guard.check(candidates);
            if (violations == null) {
                continue;
            }
            for (Integer index : violations.keySet()) {
                Decision decision = decisionByIndex.get(index);
                Violation violation = violations.get(index);
                if (decision != null && violation != null && decision.isAllowed()) {
                    decision.reject(violation.code, violation.message);
                }
            }
        }
    }

    /* ------------------------------------------------------------------ */
    /* Configuration                                                       */
    /* ------------------------------------------------------------------ */

    private void loadConfiguration(List<Shipment_Status_Transition__mdt> rows) {
        Set<String> statuses = validStatuses();
        Set<String> eventTypes = validTrackingEventTypes();
        for (Shipment_Status_Transition__mdt row : rows) {
            String fromStatus = clean(row.From_Status__c);
            String toStatus = clean(row.To_Status__c);
            String key = pairKey(fromStatus, toStatus);
            if (row.Is_Active__c != true) {
                inactivePairs.add(key);
                continue;
            }
            activeRowCount++;
            Boolean wellFormed =
                statuses.contains(toStatus) &&
                (fromStatus == null || statuses.contains(fromStatus)) &&
                eventTypes.contains(eventTypeFor(row));
            if (!wellFormed || activeByPair.containsKey(key) || invalidPairs.contains(key)) {
                // Malformed, or a second active row for the same pair: ambiguous, so block the pair.
                invalidPairs.add(key);
                activeByPair.remove(key);
                continue;
            }
            activeByPair.put(key, row);
        }
        Set<String> initial = new Set<String>();
        for (Shipment_Status_Transition__mdt row : activeByPair.values()) {
            if (clean(row.From_Status__c) == null) {
                initial.add(clean(row.To_Status__c));
            }
        }
        initialStatuses.addAll(initial);
        initialStatuses.sort();
    }

    /** Configured event type; a blank value means the event type named after the target status. */
    private static String eventTypeFor(Shipment_Status_Transition__mdt row) {
        String configured = clean(row.Tracking_Event_Type__c);
        return configured == null ? clean(row.To_Status__c) : configured;
    }

    private Boolean hasPermission(String permissionName, Map<String, Boolean> permissionCache) {
        String name = permissionName.trim();
        if (!permissionCache.containsKey(name)) {
            permissionCache.put(name, PermissionService.hasPermission(name));
        }
        return permissionCache.get(name);
    }

    private static String pairKey(String fromStatus, String toStatus) {
        return (fromStatus == null ? '' : fromStatus) + '>' + (toStatus == null ? '' : toStatus);
    }

    private static String clean(String value) {
        return String.isBlank(value) ? null : value.trim();
    }

    private static String format(String template, String fromStatus, String toStatus, String extra) {
        return String.format(template, new List<Object>{ fromStatus, toStatus, extra });
    }

    private static Set<String> activeValues(Schema.SObjectField field) {
        Set<String> values = new Set<String>();
        for (Schema.PicklistEntry entry : field.getDescribe().getPicklistValues()) {
            if (entry.isActive()) {
                values.add(entry.getValue());
            }
        }
        return values;
    }

    /* ------------------------------------------------------------------ */
    /* Types                                                               */
    /* ------------------------------------------------------------------ */

    public class StatusChange {
        public Integer index;
        public Shipment__c record;
        public String fromStatus;
        public String toStatus;

        public StatusChange(Integer index, Shipment__c record, String fromStatus, String toStatus) {
            this.index = index;
            this.record = record;
            this.fromStatus = fromStatus;
            this.toStatus = toStatus;
        }
    }

    public class Violation {
        public String code;
        public String message;

        public Violation(String code, String message) {
            this.code = code;
            this.message = message;
        }
    }

    public class Decision {
        public Integer index;
        public Id shipmentId;
        public String fromStatus;
        public String toStatus;
        public ShipmentStatusPolicy.Outcome outcome;
        public String reasonCode;
        public String message;
        public String trackingEventType;
        public String overriddenReasonCode;
        public String overriddenMessage;

        public Decision(StatusChange change) {
            this.index = change.index;
            this.shipmentId = change.record == null ? null : change.record.Id;
            this.fromStatus = String.isBlank(change.fromStatus) ? null : change.fromStatus;
            this.toStatus = change.toStatus;
        }

        public Boolean isAllowed() {
            return outcome == ShipmentStatusPolicy.Outcome.ALLOWED || outcome == ShipmentStatusPolicy.Outcome.ALLOWED_BY_OVERRIDE;
        }

        public Boolean isRejected() {
            return outcome == ShipmentStatusPolicy.Outcome.REJECTED;
        }

        /** Every allowed status change is recorded as a tracking event (CLAUDE.md section 6). */
        public Boolean requiresTrackingEvent() {
            return isAllowed();
        }

        public Decision allow(ShipmentStatusPolicy.Outcome allowedOutcome, String eventType) {
            outcome = allowedOutcome;
            trackingEventType = eventType;
            return this;
        }

        public Decision reject(String code, String text) {
            outcome = ShipmentStatusPolicy.Outcome.REJECTED;
            reasonCode = code;
            message = text;
            trackingEventType = null;
            overriddenReasonCode = null;
            overriddenMessage = null;
            return this;
        }

        public Decision noChange() {
            outcome = ShipmentStatusPolicy.Outcome.NO_CHANGE;
            return this;
        }
    }
}
