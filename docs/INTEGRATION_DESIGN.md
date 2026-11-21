# eLogix ERP - Integration Design

Status: **design only**, apart from `Integration_Log__c`, which is deployed (Phase 1). Implementation is Phase 6.

The MVP works without any paid or live external service (CLAUDE.md section 11). Every integration has an interface, a mock implementation used by default and in tests, and a Named Credential placeholder for a real adapter.

## 1. Integrations

| Integration | Interface | Direction | Mock behaviour | Used by |
|---|---|---|---|---|
| GPS provider | `IGpsProvider` | Inbound pings, outbound position poll | Returns positions interpolated along the route's stops | `TrackingService` (creates `Location Update` events, idempotent through `Event_Key__c`) |
| Payment gateway | `IPaymentGateway` | Outbound payment link; inbound callback | Deterministic success, or failure for amounts ending in .13 | `PaymentService` (idempotent through `Payment__c.Idempotency_Key__c`) |
| External accounting ERP | `IAccountingSync` | Outbound invoice and payment posting | Returns a synthetic document number | `InvoiceService` |
| Mapping and distance | `IDistanceProvider` | Outbound | Distance from `Route__c`; otherwise from a small lane table | `FreightCalculationService` |
| Notifications | `INotificationProvider` | Outbound SMS and email | Writes an `Integration_Log__c` row only | Status-change subscribers |

## 2. Cross-cutting design

- **Callouts** run in Queueable Apex with `Database.AllowsCallouts`, never in triggers.
- **Timeouts.** A 10 s default per adapter, configurable through `eLogix_Setting__mdt`.
- **Retries.** Exponential backoff for `Timeout`, `Rate Limit` and `Server Error` only. Maximum retries come from settings. After the last retry, the log status becomes `Dead Letter`.
- **Idempotency.** Every outbound request carries `Integration_Log__c.Idempotency_Key__c` (unique). A retry reuses the key, and inbound callbacks are deduplicated on business keys.
- **Error categories.** `Error_Category__c` takes the values None, Timeout, Authentication, Validation, Rate Limit, Server Error, Client Error, Serialization and Unknown.
- **Logging hygiene.** Payloads are scrubbed of tokens and personal data before they are stored. `Correlation_Id__c` groups all rows of one business transaction. Successful logs are purged by a batch job to protect the 5 MB data storage.
- **Named Credentials** (`eLogix_GPS`, `eLogix_Payments`, `eLogix_Accounting`, `eLogix_Maps`, `eLogix_Notify`) are created only with placeholder endpoints. No live connectivity is invented.

## 3. GPS ingestion (implemented in Phase 6; robustness reviewed in Phase 2 follow-up F5)

`TrackingService.recordEvents` is the only write path for GPS pings. Two Phase 6 requirements came out of the Phase 2 review; detail and acceptance criteria are in [TRACKING_IMPLEMENTATION.md](TRACKING_IMPLEMENTATION.md) section 5.

1. **No batch-wide rollback.** One shipment that fails its summary update must not discard the pings of other shipments in the same call. Summaries are updated with partial success, and only the failed shipment's new events are compensated.
2. **Lock contention is retryable, not fatal.**
   - Pings are processed asynchronously, through a Queueable or a platform event subscriber that consumes the inbound queue, never inline with the provider's request.
   - Pings are grouped per shipment and ordered by timestamp.
   - A row-lock timeout becomes the per-request code `RECORD_LOCKED`, which is retried with exponential backoff under the policy in section 2. After the last attempt, the `Integration_Log__c` row becomes `Dead Letter`.
   - Replays are safe because each ping carries its provider message id as `externalEventId`, which deduplicates through `Event_Key__c` (`EXT:{source}:{id}`).

### 3.1 Phase 6 implementation

Classes are in `classes/integrations/`.

```
Provider -- POST /services/apexrest/elogix/gps/v1/pings --> GpsPingResource   (403 without eLogix_Ingest_GPS; 400 bad body; 202 {batchId, accepted})
MockGpsProvider.currentPositions() ---------------------+        |
                                                        v        v
                                          GpsIngestionJob.submit(pings)   (permission check, 1..200 pings, new batch id)
                                                        |  Queueable
                                                        v
                                          GpsIngestionService.ingest --> TrackingService.recordEvents ('Location Update', source 'GPS Integration')
                                                        |
                                          locked subset -> re-enqueued after 1, 2, 4 min -> Dead Letter logs
```

| Step | Rule | Configured by |
|---|---|---|
| Validate | Latitude and longitude in range, not (0, 0). messageId of at most 40 characters. No more than `GPS_Max_Future_Skew_Minutes` (5) ahead. Not older than `GPS_Max_Ping_Age_Hours` (24): older pings are counted `STALE`. A repeated messageId within a batch is counted `DUPLICATE`. | `eLogix_Setting__mdt` |
| Map (G2, G4) | `Vehicle_Number__c` (unique, case-insensitive) -> its **Active** `Vehicle_Assignment__c` -> shipment. Unknown vehicles are counted `UNKNOWN_VEHICLE`; vehicles without an Active trip are counted `NO_ACTIVE_TRIP`. Both are rejected. | - |
| Throttle (G3) | Per shipment, in recorded-time order, against the last stored GPS location (one aggregate query and one row query per batch). A ping is stored only if at least `GPS_Min_Interval_Minutes` (15) have passed or the vehicle moved at least `GPS_Min_Distance_Km` (2, haversine). A throttled ping creates **no** tracking event and does **not** touch the shipment summary. | `eLogix_Setting__mdt` |
| Record | `TrackingService.recordEvents`. GPS never changes shipment status, because `Location Update` is not a status event. | - |
| Retry | Only `RECORD_LOCKED` pings are retried, as a new job for the same batch, after 2^attempt minutes (1, 2, 4), up to `GPS_Max_Retries` (3). Chain depth is 4, within the Developer Edition limit of 5. A ping that was already stored is never stored twice. | `eLogix_Setting__mdt` |
| Log (G5) | **One** `Integration_Log__c` per batch (`Idempotency_Key__c = GPS-BATCH:{batchId}`, `Correlation_Id__c = batchId`), upserted on every attempt. `Response_Payload__c` holds the counts (RECEIVED, STORED, THROTTLED, DUPLICATE, INVALID, STALE, UNKNOWN_VEHICLE, NO_ACTIVE_TRIP, FAILED, RECORD_LOCKED, DEAD_LETTER). Status is `Retrying` while a retry is pending, `Failed` if any ping was dead-lettered, otherwise `Success`. A **Dead Letter** row (`GPS-DL:{messageId}`, the ping in `Request_Payload__c`) is written only for pings that exhaust their retries. | - |

Non-lock failures of individual pings, such as a validation error on the shipment, are counted `FAILED`, listed in `Error_Message__c` and not retried.
