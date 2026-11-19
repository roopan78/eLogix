# eLogix ERP - Business Requirements

## 1. Purpose

eLogix ERP is a Salesforce-native logistics and supply-chain platform for a multi-branch Indian road-freight operator. It covers the full order-to-cash and reverse-logistics cycle, from customer request to proof of delivery, invoice and return. The prototype has to demonstrate realistic, controlled business workflows rather than CRUD screens.

## 2. Business context

- **Operator profile.** A regional full-truckload and part-load carrier with business units across South India and onward links to Hyderabad and Mumbai.
- **Reference lanes.** Chennai → Bangalore, Madurai → Coimbatore, Chennai → Hyderabad, Bangalore → Mumbai, Madurai → Chennai.
- **Pain points addressed.** Quotes priced inconsistently by hand, trucks double-booked or dispatched with expired papers, stock disappearing without an audit trail, duplicate invoices, and no single shipment history for customer service.

## 3. Personas

| Persona | Primary goals | Permission set |
|---|---|---|
| Logistics Manager | See every shipment, approve exceptions (discounts, cancellations, returns), keep SLAs | `eLogix_Logistics_Manager` |
| Sales Executive | Onboard customers, capture requests, issue quotations quickly and consistently | `eLogix_Sales_Executive` |
| Operations Executive | Execute shipments: items, status, tracking, delivery, proof of delivery | `eLogix_Operations_Executive` |
| Fleet Manager | Keep vehicles and drivers compliant and allocate them without conflicts | `eLogix_Fleet_Manager` |
| Warehouse Manager | Accurate stock, controlled movements, return inspection | `eLogix_Warehouse_Manager` |
| Finance Executive | Correct invoices once per milestone, reconcile payments, settle claims, manage rate cards and credit terms | `eLogix_Finance_Executive` |
| Customer Service Executive | Answer "where is my shipment", raise requests, returns and claims | `eLogix_Customer_Service_Executive` |
| System Administrator | Configure, support, correct data | System Administrator profile + `eLogix_Administrator` |

## 4. Functional scope and priority

| ID | Capability | Priority | Phase | Status |
|---|---|---|---|---|
| FR-01 | Customer master with classification, active flag, credit terms, GSTIN | P0 | 1 | Data model live |
| FR-02 | Multiple business units in one org | P0 | 1 | Data model live |
| FR-03 | Shipment request capture with validation (active customer, valid dates, weight) | P0 | 1-2 | Validation live; services P2 |
| FR-04 | Quotation from the applicable date-effective rate card; configurable tax; discount approval | P0 | 3, 5 | Data model live |
| FR-05 | Shipment with items, controlled lifecycle (section 6 of the spec), tracking history for every status change | P0 | 2 | Lifecycle configuration live |
| FR-06 | Fleet allocation honouring capacity, document validity, licence validity, maintenance and no overlapping assignments | P0 | 4 | Data model live |
| FR-07 | Warehouse stock maintained only through audited stock movements; reservations; return restocking after inspection | P1 | 5 | Data model live |
| FR-08 | Delivery attempts, failure reasons, proof of delivery with Salesforce Files | P1 | 5 | Data model live |
| FR-09 | Invoicing once per shipment and milestone; payments reconciled against balance; paid invoices locked | P0 | 5 | Data model live |
| FR-10 | Returns (approval before pickup, inspection before resolution) and claims | P2 | 6 | Data model live |
| FR-11 | Integrations: GPS, payment gateway, accounting, mapping and distance, notifications, as mocks behind interfaces | P2 | 6 | Logging object live |
| FR-12 | Operational LWCs (booking, quotation builder, allocation, tracking console, delivery, invoices, returns) | P1 | 7 | Not started |
| FR-13 | Executive Operations dashboard and operational reports on native analytics | P1 | 8 | Not started |
| FR-14 | Idempotent demo data for the reference lanes | P1 | 9 | Not started |

P0 = must demo; P1 = should demo; P2 = demo if time permits (CLAUDE.md section 17).

## 5. Non-functional requirements

| Area | Requirement |
|---|---|
| Platform | Standard Developer Edition. No paid add-ons. No Enterprise-only features. |
| Security | CRUD, FLS and sharing enforced. Sensitive operations behind custom permissions. Financial and system-derived fields protected. |
| Integrity | Duplicate prevention through unique keys. Derived totals computed by the platform. Audit trail for stock and shipment history. |
| Scale | All Apex bulk-safe for 200-record batches. No SOQL or DML in loops. |
| Configurability | Business thresholds in custom metadata. Prices on rate card records. Lifecycle in custom metadata. |
| Storage | Fits in 5 MB of data storage with headroom (planned demo footprint about 1.2 MB). |
| Quality | At least 85% meaningful Apex coverage. Tests for every rule in [BUSINESS_RULES.md](BUSINESS_RULES.md). |

## 6. Out of scope (prototype)

Live external integrations, multi-currency, Experience Cloud portals, mobile offline, route optimisation, e-way bill and GST e-invoicing filing.
