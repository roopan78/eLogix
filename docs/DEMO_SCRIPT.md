# eLogix ERP - Demo Script

Status: **outline.** It is finalised in Phase 9, once demo data and LWCs exist. Each step lists the capability it proves, so the outline doubles as a coverage checklist.

| # | Story (Chennai → Bangalore, Sri Murugan Textiles) | Persona | Proves | Available from |
|---|---|---|---|---|
| 1 | Open the eLogix ERP app; show navigation, a customer with credit terms and GSTIN, and the business units | Admin | App, data model, layouts | Phase 1 (live) |
| 2 | Try to raise a request for an inactive customer and get blocked; raise a valid request | Sales | Customer rules | Phase 1 (live) |
| 3 | Build a quotation from the effective rate card: base + weight + distance + fuel + insurance − discount + GST (a non-taxable loading line stays out of GST) | Sales | Freight engine, configurable pricing, `Is_Taxable__c` | Phase 3 (live) |
| 4 | A 15% discount goes to Pending Approval; the Sales owner cannot approve it; the manager approves, and only then can it be sent | Logistics Mgr | Approval gate, verified stamp, custom permission | Phase 3 (gate, live); Phase 5 (routing Flow) |
| 5 | Customer accepts; convert to a shipment (status Quoted, freight from the quotation), add items, confirm (blocked first with zero items) | Logistics Mgr / Operations | Conversion, lifecycle policy, guards | Phase 3 (conversion) + Phase 2 (live) |
| 6 | Allocate a vehicle and driver. Rejected: an expired-insurance truck, an under-capacity truck, a truck with scheduled maintenance and a double-booked driver. The compliant pair is accepted and appears on the shipment. Ready for Dispatch is refused until then, and cancelling the shipment frees the truck. Scripted in `scripts/apex/verify-phase4-fleet.apex`. | Fleet | Fleet rules, locking, Ready for Dispatch guard | Phase 4 (built, deployment pending) |
| 7 | Dispatch: the allocation is revalidated and the trip becomes Active; the timeline shows each tracking event. (Stock reservation at dispatch: Phase 5B.) | Ops | Revalidation, lifecycle, tracking | Phase 5 (stock: 5B) |
| 8 | Try to jump Delivered → Dispatched and get blocked; show the transition metadata | Operations | Configurable status policy | Phase 2 |
| 9 | Start a delivery attempt; record the proof and attach a photo in Files; confirm. A repeated confirmation is refused; the photo cannot be deleted, even by an administrator. A failed attempt and its retry show as attempts 1 and 2 on the same trip. (Invoice generation: Phase 5B.) | Ops / Logistics Mgr | Delivery, evidence, duplicate prevention | Phase 5 (invoice: 5B) |
| 10 | Record a partial UPI payment, then the balance; an overpayment is blocked | Finance | Payment reconciliation | Phase 5 |
| 11 | Raise a return, approve it, inspect it, restock it; raise a damage claim | Customer Svc / Warehouse | Reverse logistics | Phase 6 |
| 12 | Executive Operations Dashboard | Logistics Mgr | Native analytics | Phase 8 |

Already demonstrable today: steps 1 and 2, plus the data-integrity points behind steps 8 to 10 (immutable tracking history, unique invoice key, roll-up totals) using `scripts/apex/verify-phase1-metadata.apex`.
