/**
 * Shipment tracking history.
 *
 * recordStatusEvents (Shipment__c trigger, after context only) writes one Tracking_Event__c per
 * allowed status change. It reads the trigger records itself and recomputes the decisions from Trigger.old and Trigger.new instead of receiving state
 * from the before-trigger, and suppresses duplicates with a deterministic Event_Key__c checked
 * against the database (docs/APEX_ARCHITECTURE.md section 5.3):
 *
 *     {shipmentId}:{FromCode}>{ToCode}:{version}:{sequence}
 *
 * FromCode and ToCode are status names without spaces (NEW on creation). version is the old
 * record's SystemModstamp in milliseconds, or CreatedDate on insert; together they identify the
 * save. sequence (added in Phase 5) is the event's position in the shipment's status history, so
 * the same transition repeated within one second (the stored precision of SystemModstamp) still
 * gets a key of its own. A workflow re-fire finds its first event as the latest one and writes
 * nothing; a partial-success retry runs after rollback, finds nothing and writes it again. Keys
 * stored before Phase 5 have no sequence and are left as they are. If an event cannot be written, the shipment row gets an
 * error, so the status change is rolled back with it.
 *
 * recordEvents is the API for operational events (location updates, hub scans) from users and
 * integrations.
 */
public with sharing class TrackingService {
    public static final String SOURCE_MANUAL = 'Manual';
    public static final String SOURCE_APEX = 'Apex Service';
    public static final String REQUEST_INVALID = 'REQUEST_INVALID';
    public static final String STATUS_EVENT_NOT_ALLOWED = 'STATUS_EVENT_NOT_ALLOWED';
    public static final String SHIPMENT_NOT_FOUND = 'SHIPMENT_NOT_FOUND';
    public static final String OPERATION_FAILED = 'OPERATION_FAILED';
    public static final String STATUS_EVENTS_TRIGGER_ONLY = 'STATUS_EVENTS_TRIGGER_ONLY';
    @TestVisible
    private static final String CREATION_CODE = 'NEW';
    @TestVisible
    private static final String EXTERNAL_KEY_PREFIX = 'EXT:';
    /** Event types reserved for status changes besides the statuses themselves. */
    private static final Set<String> RESERVED_EVENT_TYPES = new Set<String>{ 'Created' };
    private static final String ON_HOLD = 'On Hold';
    private static final String CANCELLED = 'Cancelled';
    private static final Integer KEY_MAX_LENGTH = 80;
    private static final String STATUS_CONTEXT = 'TrackingService.recordStatusEvents';
    private static final String EVENTS_CONTEXT = 'TrackingService.recordEvents';

    /** Test seam for the clock. Lets a test force a future timestamp so the event insert fails validation. */
    @TestVisible
    private static Datetime nowOverride;

    private final ShipmentStatusPolicy policy;

    public TrackingService() {
        this(new ShipmentStatusPolicy());
    }

    @TestVisible
    private TrackingService(ShipmentStatusPolicy policy) {
        this.policy = policy;
    }

    /* ------------------------------------------------------------------ */
    /* Status events                                                       */
    /* ------------------------------------------------------------------ */

    /**
     * Records one event per allowed status change of the shipments in the current trigger. Costs
     * no SOQL or DML when no status changed; otherwise 1 query and 1 insert for the whole batch.
     *
     * Takes no arguments on purpose. It reads Trigger.new and Trigger.oldMap itself and refuses to
     * run anywhere except a Shipment__c after insert or after update trigger. Status history is
     * written without sharing, so a caller must never be able to supply its own "before" and
     * "after" records: that would let code expose an entry point that fabricates history for a
     * shipment that never changed (Phase 2 follow-up F1).
     */
    public void recordStatusEvents() {
        if (!isShipmentAfterSaveTrigger()) {
            throw new AuthorizationException(Label.eLogix_Access_Denied).withCode(STATUS_EVENTS_TRIGGER_ONLY);
        }
        recordStatusEvents((List<Shipment__c>) Trigger.new, Trigger.isInsert ? null : (Map<Id, Shipment__c>) Trigger.oldMap);
    }

    private static Boolean isShipmentAfterSaveTrigger() {
        return Trigger.isExecuting &&
            Trigger.isAfter &&
            (Trigger.isInsert || Trigger.isUpdate) &&
            Trigger.new != null &&
            Trigger.new.getSObjectType() == Shipment__c.SObjectType;
    }

    private void recordStatusEvents(List<Shipment__c> newList, Map<Id, Shipment__c> oldById) {
        if (newList.isEmpty()) {
            return;
        }
        List<ShipmentStatusPolicy.Decision> decisions = oldById == null
            ? policy.evaluateCreation(newList)
            : policy.evaluateStatusChanges(newList, oldById);

        // The save identity ({shipmentId}:{From}>{To}:{previous version}) is the same when a workflow or
        // flow field update re-fires this trigger for the same save, but it can repeat for two real
        // saves of the same transition within one second (SystemModstamp is stored to the second).
        // The key therefore adds a per-shipment sequence: the event's position in the shipment's
        // status history. With T status events stored, a save writes identity:(T+1). A re-fire of the
        // same save finds its first event as the latest one, identity:T, and writes nothing; a later
        // save of the same transition comes after at least one other transition, so its key differs.
        // Sequences are taken while this save holds the shipment's row lock, so concurrent saves of a
        // shipment cannot share one, and the unique index on Event_Key__c remains the backstop.
        // Stored keys are never rewritten.
        Map<Id, String> identityByShipment = new Map<Id, String>();
        Map<Id, ShipmentStatusPolicy.Decision> decisionByShipment = new Map<Id, ShipmentStatusPolicy.Decision>();
        for (ShipmentStatusPolicy.Decision decision : decisions) {
            if (!decision.requiresTrackingEvent()) {
                continue;
            }
            Shipment__c record = newList[decision.index];
            Shipment__c previous = oldById == null ? null : oldById.get(record.Id);
            identityByShipment.put(record.Id, statusEventKey(record, previous, decision));
            decisionByShipment.put(record.Id, decision);
        }
        if (identityByShipment.isEmpty()) {
            return;
        }

        TrackingEventSelector selector = new TrackingEventSelector();
        Map<Id, Integer> stored = selector.countStatusEvents(identityByShipment.keySet());
        Map<Id, String> recordedKey = new Map<Id, String>();
        Map<Id, String> nextKey = new Map<Id, String>();
        Set<String> candidates = new Set<String>();
        for (Id shipmentId : identityByShipment.keySet()) {
            Integer count = stored.containsKey(shipmentId) ? stored.get(shipmentId) : 0;
            String identity = identityByShipment.get(shipmentId);
            recordedKey.put(shipmentId, sequencedKey(identity, count));
            nextKey.put(shipmentId, sequencedKey(identity, count + 1));
            candidates.add(recordedKey.get(shipmentId));
            candidates.add(nextKey.get(shipmentId));
        }
        Set<String> existingKeys = selector.selectExistingKeys(candidates);
        List<Tracking_Event__c> toInsert = new List<Tracking_Event__c>();
        List<Shipment__c> owners = new List<Shipment__c>();
        Integer skipped = 0;
        for (Id shipmentId : identityByShipment.keySet()) {
            String key = nextKey.get(shipmentId);
            if (existingKeys.contains(recordedKey.get(shipmentId)) || existingKeys.contains(key)) {
                skipped++; // this save's event is already recorded (re-fired trigger)
                continue;
            }
            ShipmentStatusPolicy.Decision decision = decisionByShipment.get(shipmentId);
            Shipment__c record = newList[decision.index];
            toInsert.add(buildStatusEvent(record, decision, key));
            owners.add(record);
        }
        if (toInsert.isEmpty()) {
            Logger.debug(STATUS_CONTEXT, 'All ' + skipped + ' status events already recorded; nothing to insert.');
            return;
        }

        List<Database.SaveResult> results = new Writer().insertEvents(toInsert);
        Integer failures = 0;
        for (Integer i = 0; i < results.size(); i++) {
            if (!results[i].isSuccess()) {
                failures++;
                owners[i].addError(Label.eLogix_Tracking_Event_Failed);
                Logger.error(STATUS_CONTEXT, 'Tracking event insert failed for shipment ' + owners[i].Id + ' status=' + firstStatusCode(results[i]), null);
            }
        }
        Logger.debug(STATUS_CONTEXT, 'inserted=' + (toInsert.size() - failures) + ' skipped=' + skipped + ' failed=' + failures);
    }

    /** The save identity: {shipmentId}:{FromCode}>{ToCode}:{version} (the whole key before Phase 5). */
    @TestVisible
    private static String statusEventKey(Shipment__c record, Shipment__c previous, ShipmentStatusPolicy.Decision decision) {
        Datetime version = previous == null ? record.CreatedDate : previous.SystemModstamp;
        return String.valueOf(record.Id) +
            ':' +
            statusCode(decision.fromStatus) +
            '>' +
            statusCode(decision.toStatus) +
            ':' +
            (version == null ? '0' : String.valueOf(version.getTime()));
    }

    /** The stored key: the save identity followed by the per-shipment sequence. */
    @TestVisible
    private static String sequencedKey(String identity, Integer sequence) {
        return identity + ':' + sequence;
    }

    private static String statusCode(String status) {
        return String.isBlank(status) ? CREATION_CODE : status.deleteWhitespace();
    }

    private static Tracking_Event__c buildStatusEvent(Shipment__c record, ShipmentStatusPolicy.Decision decision, String key) {
        return new Tracking_Event__c(
            Shipment__c = record.Id,
            Event_Type__c = decision.trackingEventType,
            Event_Timestamp__c = now(),
            From_Status__c = decision.fromStatus,
            To_Status__c = decision.toStatus,
            Source__c = currentSource(),
            Event_Key__c = key,
            Remarks__c = statusRemarks(record, decision)
        );
    }

    /** Override note, then the hold or cancellation reason the user entered. */
    private static String statusRemarks(Shipment__c record, ShipmentStatusPolicy.Decision decision) {
        List<String> parts = new List<String>();
        if (decision.outcome == ShipmentStatusPolicy.Outcome.ALLOWED_BY_OVERRIDE) {
            parts.add(String.format(Label.eLogix_Status_Override_Remark, new List<Object>{ decision.overriddenReasonCode }));
        }
        if (ON_HOLD.equals(decision.toStatus) && String.isNotBlank(record.Hold_Reason__c)) {
            parts.add(record.Hold_Reason__c);
        } else if (CANCELLED.equals(decision.toStatus) && String.isNotBlank(record.Cancellation_Reason__c)) {
            parts.add(record.Cancellation_Reason__c);
        }
        return parts.isEmpty() ? null : fit(String.join(parts, ' '), Tracking_Event__c.Remarks__c);
    }

    /** Manual when the change came from the Lightning or Visualforce UI, otherwise Apex Service. */
    private static String currentSource() {
        System.Quiddity quiddity = Request.getCurrent().getQuiddity();
        Boolean fromUserInterface =
            quiddity == System.Quiddity.AURA ||
            quiddity == System.Quiddity.VF ||
            quiddity == System.Quiddity.QUICK_ACTION;
        return fromUserInterface ? SOURCE_MANUAL : SOURCE_APEX;
    }

    /* ------------------------------------------------------------------ */
    /* Operational events                                                  */
    /* ------------------------------------------------------------------ */

    /**
     * Records operational events. Per-request results; requests whose external event id was
     * already recorded are skipped and reported as success (idempotent replay). When an event is
     * newer than the shipment's Latest_Tracking_Timestamp__c, the shipment's tracking summary is
     * updated in the same transaction.
     *
     * Throws AuthorizationException when the user cannot create tracking events at all.
     */
    public ServiceResult recordEvents(List<TrackingEventRequest> requests) {
        ServiceResult result = new ServiceResult();
        if (requests == null || requests.isEmpty()) {
            return result;
        }
        if (!Schema.SObjectType.Tracking_Event__c.isCreateable()) {
            throw new AuthorizationException(Label.eLogix_Access_Denied).withCode(AuthorizationException.ACCESS_DENIED);
        }

        // 1. Validate requests without touching the database.
        Set<String> reservedTypes = ShipmentStatusPolicy.validStatuses();
        reservedTypes.addAll(RESERVED_EVENT_TYPES);
        Set<String> eventTypes = ShipmentStatusPolicy.validTrackingEventTypes();
        Set<String> sources = activeValues(Tracking_Event__c.Source__c);
        Set<Id> shipmentIds = new Set<Id>();
        List<Integer> candidateIndexes = new List<Integer>();
        for (Integer i = 0; i < requests.size(); i++) {
            TrackingEventRequest request = requests[i];
            if (!isWellFormed(request, eventTypes, sources)) {
                result.addError(REQUEST_INVALID, String.format(Label.eLogix_Request_Invalid, new List<Object>{ i + 1 }), i, request?.shipmentId);
            } else if (reservedTypes.contains(request.eventType)) {
                result.addError(
                    STATUS_EVENT_NOT_ALLOWED,
                    String.format(Label.eLogix_Tracking_Status_Event_Not_Allowed, new List<Object>{ request.eventType }),
                    i,
                    request.shipmentId
                );
            } else {
                shipmentIds.add(request.shipmentId);
                candidateIndexes.add(i);
            }
        }
        if (candidateIndexes.isEmpty()) {
            return result;
        }

        // 2. Authorize per shipment: the user must be able to read it (user mode). Lock it so that
        //    concurrent events compare against a current tracking summary.
        Map<Id, Shipment__c> shipments = new ShipmentSelector().selectTrackingSummaryForUpdate(shipmentIds);

        // 3. Build events; collapse duplicate external ids within the batch.
        List<Tracking_Event__c> events = new List<Tracking_Event__c>();
        List<Integer> eventRequestIndexes = new List<Integer>();
        Set<String> batchKeys = new Set<String>();
        for (Integer i : candidateIndexes) {
            TrackingEventRequest request = requests[i];
            if (!shipments.containsKey(request.shipmentId)) {
                result.addError(
                    SHIPMENT_NOT_FOUND,
                    String.format(Label.eLogix_Tracking_Shipment_Not_Found, new List<Object>{ request.shipmentId }),
                    i,
                    request.shipmentId
                );
                continue;
            }
            String source = String.isBlank(request.source) ? SOURCE_APEX : request.source;
            String key = String.isBlank(request.externalEventId) ? null : externalEventKey(source, request.externalEventId);
            if (key != null && !batchKeys.add(key)) {
                continue; // Same external event twice in one batch: record it once.
            }
            events.add(buildOperationalEvent(request, source, key));
            eventRequestIndexes.add(i);
        }

        // 4. Skip events already recorded by an earlier delivery of the same message.
        Set<String> existingKeys = new TrackingEventSelector().selectExistingKeys(batchKeys);
        List<Tracking_Event__c> toInsert = new List<Tracking_Event__c>();
        List<Integer> insertRequestIndexes = new List<Integer>();
        for (Integer j = 0; j < events.size(); j++) {
            if (events[j].Event_Key__c == null || !existingKeys.contains(events[j].Event_Key__c)) {
                toInsert.add(events[j]);
                insertRequestIndexes.add(eventRequestIndexes[j]);
            }
        }
        if (toInsert.isEmpty()) {
            return result;
        }

        // 5. Insert events and update the tracking summary together, or not at all.
        Savepoint savepoint = Database.setSavepoint();
        Writer writer = new Writer();
        List<Database.SaveResult> saveResults = writer.insertEvents(toInsert);
        List<Id> insertedIds = new List<Id>();
        List<Integer> insertedRequestIndexes = new List<Integer>();
        Map<Id, Shipment__c> summaryUpdates = new Map<Id, Shipment__c>();
        for (Integer j = 0; j < saveResults.size(); j++) {
            Integer requestIndex = insertRequestIndexes[j];
            if (!saveResults[j].isSuccess()) {
                for (Database.Error error : saveResults[j].getErrors()) {
                    result.addError(String.valueOf(error.getStatusCode()), error.getMessage(), requestIndex, toInsert[j].Shipment__c);
                }
                continue;
            }
            insertedIds.add(saveResults[j].getId());
            insertedRequestIndexes.add(requestIndex);
            collectSummaryUpdate(toInsert[j], shipments.get(toInsert[j].Shipment__c), summaryUpdates);
        }

        try {
            writer.updateSummaries(summaryUpdates.values());
        } catch (Exception e) {
            Database.rollback(savepoint);
            String message = ExceptionHandler.toUserMessage(e, EVENTS_CONTEXT);
            for (Integer requestIndex : insertedRequestIndexes) {
                result.addError(OPERATION_FAILED, message, requestIndex, requests[requestIndex].shipmentId);
            }
            return result;
        }
        for (Id eventId : insertedIds) {
            result.addRecordId(eventId);
        }
        Logger.info(EVENTS_CONTEXT, 'requested=' + requests.size() + ' inserted=' + insertedIds.size() + ' errors=' + result.errors.size());
        return result;
    }

    private static Boolean isWellFormed(TrackingEventRequest request, Set<String> eventTypes, Set<String> sources) {
        return request != null &&
            request.shipmentId != null &&
            request.shipmentId.getSObjectType() == Shipment__c.SObjectType &&
            String.isNotBlank(request.eventType) &&
            eventTypes.contains(request.eventType) &&
            (String.isBlank(request.source) || sources.contains(request.source));
    }

    /** EXT:{source}:{externalId}; hashed when longer than Event_Key__c allows. */
    @TestVisible
    private static String externalEventKey(String source, String externalEventId) {
        String key = EXTERNAL_KEY_PREFIX + source.deleteWhitespace() + ':' + externalEventId.trim();
        if (key.length() <= KEY_MAX_LENGTH) {
            return key;
        }
        return EXTERNAL_KEY_PREFIX + EncodingUtil.convertToHex(Crypto.generateDigest('SHA-256', Blob.valueOf(key)));
    }

    private static Tracking_Event__c buildOperationalEvent(TrackingEventRequest request, String source, String key) {
        return new Tracking_Event__c(
            Shipment__c = request.shipmentId,
            Event_Type__c = request.eventType,
            Event_Timestamp__c = request.eventTimestamp == null ? now() : request.eventTimestamp,
            Location__c = String.isBlank(request.location) ? null : fit(request.location.trim(), Tracking_Event__c.Location__c),
            Latitude__c = request.latitude,
            Longitude__c = request.longitude,
            Source__c = source,
            Event_Key__c = key,
            Remarks__c = String.isBlank(request.remarks) ? null : fit(request.remarks, Tracking_Event__c.Remarks__c)
        );
    }

    /** Keeps, per shipment, the newest event that is newer than the stored summary. */
    private static void collectSummaryUpdate(Tracking_Event__c event, Shipment__c shipment, Map<Id, Shipment__c> summaryUpdates) {
        Shipment__c pending = summaryUpdates.get(shipment.Id);
        Datetime latest = pending != null ? pending.Latest_Tracking_Timestamp__c : shipment.Latest_Tracking_Timestamp__c;
        if (latest != null && event.Event_Timestamp__c <= latest) {
            return;
        }
        Shipment__c summary = new Shipment__c(Id = shipment.Id, Latest_Tracking_Timestamp__c = event.Event_Timestamp__c);
        if (String.isNotBlank(event.Location__c)) {
            summary.Latest_Location__c = fit(event.Location__c, Shipment__c.Latest_Location__c);
        } else if (pending != null && pending.Latest_Location__c != null) {
            summary.Latest_Location__c = pending.Latest_Location__c;
        }
        summaryUpdates.put(shipment.Id, summary);
    }

    /* ------------------------------------------------------------------ */
    /* Helpers                                                             */
    /* ------------------------------------------------------------------ */

    private static Datetime now() {
        return nowOverride != null ? nowOverride : System.now();
    }

    private static String fit(String value, Schema.SObjectField field) {
        return value.abbreviate(field.getDescribe().getLength());
    }

    private static String firstStatusCode(Database.SaveResult result) {
        return result.getErrors().isEmpty() ? 'UNKNOWN' : String.valueOf(result.getErrors()[0].getStatusCode());
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

    /**
     * Writes tracking events and the shipment tracking summary in system mode, without sharing.
     *
     * Justification (docs/APEX_ARCHITECTURE.md section 6): Event_Key__c, From_Status__c,
     * To_Status__c, Latest_Location__c and Latest_Tracking_Timestamp__c are protected fields,
     * read-only for every role, because they are an audit trail and a derived summary. Every
     * caller authorizes first: status events follow a shipment save the user was allowed to make,
     * and recordEvents checks Tracking_Event__c create access and reads each shipment in user mode.
     * Without sharing lets a user with read access to a shipment (for example a Logistics Manager
     * with View All) record events on it; the master-detail parent would otherwise demand edit
     * access.
     */
    private without sharing class Writer {
        public List<Database.SaveResult> insertEvents(List<Tracking_Event__c> events) {
            return Database.insert(events, false, AccessLevel.SYSTEM_MODE);
        }

        public void updateSummaries(List<Shipment__c> shipments) {
            if (!shipments.isEmpty()) {
                Database.update(shipments, true, AccessLevel.SYSTEM_MODE);
            }
        }
    }
}
