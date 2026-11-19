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
| `FleetAllocationService` | `allocate(List<AllocationRequest>)`, `release(List<Id> assignmentIds)` | `eLogix_Allocate_Fleet` | P4 |
| `InventoryService` | `postMovements(List<MovementRequest>)`, `reserve(...)`, `release(...)` | Stock Movement create; `eLogix_Adjust_Inventory` for adjustments | P5 |
| `DeliveryService` | `completeDelivery(List<DeliveryResult>)` | Delivery edit | P5 |
| `InvoiceService` | `generate(List<InvoiceRequest>)` | Invoice create | P5 |
| `PaymentService` | `recordPayments(List<PaymentRequest>)` | Payment create; `eLogix_Record_Advance_Payment` for overpayment | P5 |
| `ReturnService` | `submit`, `approve`, `reject`, `completeInspection`, `restock` | `eLogix_Approve_Return` for approve/reject | P6 |

Inbound REST endpoints (GPS pings, payment callbacks) will be specified here in Phase 6, with request and response schemas and idempotency semantics.
