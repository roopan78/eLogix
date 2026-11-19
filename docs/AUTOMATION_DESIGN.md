# eLogix ERP - Automation Design

Status: **design only.** Nothing in this document is deployed yet, apart from the validation rules listed in [BUSINESS_RULES.md](BUSINESS_RULES.md). Flows and asynchronous Apex arrive in Phases 2 to 6.

## 1. Rule of ownership

Each behaviour has exactly one owner (CLAUDE.md section 10). Flows orchestrate; they call Apex invocable methods for anything transactional instead of re-implementing rules.

| Concern | Owner | Mechanism |
|---|---|---|
| Single-record invariants | Validation rules (live) | Declarative |
| Status transitions, fleet, stock, invoice and payment integrity | Apex domain and services | Triggers through handlers |
| Approvals, notifications, SLA monitoring, admin-tunable orchestration | Flows | Record-triggered and scheduled flows |
| Long-running or callout work | Queueable Apex | `System.Finalizer` for retry and dead-letter |
| Large-volume maintenance | Batch Apex | Scheduled |
| Decoupled cross-module reactions | Platform events | Apex and flow subscribers |

## 2. Planned flows (CLAUDE.md section 10)

| Flow | Type | Trigger | Does | Rule owner it relies on | Phase |
|---|---|---|---|---|---|
| Shipment Request Validation Flow | Record-triggered, before save | Request created or submitted | Defaults the business unit from the customer, the route from origin and destination, and the expected delivery date from route transit hours. Moves Draft → Submitted when complete. | Validation rules own the hard checks (active customer, dates, weight) | P5 |
| Quotation Approval Flow | Record-triggered, after save | Quotation set to Pending Approval | Auto-approves when discount ≤ `Max_Discount_Percent_No_Approval`; otherwise routes to users holding `eLogix_Approve_Quotation` | Approval stamp written by an Apex invocable | P5 |
| Delivery Completion Flow | Record-triggered, after save | Delivery status becomes Delivered | Calls `DeliveryService` to set the shipment Delivered and the actual delivery date, and to write tracking | `ShipmentStatusPolicy` | P5 |
| Invoice Generation Flow | Record-triggered, after save | Shipment becomes Delivered | Calls `InvoiceService.generate` (idempotent through `Invoice_Key__c`) | `InvoiceService` | P5 |
| Payment Status Update Flow | Record-triggered, after save | Payment Completed, Failed or Reversed | Recomputes invoice status (Partially Paid / Paid) through an invocable | `PaymentService` | P5 |
| Return Approval Flow | Record-triggered, after save | Return Submitted | Routes to `eLogix_Approve_Return` holders; on approval calls `ReturnService.approve` | `RET_Approval_Before_Pickup` | P6 |
| SLA Monitoring Flow | Scheduled, hourly | Active shipments past expected delivery plus `Delay_Grace_Hours` | Transitions to Delayed through the policy and notifies the owner | `ShipmentStatusPolicy` | P5 |

## 3. Planned asynchronous Apex and events

| Component | Purpose | Phase |
|---|---|---|
| `Shipment_Status_Changed__e` | Published by `TrackingService` after commit; subscribers send notifications and post GPS or accounting sync | P6 |
| `IntegrationCalloutQueueable` | Callouts with timeout, retry policy, idempotency key, `Integration_Log__c` entry, dead letter after max retries | P6 |
| `IntegrationLogPurgeBatch` | Deletes successful logs older than N days (protects 5 MB storage) | P6 |
| `DocumentExpiryBatch` | Flags vehicles and drivers whose registration, insurance or licence expires within 30 days | P4 |
