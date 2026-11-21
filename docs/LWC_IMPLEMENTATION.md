# eLogix ERP - Lightning Web Components (Phase 7)

|        |                                                                                                                                                                                                                                |
| ------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| Status | Steps 1–3 deployed (Step 3: `0Afg700000Kax4UCAR`). Steps 4–7 implemented locally, awaiting check-only validation.                                                                                                              |
| Scope  | Shipments, quotations, fleet, tracking and delivery. Warehouse, inventory, invoicing, payments and returns screens wait for their services (decision P1). No custom dashboard: the Phase 8 native dashboard goes on Home (P2). |
| Tests  | Apex: 5 controller test classes (23 tests). Jest: 15 suites, 98 tests.                                                                                                                                                         |

## 1. Architecture

```
LWC (SLDS, labels, loading / empty / error states)
  │  reads: Lightning Data Service (record view / edit forms, getRecord, object info, picklists)
  │         or cacheable controller methods (user mode)
  │  writes: controller action  ->  existing service  ->  trigger, validation rules, policy
  ▼
5 thin controllers (with sharing, @AuraEnabled; return the service's ServiceResult)
  ShipmentConsoleController  QuotationConsoleController  FleetConsoleController
  DeliveryConsoleController  TrackingConsoleController
```

- No business rule is implemented in JavaScript. Components decide only which buttons to show for the current status. The service re-checks every action and its result (`ServiceResult`) is shown as a toast through `elogixUtils.handleServiceResult`.
- **Status changes (P5):**
  - Offered options come from the real `ShipmentStatusPolicy`, through `ShipmentConsoleController.getStatusOptions`.
  - Options checked only on save (allocation guard) are marked.
  - Out for Delivery, Delivered and Failed Delivery are reachable only through `deliveryManagement`.
- All user-facing text is in Custom Labels (`eLogix_UI_*`). Table headers use the fields' own labels from object info.

## 2. Component inventory

| Component            | Placement                                             | What it does                                                                                                                        | Backend                                               |
| -------------------- | ----------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------- |
| `statusBadge`        | Reusable                                              | Colour-coded SLDS badge per status meaning                                                                                          | -                                                     |
| `loadingIndicator`   | Reusable                                              | Accessible spinner with optional message                                                                                            | -                                                     |
| `confirmationDialog` | Reusable (LightningModal)                             | Confirm, with an optional required reason                                                                                           | -                                                     |
| `reusableDataTable`  | Reusable                                              | Datatable with loading, error (Retry), empty states and client sorting                                                              | -                                                     |
| `elogixUtils`        | Service module                                        | `reduceErrors`, toasts, `handleServiceResult`, `formatLabel`                                                                        | -                                                     |
| `shipmentManagement` | Shipment Console                                      | Shipment list, status filter, search, open record                                                                                   | `getShipments`                                        |
| `shipmentBooking`    | Shipment Console; Account page                        | Shipment request form: draft or submit                                                                                              | LDS record edit form                                  |
| `shipmentDetails`    | Shipment record page                                  | Key fields, status badge, policy-driven status change with reasons                                                                  | `getStatusOptions`, `changeStatus`                    |
| `shipmentTimeline`   | Shipment record page; Tracking Console                | Tracking history, newest first; refreshes on status change                                                                          | `getTimeline`                                         |
| `quotationBuilder`   | Quotation record page (Shipment Request page: create) | Breakdown, charge lines, recalculate, submit, approve or reject (`eLogix_Approve_Quotation`), mark sent, record acceptance, convert | `QuotationConsoleController`; LDS for Sent / Accepted |
| `vehicleAllocation`  | Shipment record page                                  | Open assignment; allocate, reallocate, release; correction on On Hold with `eLogix_Correct_Dispatched_Allocation`                   | `FleetConsoleController`                              |
| `fleetManagement`    | Fleet Console                                         | Vehicles and drivers, status, documents, allocatable today                                                                          | `getFleetOverview`                                    |
| `trackingConsole`    | Tracking Console                                      | Shipments on the road; history and manual event for the selected one                                                                | `TrackingConsoleController`                           |
| `deliveryManagement` | Shipment record page                                  | Start attempt, proof of delivery, evidence upload, confirm, failure, verify                                                         | `DeliveryConsoleController`; `lightning-file-upload`  |

## 3. Lightning pages and navigation

Generated by `npm run metadata:generate` from `scripts/node/model/elogix-experience.mjs` (`APP_PAGES`, `RECORD_PAGES`).

