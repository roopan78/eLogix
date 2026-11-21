/**
 * Simulated GPS provider (Phase 6, G1) so the MVP works without a paid service. For every vehicle on
 * an Active trip it reports a position interpolated between the shipment's origin and destination
 * cities by the elapsed fraction of the trip window. Shipments whose cities are not in the table are
 * skipped. Message ids are per vehicle and minute, so polling twice in a minute is idempotent.
 *
 * Usage (anonymous Apex, as a user with eLogix_Ingest_GPS):
 *   GpsIngestionJob.submit(new MockGpsProvider().currentPositions());
 */
public with sharing class MockGpsProvider implements IGpsProvider {
    /** City -> {latitude, longitude}. Matched as a case-insensitive substring of Origin__c / Destination__c. */
    private static final Map<String, List<Decimal>> CITIES = new Map<String, List<Decimal>>{
        'chennai' => new List<Decimal>{ 13.0827, 80.2707 },
        'bangalore' => new List<Decimal>{ 12.9716, 77.5946 },
        'bengaluru' => new List<Decimal>{ 12.9716, 77.5946 },
        'madurai' => new List<Decimal>{ 9.9252, 78.1198 },
        'coimbatore' => new List<Decimal>{ 11.0168, 76.9558 },
        'hyderabad' => new List<Decimal>{ 17.3850, 78.4867 },
        'mumbai' => new List<Decimal>{ 19.0760, 72.8777 }
    };

    @TestVisible
    private Datetime now = System.now();

    public List<GpsPing> currentPositions() {
        List<GpsPing> pings = new List<GpsPing>();
        Long minute = now.getTime() / 60000;
        for (Vehicle_Assignment__c trip : [
            SELECT Vehicle__r.Vehicle_Number__c, Assignment_Start__c, Assignment_End__c, Shipment__r.Origin__c, Shipment__r.Destination__c
            FROM Vehicle_Assignment__c
            WHERE Status__c = 'Active' AND Shipment__c != NULL
            WITH USER_MODE
            LIMIT 200
        ]) {
            List<Decimal> origin = locate(trip.Shipment__r.Origin__c);
            List<Decimal> destination = locate(trip.Shipment__r.Destination__c);
            if (origin == null || destination == null) {
                continue;
            }
            Decimal share = elapsedShare(trip.Assignment_Start__c, trip.Assignment_End__c);
            pings.add(
                new GpsPing(
                    'MOCK-' + trip.Vehicle__r.Vehicle_Number__c + '-' + minute,
                    trip.Vehicle__r.Vehicle_Number__c,
                    (origin[0] + (destination[0] - origin[0]) * share).setScale(6),
                    (origin[1] + (destination[1] - origin[1]) * share).setScale(6),
                    now
                )
            );
        }
        return pings;
    }

    private static List<Decimal> locate(String place) {
        if (String.isBlank(place)) {
            return null;
        }
        String lower = place.toLowerCase();
        for (String city : CITIES.keySet()) {
            if (lower.contains(city)) {
                return CITIES.get(city);
            }
        }
        return null;
    }

    /** Elapsed share of the trip window, 0..1; halfway when the window is unknown. */
    private Decimal elapsedShare(Datetime startsAt, Datetime endsAt) {
        if (startsAt == null || endsAt == null || endsAt <= startsAt) {
            return 0.5;
        }
        Decimal elapsed = now.getTime() - startsAt.getTime();
        Decimal total = endsAt.getTime() - startsAt.getTime();
        return Math.max(0, Math.min(1, elapsed / total));
    }
}
