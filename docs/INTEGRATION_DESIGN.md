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
