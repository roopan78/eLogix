# eLogix ERP - Shipment Lifecycle

| | |
|---|---|
| Configuration | `Shipment_Status_Transition__mdt`: 46 records, **live** in `eLogixDev` |
| Enforcement | `ShipmentStatusPolicy` (Apex, Phase 2), called from `ShipmentTriggerHandler` on insert and on status change |
| Status vocabulary | Global value set `eLogix_Shipment_Status` (17 values; default `Draft`) |
| History | Every allowed transition writes one `Tracking_Event__c`. `Status__c` also has field history tracking. |

## 1. State diagram

```mermaid
stateDiagram-v2
    state "Ready for Dispatch" as ReadyforDispatch
    state "In Transit" as InTransit
    state "Out for Delivery" as OutforDelivery
    state "On Hold" as OnHold
    state "Failed Delivery" as FailedDelivery
    state "Return Initiated" as ReturnInitiated

    [*] --> Draft
    [*] --> Requested
    [*] --> Quoted
    Draft --> Requested
    Requested --> Quoted
    Quoted --> Confirmed
    Confirmed --> ReadyforDispatch
    ReadyforDispatch --> Dispatched
    Dispatched --> InTransit
    InTransit --> OutforDelivery
    OutforDelivery --> Delivered
    Delivered --> Closed
    Closed --> [*]

    Draft --> Cancelled
    Requested --> Cancelled
    Quoted --> Cancelled
    Confirmed --> Cancelled : permission
    ReadyforDispatch --> Cancelled : permission
    OnHold --> Cancelled : permission
    Cancelled --> [*]

    Confirmed --> OnHold
    ReadyforDispatch --> OnHold
    Dispatched --> OnHold
    InTransit --> OnHold
    Delayed --> OnHold
    FailedDelivery --> OnHold
    OnHold --> Confirmed
    OnHold --> ReadyforDispatch
    OnHold --> InTransit

    Dispatched --> Delayed
    InTransit --> Delayed
    OutforDelivery --> Delayed
    Delayed --> InTransit
    Delayed --> OutforDelivery

    OutforDelivery --> FailedDelivery
    FailedDelivery --> OutforDelivery
    FailedDelivery --> ReturnInitiated

    InTransit --> Damaged
    OutforDelivery --> Damaged
    Delayed --> Damaged
    InTransit --> Lost
    OutforDelivery --> Lost
    Delayed --> Lost
    Damaged --> ReturnInitiated
    Damaged --> Closed
    Lost --> Closed

    Delivered --> ReturnInitiated
    ReturnInitiated --> Closed
```

"permission" means the transition needs custom permission `eLogix_Cancel_Confirmed_Shipment`.

## 2. Design rules

1. **Initial statuses.** A shipment can be created only as `Draft`, `Requested` or `Quoted` (records with blank `From_Status__c`). Shipments are never created already `Confirmed`. Their items are child records inserted after the parent, so the at-least-one-item rule can only be checked on the move to `Confirmed`.
2. **Terminal statuses.** `Closed` and `Cancelled` have no outgoing transitions. The generator fails the build if one is added. This implements "cancelled shipments cannot be processed further".
3. **No re-dispatch.** No path from `Delivered` leads back to `Dispatched` (also a generator check). This implements "delivered shipments cannot be dispatched again".
4. **Override.** A user holding `eLogix_Override_Shipment_Status` (Administrator, Logistics Manager) may make any change, to correct data. The policy still writes a Tracking Event, with remarks marking it as an override.
5. **Transition guards** (enforced in Apex, in addition to the table):

   | Into | Guard | Phase |
   |---|---|---|
   | `Confirmed` | `Item_Count__c ≥ 1` | P2 |
   | `Ready for Dispatch` | Vehicle and driver allocated through `FleetAllocationService` | P4 |
   | `Dispatched` | Warehouse-sourced items have reserved stock | P5 |
   | `Delivered` | `Actual_Delivery_Date__c` set (validation rule `SHP_Delivered_Requires_Delivery_Date`, live) | Live |
   | `On Hold` / `Cancelled` | Reason entered (validation rules, live) | Live |
