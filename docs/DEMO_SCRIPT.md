# eLogix ERP - Demo Script

Status: **outline.** It is finalised in Phase 9, once demo data and LWCs exist. Each step lists the capability it proves, so the outline doubles as a coverage checklist.

| # | Story (Chennai → Bangalore, Sri Murugan Textiles) | Persona | Proves | Available from |
|---|---|---|---|---|
| 1 | Open the eLogix ERP app; show navigation, a customer with credit terms and GSTIN, and the business units | Admin | App, data model, layouts | Phase 1 (live) |
| 2 | Try to raise a request for an inactive customer and get blocked; raise a valid request | Sales | Customer rules | Phase 1 (live) |
| 3 | Build a quotation from the effective rate card: base + weight + distance + fuel + insurance − discount + GST | Sales | Freight engine, configurable pricing | Phase 3 |
| 4 | A 15% discount routes for approval; the manager approves | Logistics Mgr | Approval flow, custom permission | Phase 5 |
| 5 | Convert to a shipment, add items, confirm (blocked first with zero items) | Operations | Lifecycle policy, guards | Phase 2 |
| 6 | Allocate a vehicle and driver: an expired-insurance truck and a double-booked driver are rejected | Fleet | Fleet rules, locking | Phase 4 |
| 7 | Dispatch: stock is reserved and issued through stock movements; the timeline shows each tracking event | Warehouse / Ops | Inventory audit, tracking | Phase 5 |
| 8 | Try to jump Delivered → Dispatched and get blocked; show the transition metadata | Operations | Configurable status policy | Phase 2 |
| 9 | Deliver with proof of delivery and a photo in Files; the invoice is generated once (the replay is idempotent) | Ops / Finance | Delivery, duplicate prevention | Phase 5 |
| 10 | Record a partial UPI payment, then the balance; an overpayment is blocked | Finance | Payment reconciliation | Phase 5 |
| 11 | Raise a return, approve it, inspect it, restock it; raise a damage claim | Customer Svc / Warehouse | Reverse logistics | Phase 6 |
| 12 | Executive Operations Dashboard | Logistics Mgr | Native analytics | Phase 8 |

Already demonstrable today: steps 1 and 2, plus the data-integrity points behind steps 8 to 10 (immutable tracking history, unique invoice key, roll-up totals) using `scripts/apex/verify-phase1-metadata.apex`.