| Page                           | Type / template                                    | Components                                                                                                                               | Navigation                          |
| ------------------------------ | -------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------- | ----------------------------------- |
| `eLogix_Shipment_Console`      | App page, `flexipage:defaultAppHomeTemplate`       | `shipmentManagement`, `shipmentBooking` (stay on page)                                                                                   | Tab **Shipment Console**            |
| `eLogix_Fleet_Console`         | App page                                           | `fleetManagement`                                                                                                                        | Tab **Fleet Console**               |
| `eLogix_Tracking_Console`      | App page                                           | `trackingConsole`                                                                                                                        | Tab **Tracking Console**            |
| `eLogix_Shipment_Record_Page`  | Record page, `flexipage:recordHomeTemplateDesktop` | Header: highlights panel. Main: `shipmentDetails`, `vehicleAllocation`, `deliveryManagement`, related lists. Sidebar: `shipmentTimeline` | App default for Shipment (desktop)  |
| `eLogix_Quotation_Record_Page` | Record page                                        | Header: highlights panel. Main: `quotationBuilder`, related lists. Sidebar: record detail                                                | App default for Quotation (desktop) |

The three console tabs follow Home and Dashboards in the eLogix ERP app. A permission set gets a console tab when it can read the page's object (`requires`).

`quotationBuilder`'s **Create quotation** mode can also be added to the Shipment Request record page in Lightning App Builder; no generated page assigns it there.

## 4. Security

- **Controller class access** is generated from `CONTROLLER_ACCESS` in `elogix-security.mjs`. A role gets a controller when it can read the screen's object:

  | Controller                   | Object read access needed |
  | ---------------------------- | ------------------------- |
  | `ShipmentConsoleController`  | Shipment                  |
  | `QuotationConsoleController` | Quotation                 |
  | `FleetConsoleController`     | Vehicle Assignment        |
  | `DeliveryConsoleController`  | Delivery                  |
  | `TrackingConsoleController`  | Tracking Event            |

  The GPS integration and data migration permission sets get none.

- **Reads** run in user mode, so CRUD, FLS and sharing apply. Record views use LDS forms, which hide fields without FLS.
- **Button visibility is a convenience only:**
  - Approve and reject use the `eLogix_Approve_Quotation` import.
  - Allocation actions use `canAllocate` / `canCorrect` from the controller.
  - Proof verification uses `Verified_By__c` updateability.

  The services enforce the same rules on save.

- **Panels a role cannot use show an error state, not data.** For example, the Shipment record page shows the allocation panel to a Sales Executive, who has no Vehicle Assignment access. Component visibility filters per role are a Phase 9 refinement.
- **Visibility before Phase 9:** under Private org-wide defaults and no role hierarchy, non-manager users see only shipments they own.

## 5. Manual UI verification checklist

Run as an administrator holding `eLogix_Administrator`, then repeat the marked steps (★) as a role user.

| #    | Where                                                                        | Check                                                                                                                                                    |
| ---- | ---------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 1    | App launcher → eLogix ERP                                                    | Tabs: Home, Dashboards, Shipment Console, Fleet Console, Tracking Console, then the object tabs                                                          |
| 2    | Shipment Console                                                             | List loads; status filter and search narrow it; View opens the record; empty state for a search with no match                                            |
| 3    | Shipment Console → booking                                                   | Save a draft, then submit a request: toasts, form clears; validation errors (pickup in the past) show inline                                             |
| 4    | Quotation (from a Submitted request: Create quotation, or an existing Draft) | Record page is the eLogix page; breakdown and lines show; Recalculate; Submit (auto-approves without discount)                                           |
| 5 ★  | Quotation with a large discount, as Sales                                    | Submit leaves it Pending Approval; no Approve/Reject buttons for Sales                                                                                   |
| 6    | Same quotation, as Logistics Manager                                         | Approve; or Reject with a reason (returns to Draft)                                                                                                      |
| 7    | Approved quotation                                                           | Mark as sent → Record customer acceptance → Convert to shipment opens the new shipment                                                                   |
| 8    | Shipment record page                                                         | Details, status badge, timeline; status options mark Ready for Dispatch as "checked on save"; no delivery statuses offered                               |
| 9    | Confirmed shipment                                                           | Ready for Dispatch without an allocation is refused with the guard's message; On Hold asks for a reason                                                  |
| 10 ★ | Same shipment, as Fleet Manager                                              | Allocate a suggested vehicle and driver; Reallocate; Release with confirmation; as Operations: read-only allocation                                      |
| 11   | Allocated shipment                                                           | Ready for Dispatch → Dispatched → In Transit; timeline updates after each change                                                                         |
| 12   | In Transit shipment → Delivery panel                                         | Start attempt (Out for Delivery); record proof; upload a file; Confirm delivery (Delivered)                                                              |
| 13   | Another In Transit shipment                                                  | Start attempt; Record failed attempt with a reason (Failed Delivery); start a second attempt                                                             |
| 14 ★ | Delivered shipment, as Logistics Manager (shipment owner until Phase 9)      | Verify proof; Operations sees no Verify button                                                                                                           |
| 15   | Fleet Console                                                                | Vehicle and driver tabs with counts; Allocatable column; View opens records                                                                              |
| 16   | Tracking Console                                                             | On-the-road list; select a shipment: timeline and form; record a Hub Arrival; a status event type (e.g. Delivered) is refused with the service's message |
