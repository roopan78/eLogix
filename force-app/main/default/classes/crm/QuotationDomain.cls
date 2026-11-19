/**
 * Quotation rules that must hold on every entry path: UI, API, Data Loader, Flow and services.
 * Called by QuotationTriggerHandler. See docs/PRICING_IMPLEMENTATION.md and docs/PHASE3_PLAN.md
 * section 0 for the approved decisions.
 *
 * before insert  new quotations start in Draft, unapproved, and priced (they have a rate card)
 * before update  A1: Shipment_Request__c never changes after creation, in any status
 *                Q18 lock: after Draft, charges, discount, lines (through their roll-ups) and, since A4,
 *                   the validity date cannot change
 *                Q2 transitions: Draft -> Pending Approval | Approved; Pending Approval -> Approved | Draft;
 *                   Approved -> Sent; Sent -> Accepted | Rejected; Accepted and Rejected are terminal
 *                stamp: Approved_By__c / Approval_Date__c change only on Pending Approval -> Approved,
 *                   naming the running user, who must hold the approval permission and not own the quotation
 *                threshold: above Max_Discount_Percent_No_Approval, Approved / Sent / Accepted need a stamp
 * after insert   request Submitted | Under Review -> Quoted (Q4, Q21)
 * after update   into Accepted: request Quoted -> Approved (Q4)
 */
