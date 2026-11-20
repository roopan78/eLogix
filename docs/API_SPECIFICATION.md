# eLogix ERP - API Specification

Status: **conventions defined; no Apex API is deployed yet.** Signatures are added to this document as each service ships (Phase 2 onward).

## 1. Conventions for every service operation

| Convention | Rule |
|---|---|
| Bulk-first | Public service methods accept collections (`List<Id>` or `List<Request DTO>`) and return one result per input, in input order. |
| Result pattern | `ServiceResult<T>` carries `isSuccess`, `value`, `errors` (code, Custom Label message, field) and `recordId`. Partial success is allowed where documented. |
| Exceptions | Unexpected failures throw `ELogixException` subclasses (`ValidationException`, `AuthorizationException`, `ConcurrencyException`, `IntegrationException`). Controllers translate these into `AuraHandledException` with a safe message, and the full detail goes to the logger. |
| Authorization | Each operation documents the object access and custom permission it requires, and checks them before doing any work. |
| Idempotency | Operations that create business events accept or derive an idempotency key, and return the existing record when they are replayed. |
| Transactions | Each public operation is one logical transaction, with a savepoint and rollback on failure. |

## 2. Planned operations

| Service | Operation | Required access | Phase |
|---|---|---|---|
| `ShipmentService` | `changeStatus(List<StatusChangeRequest>)` (live). Creating a shipment from a request is `QuotationService.convertToShipment` (P3), from an accepted quotation only. | Shipment edit; transition permission from metadata | P2 |
| `TrackingService` | `recordEvents(List<TrackingEventRequest>)` | Tracking Event create | P2 |
| `FreightCalculationService` | `quote(List<FreightRequest>) → List<FreightBreakdown>`; static `quotationTotals(...)`, `isDiscountWithinThreshold(...)`, `discountThresholdPercent()` (live) | Rate Card read | P3 |
| `QuotationService` | `createFromRequests(List<Id>)`, `recalculate(List<Id>)` (the planned `applyToQuotations`), `submitForApproval(List<Id>)`, `approve(List<Id>)`, `reject(List<Id>, String reason)`, `convertToShipment(List<Id>)` → `ServiceResult` (live) | Quotation create/edit; `eLogix_Approve_Quotation` (approve, reject); Shipment create (convert) | P3 |
| `FleetAllocationService` | `allocate(List<AllocationRequest>)`, `reallocate(List<AllocationRequest>)`, `correctDispatchedAllocation(List<AllocationRequest>)` (needs `eLogix_Correct_Dispatched_Allocation`; `AllocationRequest.correctionReason` required; per-record `CORRECTION_REASON_REQUIRED`), `release(List<Id>)` (Phase 5: `activate` and `complete` withdrawn; the lifecycle follows the shipment status), each returning a `ServiceResult` with per-record codes: `REQUEST_INVALID`, `NOT_FOUND`, `NO_OPEN_ASSIGNMENT`, `STATUS_NOT_ALLOWED`, `FLEET_BUSY` (retryable), or the DML status code with the rule message. Built; deployment pending. See [FLEET_IMPLEMENTATION.md](FLEET_IMPLEMENTATION.md). | Vehicle Assignment create and edit; `eLogix_Allocate_Fleet` | P4 |
| `InventoryService` | `postMovements(List<MovementRequest>)`, `reserve(...)`, `release(...)` | Stock Movement create; `eLogix_Adjust_Inventory` for adjustments | P5 |
| `DeliveryService` | `startAttempts(List<Id> shipmentIds)` → attempt Ids; `recordProofs(List<ProofOfDeliveryRequest>)` → proof Ids (upload evidence files to them); `confirmDeliveries(List<Id> shipmentIds)`; `recordFailures(List<DeliveryFailureRequest>)`; `verifyProofs(List<Id> proofIds)`. All return `ServiceResult` with per-record codes: `REQUEST_INVALID`, `NOT_FOUND`, `DUPLICATE_REQUEST`, `NO_OPEN_ATTEMPT`, `ALREADY_DELIVERED` (idempotent repeat), `DELIVERY_BUSY` (retryable), `NOT_COMPLETED`, or the DML status code with the rule message. Built; deployment pending. See [DELIVERY_IMPLEMENTATION.md](DELIVERY_IMPLEMENTATION.md). | Delivery create/edit and Shipment edit; Proof of Delivery create; `Verified_By__c` edit (Logistics Manager) for verification | P5 |
| `InvoiceService` | `generate(List<InvoiceRequest>)` | Invoice create | P5 |
| `PaymentService` | `recordPayments(List<PaymentRequest>)` | Payment create; `eLogix_Record_Advance_Payment` for overpayment | P5 |
| `ReturnService` | `submit`, `approve`, `reject`, `completeInspection`, `restock` | `eLogix_Approve_Return` for approve/reject | P6 |

Inbound REST endpoints (GPS pings, payment callbacks) will be specified here in Phase 6, with request and response schemas and idempotency semantics.
