/**
 * Asynchronous GPS ingestion (Phase 6). Both the REST endpoint and the mock provider submit a batch
 * here; each run processes the pings through GpsIngestionService and writes the batch's single
 * integration log (G5).
 *
 * Retry: only the pings that hit a record lock are re-enqueued, as a new job for the same batch,
 * after 1, 2 and 4 minutes (2^attempt), up to GPS_Max_Retries. Pings still locked after the last
 * retry become Dead Letter logs. Retries are idempotent: a ping already stored is never stored
 * twice (TrackingService event key EXT:GPSIntegration:{messageId}). Chain depth is at most
 * 1 + GPS_Max_Retries (4 by default; Developer Edition allows 5).
 */
public with sharing class GpsIngestionJob implements Queueable {
    public static final String INGEST_PERMISSION = 'eLogix_Ingest_GPS';
    public static final Integer MAX_PINGS = 200;
    private static final String CONTEXT = 'GpsIngestionJob';

    /** Enqueues retries; tests substitute a recorder because queueables cannot chain in tests. */
    public virtual class Enqueuer {
        public virtual void enqueue(GpsIngestionJob job, Integer delayMinutes) {
            System.enqueueJob(job, delayMinutes);
        }
    }

    @TestVisible
    private static Enqueuer enqueuer = new Enqueuer();

    @TestVisible
    private final String batchId;
    @TestVisible
    private final List<GpsPing> pings;
    @TestVisible
    private final Integer attempt;

    public GpsIngestionJob(String batchId, List<GpsPing> pings, Integer attempt) {
        this.batchId = batchId;
        this.pings = pings;
        this.attempt = attempt;
    }

    /**
     * Accepts a batch of 1..MAX_PINGS pings for asynchronous processing and returns its batch id
     * (the integration log's Correlation_Id__c). Requires the eLogix_Ingest_GPS custom permission.
     */
    public static String submit(List<GpsPing> pings) {
        if (!PermissionService.hasPermission(INGEST_PERMISSION)) {
            throw new AuthorizationException(Label.eLogix_GPS_Access_Denied).withCode(AuthorizationException.ACCESS_DENIED);
        }
        if (pings == null || pings.isEmpty() || pings.size() > MAX_PINGS) {
            throw new IllegalArgumentException(String.format(Label.eLogix_GPS_Invalid_Payload, new List<Object>{ MAX_PINGS }));
        }
        String batchId = UUID.randomUUID().toString();
        System.enqueueJob(new GpsIngestionJob(batchId, pings, 0));
        return batchId;
    }

    // The parameter is not named "context": Apex names are case-insensitive, and it would hide CONTEXT.
    public void execute(QueueableContext queueableContext) {
        GpsIngestionService service = new GpsIngestionService();
        GpsIngestionService.Outcome outcome;
        try {
            outcome = service.ingest(pings);
        } catch (Exception e) {
            // Unexpected failure: nothing was stored (TrackingService rolls back its own writes).
            Logger.error(CONTEXT, 'GPS batch ' + batchId + ' failed on attempt ' + attempt, e);
            outcome = new GpsIngestionService.Outcome();
            outcome.counts.put(GpsIngestionService.RECEIVED, pings.size());
            outcome.counts.put(GpsIngestionService.FAILED, pings.size());
            outcome.failures.put('*', ExceptionHandler.toUserMessage(e, CONTEXT));
        }

        List<GpsPing> exhausted = new List<GpsPing>();
        Boolean retrying = false;
        if (!outcome.retryable.isEmpty()) {
            Integer maxRetries = SettingsService.getNumber('GPS_Max_Retries').intValue();
            if (attempt < maxRetries) {
                enqueuer.enqueue(new GpsIngestionJob(batchId, outcome.retryable, attempt + 1), backoffMinutes(attempt));
                retrying = true;
            } else {
                exhausted = outcome.retryable;
            }
        }
        service.logBatch(batchId, attempt, outcome, retrying, exhausted);
    }

    /** 1, 2, 4 ... minutes before retry number attempt + 1; capped at the platform maximum of 10. */
    @TestVisible
    private static Integer backoffMinutes(Integer attempt) {
        return Math.min(10, Math.pow(2, attempt).intValue());
    }
}