public with sharing class QuotationDomain {
    public static final String DRAFT = 'Draft';
    public static final String PENDING_APPROVAL = 'Pending Approval';
    public static final String APPROVED = 'Approved';
    public static final String SENT = 'Sent';
    public static final String ACCEPTED = 'Accepted';
    public static final String REJECTED = 'Rejected';
    public static final String APPROVE_PERMISSION = 'eLogix_Approve_Quotation';
    public static final String REQUEST_SYNC_TRIGGER_ONLY = 'REQUEST_SYNC_TRIGGER_ONLY';

    /** Request statuses (Shipment_Request__c.Status__c) moved by quotation events. */
    @TestVisible
    private static final Set<String> QUOTABLE_REQUEST_STATUSES = new Set<String>{ 'Submitted', 'Under Review' };
    private static final String REQUEST_QUOTED = 'Quoted';
    private static final String REQUEST_APPROVED = 'Approved';

    /** Decision Q2. Statuses absent as keys (Accepted, Rejected, Expired, Superseded) are terminal. */
    @TestVisible
    private static final Map<String, Set<String>> ALLOWED_TRANSITIONS = new Map<String, Set<String>>{
        DRAFT => new Set<String>{ PENDING_APPROVAL, APPROVED },
        PENDING_APPROVAL => new Set<String>{ APPROVED, DRAFT },
        APPROVED => new Set<String>{ SENT },
        SENT => new Set<String>{ ACCEPTED, REJECTED }
    };

    /**
     * Fields frozen once a quotation leaves Draft (decision Q18; validity date added by A4). The
     * roll-ups lock lines, including deletes. A rejected approval returns the quotation to Draft,
     * where these fields are editable again.
     */
    @TestVisible
    private static final List<Schema.SObjectField> LOCKED_FIELDS = new List<Schema.SObjectField>{
        Quotation__c.Discount__c,
        Quotation__c.Base_Freight__c,
        Quotation__c.Weight_Charge__c,
        Quotation__c.Distance_Charge__c,
        Quotation__c.Fuel_Surcharge__c,
        Quotation__c.Insurance_Charge__c,
        Quotation__c.Tax_Percent__c,
        Quotation__c.Rate_Card__c,
        Quotation__c.Shipment_Request__c,
        Quotation__c.Line_Total__c,
        Quotation__c.Taxable_Line_Total__c,
        Quotation__c.Valid_Until__c
    };

    /* ------------------------------------------------------------------ */
    /* Before insert                                                       */
    /* ------------------------------------------------------------------ */

    public void validateNew(List<Quotation__c> records) {
        for (Quotation__c quotation : records) {
            if (!DRAFT.equals(quotation.Status__c) || quotation.Approved_By__c != null || quotation.Approval_Date__c != null) {
                quotation.addError(Label.eLogix_Quotation_Must_Start_Draft);
            } else if (quotation.Rate_Card__c == null) {
                quotation.addError(Label.eLogix_Quotation_Not_Priced);
            }
        }
    }

    /* ------------------------------------------------------------------ */
    /* Before update                                                       */
    /* ------------------------------------------------------------------ */

    public void validateChanges(List<Quotation__c> records, Map<Id, Quotation__c> oldById) {
        Map<String, Boolean> permissionCache = new Map<String, Boolean>();
        List<Quotation__c> thresholdChecks = new List<Quotation__c>();
        Set<Id> stampedNow = new Set<Id>();

        for (Quotation__c quotation : records) {
            Quotation__c previous = oldById.get(quotation.Id);
            // A1: a quotation is priced for one request; it can never be re-pointed, in any status.
            String error = quotation.Shipment_Request__c != previous.Shipment_Request__c ? Label.eLogix_Quotation_Request_Immutable : null;
            if (error == null) {
                error = lockError(quotation, previous);
            }
            if (error == null) {
                error = transitionError(quotation, previous, permissionCache);
            }
            if (error == null) {
                StampCheck stamp = checkStamp(quotation, previous, permissionCache);
                error = stamp.error;
                if (stamp.isNewApproval) {
                    stampedNow.add(quotation.Id);
                }
            }
            if (error != null) {
                quotation.addError(error);
            } else if (needsThresholdCheck(quotation, previous)) {
                thresholdChecks.add(quotation);
            }
        }
        if (thresholdChecks.isEmpty()) {
            return;
        }

        // One aggregate query for the whole batch, only when an approval-sensitive transition happens.
        Map<Id, Quotation__c> checkById = new Map<Id, Quotation__c>(thresholdChecks);
        Map<Id, Decimal> discountLines = new QuotationSelector().sumDiscountLines(checkById.keySet());
        for (Quotation__c quotation : thresholdChecks) {
            Boolean withinThreshold = FreightCalculationService.isDiscountWithinThreshold(
                freightCharges(quotation),
                quotation.Line_Total__c,
                discountLines.get(quotation.Id),
                quotation.Discount__c
            );
            if (withinThreshold) {
                continue;
            }
            Quotation__c previous = oldById.get(quotation.Id);
            Boolean approvedByStamp = PENDING_APPROVAL.equals(previous.Status__c)
                ? stampedNow.contains(quotation.Id)
                : !DRAFT.equals(previous.Status__c) && quotation.Approved_By__c != null;
            if (!approvedByStamp) {
                quotation.Status__c.addError(
                    String.format(
                        Label.eLogix_Quotation_Approval_Required,
                        new List<Object>{ FreightCalculationService.discountThresholdPercent().format(), quotation.Status__c }
                    )
                );
            }
        }
    }

    private static String lockError(Quotation__c quotation, Quotation__c previous) {
        if (DRAFT.equals(previous.Status__c)) {
            return null;
        }
        for (Schema.SObjectField field : LOCKED_FIELDS) {
            if (isChanged(quotation.get(field), previous.get(field))) {
                return Label.eLogix_Quotation_Locked;
            }
        }
        return null;
    }

    private static String transitionError(Quotation__c quotation, Quotation__c previous, Map<String, Boolean> permissionCache) {
        String fromStatus = previous.Status__c;
        String toStatus = quotation.Status__c;
        if (fromStatus == toStatus) {
            return null;
        }
        Set<String> allowed = ALLOWED_TRANSITIONS.get(fromStatus);
        if (allowed == null || !allowed.contains(toStatus)) {
            return String.format(Label.eLogix_Quotation_Transition_Not_Allowed, new List<Object>{ fromStatus, toStatus });
        }
        // Pending Approval -> Draft is the approval rejection (decision Q22): approvers only.
        if (PENDING_APPROVAL.equals(fromStatus) && DRAFT.equals(toStatus) && !hasPermission(APPROVE_PERMISSION, permissionCache)) {
            return Label.eLogix_Quotation_Approver_Only;
        }
        return null;
    }

    /**
     * The stamp is never trusted: it may change only on Pending Approval -> Approved, it must name
     * the running user, who must hold the approval permission and must not own the quotation
     * (decision Q17), neither before nor after this save, so an owner change in the same save
     * cannot hide a self-approval (follow-up A2). The approval date is always set to the current
     * time, so it cannot be backdated.
     */
    private static StampCheck checkStamp(Quotation__c quotation, Quotation__c previous, Map<String, Boolean> permissionCache) {
        StampCheck check = new StampCheck();
        Boolean stampChanged =
            quotation.Approved_By__c != previous.Approved_By__c ||
            quotation.Approval_Date__c != previous.Approval_Date__c;
        if (!stampChanged) {
            return check;
        }
        Id runningUser = UserInfo.getUserId();
        Boolean valid =
            PENDING_APPROVAL.equals(previous.Status__c) &&
            APPROVED.equals(quotation.Status__c) &&
            previous.Approved_By__c == null &&
            quotation.Approved_By__c == runningUser &&
            quotation.OwnerId != runningUser &&
            previous.OwnerId != runningUser &&
            hasPermission(APPROVE_PERMISSION, permissionCache);
        if (!valid) {
            check.error = Label.eLogix_Quotation_Stamp_Invalid;
            return check;
        }
        quotation.Approval_Date__c = System.now();
        check.isNewApproval = true;
        return check;
    }

    private static Boolean needsThresholdCheck(Quotation__c quotation, Quotation__c previous) {
        return quotation.Status__c != previous.Status__c &&
            (APPROVED.equals(quotation.Status__c) || SENT.equals(quotation.Status__c) || ACCEPTED.equals(quotation.Status__c));
    }

    private static Decimal freightCharges(Quotation__c quotation) {
        return orZero(quotation.Base_Freight__c) +
            orZero(quotation.Weight_Charge__c) +
            orZero(quotation.Distance_Charge__c) +
            orZero(quotation.Fuel_Surcharge__c) +
            orZero(quotation.Insurance_Charge__c);
    }

    /* ------------------------------------------------------------------ */
    /* After insert / after update: request status (decisions Q4, Q21)     */
    /* ------------------------------------------------------------------ */

    /**
     * Moves the shipment requests of the quotations in the current trigger. Takes no arguments: it
     * reads Trigger.new and Trigger.oldMap itself and refuses to run outside a Quotation__c
     * after-save trigger, so no caller can supply the records it writes (the Phase 2 F1 pattern).
     * A request that cannot move fails only its own quotation row.
     */
    public void syncRequestStatuses() {
        if (!isQuotationAfterSaveTrigger()) {
            throw new AuthorizationException(Label.eLogix_Access_Denied).withCode(REQUEST_SYNC_TRIGGER_ONLY);
        }
        List<Quotation__c> records = (List<Quotation__c>) Trigger.new;
        Map<Id, Quotation__c> oldById = Trigger.isInsert ? null : (Map<Id, Quotation__c>) Trigger.oldMap;

        List<Quotation__c> movers = new List<Quotation__c>();
        Set<Id> requestIds = new Set<Id>();
        for (Quotation__c quotation : records) {
            Boolean created = oldById == null;
            Boolean accepted = !created && ACCEPTED.equals(quotation.Status__c) && !ACCEPTED.equals(oldById.get(quotation.Id).Status__c);
            if ((created || accepted) && quotation.Shipment_Request__c != null) {
                movers.add(quotation);
                requestIds.add(quotation.Shipment_Request__c);
            }
        }
        if (movers.isEmpty()) {
            return;
        }

        RequestStatusWriter writer = new RequestStatusWriter();
        Map<Id, Shipment_Request__c> requests = writer.lockRequests(requestIds);
        List<Shipment_Request__c> updates = new List<Shipment_Request__c>();
        List<Quotation__c> owners = new List<Quotation__c>();
        Set<Id> claimed = new Set<Id>();
        for (Quotation__c quotation : movers) {
            Shipment_Request__c request = requests.get(quotation.Shipment_Request__c);
            Boolean created = oldById == null;
            Set<String> expectedFrom = created ? QUOTABLE_REQUEST_STATUSES : new Set<String>{ REQUEST_QUOTED };
            String target = created ? REQUEST_QUOTED : REQUEST_APPROVED;
            if (request == null || !expectedFrom.contains(request.Status__c) || !claimed.add(request.Id)) {
                quotation.addError(
                    String.format(
                        created ? Label.eLogix_Request_Not_Quotable : Label.eLogix_Request_Not_Quoted,
                        new List<Object>{ request == null ? String.valueOf(quotation.Shipment_Request__c) : request.Name, request?.Status__c }
                    )
                );
                continue;
            }
            updates.add(new Shipment_Request__c(Id = request.Id, Status__c = target));
            owners.add(quotation);
        }

        List<Database.SaveResult> results = writer.updateRequests(updates);
        for (Integer i = 0; i < results.size(); i++) {
            if (!results[i].isSuccess()) {
                owners[i].addError(
                    String.format(
                        Label.eLogix_Request_Update_Failed,
                        new List<Object>{ requests.get(updates[i].Id).Name, results[i].getErrors()[0].getMessage() }
                    )
                );
            }
        }
    }

    private static Boolean isQuotationAfterSaveTrigger() {
        return Trigger.isExecuting &&
            Trigger.isAfter &&
            (Trigger.isInsert || Trigger.isUpdate) &&
            Trigger.new != null &&
            Trigger.new.getSObjectType() == Quotation__c.SObjectType;
    }

    /* ------------------------------------------------------------------ */
    /* Helpers                                                             */
    /* ------------------------------------------------------------------ */

    private static Boolean hasPermission(String permission, Map<String, Boolean> cache) {
        if (!cache.containsKey(permission)) {
            cache.put(permission, PermissionService.hasPermission(permission));
        }
        return cache.get(permission);
    }

    /** Numeric comparison for Decimals, so 10.0 and 10.00 are equal; plain comparison otherwise. */
    private static Boolean isChanged(Object current, Object previous) {
        if (current instanceof Decimal && previous instanceof Decimal) {
            return ((Decimal) current) != ((Decimal) previous);
        }
        return current != previous;
    }

    private static Decimal orZero(Decimal value) {
        return value == null ? 0 : value;
    }

    private class StampCheck {
        public String error;
        public Boolean isNewApproval = false;
    }

    /**
     * Moves request statuses without sharing. Justification: the Status__c move is a consequence of a
     * quotation save the user was already allowed to make, and saving a quotation that references a
     * request requires read access to that request. A Logistics Manager has View All but not Modify All
     * on Sales-owned requests until Phase 9 roles exist. Writes Status__c only, and only for the
     * requests of the quotations in the current trigger (see syncRequestStatuses).
     */
    private without sharing class RequestStatusWriter {
        public Map<Id, Shipment_Request__c> lockRequests(Set<Id> requestIds) {
            return new Map<Id, Shipment_Request__c>(
                [SELECT Id, Name, Status__c FROM Shipment_Request__c WHERE Id IN :requestIds WITH SYSTEM_MODE FOR UPDATE]
            );
        }

        public List<Database.SaveResult> updateRequests(List<Shipment_Request__c> requests) {
            if (requests.isEmpty()) {
                return new List<Database.SaveResult>();
            }
            return Database.update(requests, false, AccessLevel.SYSTEM_MODE);
        }
    }
}