6. **Tracking event mapping.** `Tracking_Event_Type__c` on each transition record names the event type. It equals the target status, except that creation writes `Created`. The event's `From_Status__c` and `To_Status__c` fields record the actual change.
7. **Shipment request status is separate.** `Shipment_Request__c.Status__c` (Draft → Submitted → Under Review → Quoted → Approved → Converted, or Rejected/Cancelled) tracks the commercial intake. The shipment lifecycle above starts when a request is converted.

## 3. Transition table

| From | To | Tracking event | Required permission | Note |
|---|---|---|---|---|
| *(create)* | Draft | Created |  | Shipment captured without a request. |
| *(create)* | Requested | Created |  | Shipment created from a submitted shipment request. |
| *(create)* | Quoted | Created |  | Shipment created from an accepted quotation. |
| Draft | Requested | Requested |  |  |
| Requested | Quoted | Quoted |  |  |
| Quoted | Confirmed | Confirmed |  | Requires at least one shipment item. |
| Confirmed | Ready for Dispatch | Ready for Dispatch |  | Requires vehicle and driver allocation. |
| Ready for Dispatch | Dispatched | Dispatched |  | Requires inventory to be available for warehouse-sourced items. |
| Dispatched | In Transit | In Transit |  |  |
| In Transit | Out for Delivery | Out for Delivery |  |  |
| Out for Delivery | Delivered | Delivered |  |  |
| Delivered | Closed | Closed |  |  |
| Draft | Cancelled | Cancelled |  |  |
| Requested | Cancelled | Cancelled |  |  |
| Quoted | Cancelled | Cancelled |  |  |
| Confirmed | Cancelled | Cancelled | `eLogix_Cancel_Confirmed_Shipment` |  |
| Ready for Dispatch | Cancelled | Cancelled | `eLogix_Cancel_Confirmed_Shipment` |  |
| On Hold | Cancelled | Cancelled | `eLogix_Cancel_Confirmed_Shipment` |  |
| Confirmed | On Hold | On Hold |  |  |
| Ready for Dispatch | On Hold | On Hold |  |  |
| Dispatched | On Hold | On Hold |  |  |
| In Transit | On Hold | On Hold |  |  |
| Delayed | On Hold | On Hold |  |  |
| Failed Delivery | On Hold | On Hold |  |  |
| On Hold | Confirmed | Confirmed |  |  |
| On Hold | Ready for Dispatch | Ready for Dispatch |  |  |
| On Hold | In Transit | In Transit |  |  |
| Dispatched | Delayed | Delayed |  |  |
| In Transit | Delayed | Delayed |  |  |
| Out for Delivery | Delayed | Delayed |  |  |
| Delayed | In Transit | In Transit |  |  |
| Delayed | Out for Delivery | Out for Delivery |  |  |
| Out for Delivery | Failed Delivery | Failed Delivery |  |  |
| Failed Delivery | Out for Delivery | Out for Delivery |  | Re-attempt delivery. |
| Failed Delivery | Return Initiated | Return Initiated |  |  |
| In Transit | Damaged | Damaged |  |  |
| Out for Delivery | Damaged | Damaged |  |  |
| Delayed | Damaged | Damaged |  |  |
| In Transit | Lost | Lost |  |  |
| Out for Delivery | Lost | Lost |  |  |
| Delayed | Lost | Lost |  |  |
| Damaged | Return Initiated | Return Initiated |  |  |
| Damaged | Closed | Closed |  | Closed after claim settlement. |
| Lost | Closed | Closed |  | Closed after claim settlement. |
| Delivered | Return Initiated | Return Initiated |  |  |
| Return Initiated | Closed | Closed |  |  |

To change the lifecycle, edit `TRANSITIONS` in `scripts/node/model/elogix-config.mjs`, run `npm run metadata:generate`, then deploy `force-app/main/default/customMetadata`. Admins can also edit records in Setup → Custom Metadata Types. The source must then be retrieved back into the repo so it does not drift.
