/**
 * GPS ping processing (Phase 6). Turns a batch of pings into Location Update tracking events through
 * the single tracking write path, TrackingService.recordEvents, and never changes a shipment status.
 *
 *   1. validate        coordinates in range and not (0, 0); recorded at most GPS_Max_Future_Skew_Minutes
 *                      ahead and at most GPS_Max_Ping_Age_Hours ago; messageId and vehicle present
 *   2. de-duplicate    the same messageId twice in a batch is processed once
 *   3. map             vehicle (unique Vehicle_Number__c) -> its Active assignment -> shipment;
 *                      pings for unknown vehicles or vehicles without an Active trip are rejected (G4)
 *   4. order           per shipment, by recorded time
 *   5. throttle (G3)   stored only if GPS_Min_Interval_Minutes have passed since the shipment's last
 *                      stored GPS location, or it moved GPS_Min_Distance_Km; throttled pings create
 *                      no tracking event and do not touch the shipment's latest-location summary
 *   6. record          TrackingService.recordEvents; the provider message id makes replays and
 *                      retries idempotent; RECORD_LOCKED results are returned for retry
 *
 * Reads run in user mode as the integration user (eLogix_GPS_Integration). Costs a fixed number of
 * queries per batch, never per ping.
 */
public with sharing class GpsIngestionService {
    public static final String SOURCE = 'GPS Integration';
    public static final String EVENT_TYPE = 'Location Update';
    public static final String INTEGRATION_NAME = 'GPS Ingestion';
    public static final String ENDPOINT = '/services/apexrest/elogix/gps/v1/pings';

    /** Outcome codes, counted per batch in the integration log. */
    public static final String RECEIVED = 'RECEIVED';
    public static final String STORED = 'STORED';
    public static final String THROTTLED = 'THROTTLED';
    public static final String DUPLICATE = 'DUPLICATE';
    public static final String INVALID = 'INVALID';
    public static final String STALE = 'STALE';
    public static final String UNKNOWN_VEHICLE = 'UNKNOWN_VEHICLE';
    public static final String NO_ACTIVE_TRIP = 'NO_ACTIVE_TRIP';
    public static final String FAILED = 'FAILED';
    public static final String RECORD_LOCKED = TrackingService.RECORD_LOCKED;
    public static final String DEAD_LETTER = 'DEAD_LETTER';

    private static final Integer MAX_MESSAGE_ID_LENGTH = 40;
    private static final Decimal EARTH_RADIUS_KM = 6371;

    public class Outcome {
        public Map<String, Integer> counts = new Map<String, Integer>();
        /** Pings that hit a record lock; retried by GpsIngestionJob. */
        public List<GpsPing> retryable = new List<GpsPing>();
        /** messageId -> reason, for pings that failed for another reason (not retried). */
        public Map<String, String> failures = new Map<String, String>();

        public void count(String code) {
            counts.put(code, (counts.containsKey(code) ? counts.get(code) : 0) + 1);
        }
    }

    /** A ping that passed validation and mapping, sortable by shipment and recorded time. */
    private class Candidate implements Comparable {
        GpsPing ping;
        Id shipmentId;

        Candidate(GpsPing ping, Id shipmentId) {
            this.ping = ping;
            this.shipmentId = shipmentId;
        }

        public Integer compareTo(Object other) {
            Candidate that = (Candidate) other;
            String a = String.valueOf(shipmentId);
            String b = String.valueOf(that.shipmentId);
            if (a != b) {
                return a < b ? -1 : 1;
            }
            Long t1 = ping.recordedAt.getTime();
            Long t2 = that.ping.recordedAt.getTime();
            return t1 == t2 ? 0 : (t1 < t2 ? -1 : 1);
        }
    }

    public Outcome ingest(List<GpsPing> pings) {
        Outcome outcome = new Outcome();
        if (pings == null || pings.isEmpty()) {
            return outcome;
        }
        Datetime now = System.now();
        Datetime oldest = now.addMinutes(-(SettingsService.getNumber('GPS_Max_Ping_Age_Hours') * 60).intValue());
        Datetime newest = now.addMinutes(SettingsService.getNumber('GPS_Max_Future_Skew_Minutes').intValue());
        Integer intervalMinutes = SettingsService.getNumber('GPS_Min_Interval_Minutes').intValue();
        Decimal minDistanceKm = SettingsService.getNumber('GPS_Min_Distance_Km');

        // 1-2. Validate and de-duplicate.
        List<GpsPing> valid = new List<GpsPing>();
        Set<String> seen = new Set<String>();
        Set<String> vehicleNumbers = new Set<String>();
        for (GpsPing ping : pings) {
            outcome.count(RECEIVED);
            String problem = validate(ping, oldest, newest);
            if (problem != null) {
                outcome.count(problem);
            } else if (!seen.add(ping.messageId)) {
                outcome.count(DUPLICATE);
            } else {
                valid.add(ping);
                vehicleNumbers.add(ping.vehicleNumber.trim().toUpperCase());
            }
        }

        // 3. Map vehicle -> Active assignment -> shipment.
        Map<String, Id> shipmentByVehicle = activeShipmentsByVehicle(vehicleNumbers);
        Set<String> knownVehicles = shipmentByVehicle.keySet().containsAll(vehicleNumbers) ? vehicleNumbers : selectKnownVehicles(vehicleNumbers);
        List<Candidate> candidates = new List<Candidate>();
        for (GpsPing ping : valid) {
            String vehicle = ping.vehicleNumber.trim().toUpperCase();
            Id shipmentId = shipmentByVehicle.get(vehicle);
            if (shipmentId != null) {
                candidates.add(new Candidate(ping, shipmentId));
            } else {
                outcome.count(knownVehicles.contains(vehicle) ? NO_ACTIVE_TRIP : UNKNOWN_VEHICLE);
            }
        }
        if (candidates.isEmpty()) {
            return outcome;
        }

        // 4-5. Order per shipment and throttle against the last stored GPS location.
        candidates.sort();
        Set<Id> shipmentIds = new Set<Id>();
        for (Candidate candidate : candidates) {
            shipmentIds.add(candidate.shipmentId);
        }
        Map<Id, Tracking_Event__c> lastStored = lastStoredLocations(shipmentIds);
        List<Candidate> toStore = new List<Candidate>();
        for (Candidate candidate : candidates) {
            Tracking_Event__c last = lastStored.get(candidate.shipmentId);
            if (last == null || farEnough(last, candidate.ping, intervalMinutes, minDistanceKm)) {
                toStore.add(candidate);
                lastStored.put(
                    candidate.shipmentId,
                    new Tracking_Event__c(
                        Event_Timestamp__c = candidate.ping.recordedAt,
                        Latitude__c = candidate.ping.latitude,
                        Longitude__c = candidate.ping.longitude
                    )
                );
            } else {
                outcome.count(THROTTLED);
            }
        }
        if (toStore.isEmpty()) {
            return outcome;
        }

        // 6. Record through the single tracking write path.
        List<TrackingEventRequest> requests = new List<TrackingEventRequest>();
        for (Candidate candidate : toStore) {
            requests.add(toRequest(candidate));
        }
        ServiceResult result = new TrackingService().recordEvents(requests);
        for (Integer i = 0; i < toStore.size(); i++) {
            List<ServiceResult.ServiceError> errors = result.errorsFor(i);
            if (errors.isEmpty()) {
                outcome.count(STORED); // includes a replay of an already stored ping: no second event
            } else if (errors[0].code == RECORD_LOCKED) {
                outcome.count(RECORD_LOCKED);
                outcome.retryable.add(toStore[i].ping);
            } else {
                outcome.count(FAILED);
                outcome.failures.put(toStore[i].ping.messageId, errors[0].code + ': ' + errors[0].message);
            }
        }
        return outcome;
    }

    /* ------------------------------------------------------------------ */
    /* Batch log (G5): one Integration_Log__c per batch, Dead Letters only  */
    /* ------------------------------------------------------------------ */

    /**
     * Upserts the batch's single log row (Idempotency_Key__c GPS-BATCH:{batchId}), accumulating the
     * counts of every attempt: a retry replaces the previous RECORD_LOCKED count with its own
     * outcome. Status: Retrying while a retry is pending; Failed if any ping was dead-lettered;
     * otherwise Success. Inserts one Dead Letter row per exhausted ping.
     */
    public void logBatch(String batchId, Integer attempt, Outcome outcome, Boolean retrying, List<GpsPing> exhausted) {
        String key = 'GPS-BATCH:' + batchId;
        Map<String, Integer> counts = new Map<String, Integer>();
        String previousFailures;
        for (Integration_Log__c existing : [
            SELECT Response_Payload__c, Error_Message__c
            FROM Integration_Log__c
            WHERE Idempotency_Key__c = :key
            WITH USER_MODE
            LIMIT 1
        ]) {
            previousFailures = existing.Error_Message__c;
            if (String.isNotBlank(existing.Response_Payload__c)) {
                Map<String, Object> stored = (Map<String, Object>) JSON.deserializeUntyped(existing.Response_Payload__c);
                for (String code : stored.keySet()) {
                    counts.put(code, (Integer) stored.get(code));
                }
            }
        }
        if (attempt > 0) {
            counts.remove(RECORD_LOCKED); // the previously locked pings are this attempt's input
        }
        for (String code : outcome.counts.keySet()) {
            if (attempt > 0 && code == RECEIVED) {
                continue; // a retry re-processes pings already counted as received
            }
            counts.put(code, (counts.containsKey(code) ? counts.get(code) : 0) + outcome.counts.get(code));
        }
        if (!exhausted.isEmpty()) {
            counts.remove(RECORD_LOCKED); // exhausted pings are reported as dead letters instead
            counts.put(DEAD_LETTER, exhausted.size());
        }
        Boolean deadLettered = counts.containsKey(DEAD_LETTER) && counts.get(DEAD_LETTER) > 0;

        List<Integration_Log__c> rows = new List<Integration_Log__c>{
            new Integration_Log__c(
                Idempotency_Key__c = key,
                Correlation_Id__c = batchId,
                Integration_Name__c = INTEGRATION_NAME,
                Direction__c = 'Inbound',
                Endpoint__c = ENDPOINT,
                HTTP_Method__c = 'POST',
                Status__c = retrying ? 'Retrying' : (deadLettered ? 'Failed' : 'Success'),
                Error_Category__c = deadLettered ? 'Timeout' : 'None',
                Retry_Count__c = attempt,
                Response_Payload__c = JSON.serialize(counts),
                Error_Message__c = outcome.failures.isEmpty() ? previousFailures : JSON.serialize(outcome.failures).left(2000),
                Log_Timestamp__c = System.now()
            )
        };
        for (GpsPing ping : exhausted) {
            rows.add(
                new Integration_Log__c(
                    Idempotency_Key__c = 'GPS-DL:' + ping.messageId, // one dead letter per ping, even if resubmitted
                    Correlation_Id__c = batchId,
                    Integration_Name__c = INTEGRATION_NAME,
                    Direction__c = 'Inbound',
                    Endpoint__c = ENDPOINT,
                    HTTP_Method__c = 'POST',
                    Status__c = 'Dead Letter',
                    Error_Category__c = 'Timeout',
                    Retry_Count__c = attempt,
                    Request_Payload__c = JSON.serialize(ping),
                    Error_Message__c = Label.eLogix_Tracking_Record_Locked,
                    Log_Timestamp__c = System.now()
                )
            );
        }
        Database.upsert(rows, Integration_Log__c.Idempotency_Key__c, true, AccessLevel.USER_MODE);
    }

    /* ------------------------------------------------------------------ */
    /* Helpers                                                             */
    /* ------------------------------------------------------------------ */

    private static String validate(GpsPing ping, Datetime oldest, Datetime newest) {
        if (
            ping == null ||
            String.isBlank(ping.messageId) ||
            ping.messageId.length() > MAX_MESSAGE_ID_LENGTH ||
            String.isBlank(ping.vehicleNumber) ||
            ping.latitude == null ||
            ping.longitude == null ||
            ping.recordedAt == null
        ) {
            return INVALID;
        }
        if (Math.abs(ping.latitude) > 90 || Math.abs(ping.longitude) > 180 || (ping.latitude == 0 && ping.longitude == 0)) {
            return INVALID;
        }
        if (ping.recordedAt > newest) {
            return INVALID; // device clock ahead of the allowed skew
        }
        if (ping.recordedAt < oldest) {
            return STALE;
        }
        return null;
    }

    private static Map<String, Id> activeShipmentsByVehicle(Set<String> vehicleNumbers) {
        Map<String, Id> byVehicle = new Map<String, Id>();
        if (vehicleNumbers.isEmpty()) {
            return byVehicle;
        }
        for (Vehicle_Assignment__c trip : [
            SELECT Shipment__c, Vehicle__r.Vehicle_Number__c
            FROM Vehicle_Assignment__c
            WHERE Status__c = 'Active' AND Shipment__c != NULL AND Vehicle__r.Vehicle_Number__c IN :vehicleNumbers
            WITH USER_MODE
        ]) {
            byVehicle.put(trip.Vehicle__r.Vehicle_Number__c.toUpperCase(), trip.Shipment__c);
        }
        return byVehicle;
    }

    /** Only queried when some pings have no Active trip: tells unknown vehicles from idle ones. */
    private static Set<String> selectKnownVehicles(Set<String> vehicleNumbers) {
        Set<String> known = new Set<String>();
        for (Vehicle__c vehicle : [SELECT Vehicle_Number__c FROM Vehicle__c WHERE Vehicle_Number__c IN :vehicleNumbers WITH USER_MODE]) {
            known.add(vehicle.Vehicle_Number__c.toUpperCase());
        }
        return known;
    }

    /** The latest stored GPS location of each shipment: one aggregate query and one row query. */
    private static Map<Id, Tracking_Event__c> lastStoredLocations(Set<Id> shipmentIds) {
        Map<Id, Datetime> latest = new Map<Id, Datetime>();
        for (AggregateResult row : [
            SELECT Shipment__c shipmentId, MAX(Event_Timestamp__c) latest
            FROM Tracking_Event__c
            WHERE Shipment__c IN :shipmentIds AND Source__c = :SOURCE AND Latitude__c != NULL
            WITH USER_MODE
            GROUP BY Shipment__c
        ]) {
            latest.put((Id) row.get('shipmentId'), (Datetime) row.get('latest'));
        }
        Map<Id, Tracking_Event__c> result = new Map<Id, Tracking_Event__c>();
        if (latest.isEmpty()) {
            return result;
        }
        List<Datetime> times = latest.values();
        for (Tracking_Event__c event : [
            SELECT Shipment__c, Event_Timestamp__c, Latitude__c, Longitude__c
            FROM Tracking_Event__c
            WHERE Shipment__c IN :shipmentIds AND Source__c = :SOURCE AND Latitude__c != NULL AND Event_Timestamp__c IN :times
            WITH USER_MODE
        ]) {
            if (event.Event_Timestamp__c == latest.get(event.Shipment__c)) {
                result.put(event.Shipment__c, event);
            }
        }
        return result;
    }

    private static Boolean farEnough(Tracking_Event__c last, GpsPing ping, Integer intervalMinutes, Decimal minDistanceKm) {
        Long minutesApart = Math.abs(ping.recordedAt.getTime() - last.Event_Timestamp__c.getTime()) / 60000;
        return minutesApart >= intervalMinutes || distanceKm(last.Latitude__c, last.Longitude__c, ping.latitude, ping.longitude) >= minDistanceKm;
    }

    /** Great-circle distance (haversine). */
    @TestVisible
    private static Decimal distanceKm(Decimal lat1, Decimal lon1, Decimal lat2, Decimal lon2) {
        Double dLat = toRadians(lat2 - lat1);
        Double dLon = toRadians(lon2 - lon1);
        Double a = Math.sin(dLat / 2) * Math.sin(dLat / 2) +
            Math.cos(toRadians(lat1)) * Math.cos(toRadians(lat2)) * Math.sin(dLon / 2) * Math.sin(dLon / 2);
        return EARTH_RADIUS_KM * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
    }

    private static Double toRadians(Decimal degrees) {
        return degrees.doubleValue() * Math.PI / 180;
    }

    private static TrackingEventRequest toRequest(Candidate candidate) {
        GpsPing ping = candidate.ping;
        String location = String.isNotBlank(ping.location)
            ? ping.location
            : String.valueOf(ping.latitude.setScale(5)) + ', ' + String.valueOf(ping.longitude.setScale(5));
        TrackingEventRequest request = new TrackingEventRequest(candidate.shipmentId, EVENT_TYPE, location.left(255));
        request.latitude = ping.latitude;
        request.longitude = ping.longitude;
        request.eventTimestamp = ping.recordedAt;
        request.source = SOURCE;
        request.externalEventId = ping.messageId;
        return request;
    }
}
