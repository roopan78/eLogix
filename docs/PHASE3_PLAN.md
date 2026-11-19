# eLogix ERP - Phase 3 Discovery and Implementation Plan (Pricing and Quotation)

| | |
|---|---|
| Status | **Implemented, deployed and verified 2026-11-19** (model `0Afg700000KOim0CAD`, Apex `0Afg700000KRoekCAD`, follow-up A1 to A3 `0Afg700000KRt9mCAD`, A4 `0Afg700000KRUWMCA5`). Not committed. Section 0 records the approved decisions; results are in [PHASE3_IMPLEMENTATION_REPORT.md](PHASE3_IMPLEMENTATION_REPORT.md). |
| Baseline | Branch `feature/phase-2-apex-foundation`, commit `90751c6`; org `eLogixDev` at deploy `0Afg700000KOZcDCAX` |
| Discovery date | 2026-11-19 (read-only: repository, model files, live org) |
| Related | [APEX_ARCHITECTURE.md](APEX_ARCHITECTURE.md) · [APEX_FRAMEWORK.md](APEX_FRAMEWORK.md) · [BUSINESS_RULES.md](BUSINESS_RULES.md) · [AUTOMATION_DESIGN.md](AUTOMATION_DESIGN.md) · [SECURITY_DESIGN.md](SECURITY_DESIGN.md) |

## 0. Approved decisions (2026-11-19)

| # | Decision |
|---|---|
| Q1 | **In scope.** Only an `Accepted` quotation can be converted to a shipment. |
| Q2 | `QuotationDomain` enforces a fixed set of status transitions in Apex. There is **no** custom metadata lifecycle and **no** scheduled expiry. Allowed transitions: Draft → Pending Approval or Approved; Pending Approval → Approved, or → Draft (approval rejected); Approved → Sent; Sent → Accepted or Rejected (customer). `Accepted` and `Rejected` are terminal. Any other change, including any change into `Expired` or `Superseded`, is rejected. Expiry stays with `Is_Expired__c` and `QT_Cannot_Accept_Expired`. |
| Q3 | **Deferred.** No version increment, no `Superseded`, no revision creation. Draft quotations can be recalculated in place. |
| Q4 | **In scope.** The request moves to `Quoted` when a quotation is created, to `Approved` when the customer accepts, and to `Converted` when the shipment is created. Each move happens in the same transaction as its quotation change, with per-record failure handling. |
| Q5 | Fuel surcharge % applies to base + weight charge + distance charge, after the minimum-freight uplift. |
| Q6 | Insurance % applies to the request's `Declared_Value__c`. A blank value gives zero insurance. |
| Q7 | The minimum applies to base + weight charge + distance charge. The uplift is recorded in the protected `Base_Freight__c`. |
| Q8 | A route is mandatory; distance = `Route__c.Distance__c`. No distance field or provider is added. |
| Q9 | Effectiveness is judged on `Requested_Pickup_Date__c`. |
| Q10 | Ranking: business-unit and region specificity, then lowest `Selection_Priority__c`, then latest `Effective_From__c`. An equal tie at the top fails with an ambiguity error. |
| Q11 | Vehicle type is required. |
| Q12 | Threshold base: gross freight before discount and tax (base, weight, distance, fuel, insurance, positive additional lines). |
| Q13 | Discount = header `Discount__c` + absolute value of negative `Discount` lines. |
| Q14 | **Option (a).** `Is_Taxable__c` is honoured through a taxable-lines roll-up and formula changes made via the Phase 1 generator. The 12% default tax setting is kept. |
| Q15 | Each charge component is rounded to 2 decimals, half-up, before saving. |
| Q16 | Default tax setting only; no overrides. |
| Q17 | Self-approval is not allowed, even with the permission. |
| Q18 | Once a quotation leaves Draft (Pending Approval, Approved, Sent, Accepted, Rejected), `Discount__c` and quotation lines are locked. Only Draft quotations can be changed or recalculated. Lines are locked by a validation rule on `Quotation_Line__c`; the header discount is locked by `QuotationDomain`. |
| Q19 | A discount at or below 10% needs no manual approval (automatic approval path). |
| Q20 | One shipment per accepted quotation, enforced by row locking and a duplicate-conversion check. |
| Q21 | Only `Submitted` and `Under Review` requests can be quoted. `Quoted` is excluded, because re-quoting is deferred with revisions. Recalculating an existing Draft quotation is still supported. |
| Q22 | A rejected approval returns the quotation to Draft, with the reason recorded in `Notes__c`. `Rejected` is reserved for customer rejection. |

### 0.1 Implementation consequences recorded before coding

1. **Request status side effects run in the quotation trigger** (after insert: → Quoted; after update into Accepted: → Approved). They therefore apply on every entry path. A request that cannot move fails only its own quotation row, through `addError`, the same per-record pattern as Phase 2 tracking. Conversion (→ Converted) runs in `QuotationService`, because no Phase 2 class may change; a shipment whose request cannot move is deleted again in the same transaction, and only that record is reported.
2. **Narrow `without sharing` writers (deviation from section 5, which said none).** A Logistics Manager has View All, but not Modify All, on Sales-owned quotations and requests, and Phase 9 roles do not exist yet. Approve and reject (the stamp is protected), request status moves, and the conversion compensation therefore use private `without sharing` inner classes. They are called only after explicit checks: the custom permission or object create access, a user-mode read of the record, and the business-state checks. The trigger-side writer reads `Trigger.new` and `Trigger.oldMap` itself (the Phase 2 F1 pattern), so no caller can supply the records it writes. This mirrors the approved `TrackingService.Writer` precedent and is listed for your review in the Phase 3 report.
3. **The approval stamp is verified by the trigger, not trusted.**
   - `Approved_By__c` and `Approval_Date__c` can change only on Pending Approval → Approved, and only when `Approved_By__c` is the running user, who must hold `eLogix_Approve_Quotation` and must not own the quotation.
   - `Approval_Date__c` is overwritten with the current time.
   - No other path can set, change or clear the stamp, including direct DML.
4. **Line deletion lock.** A validation rule cannot see deletes. Deleting a line changes the `Line_Total__c` roll-up, which saves the parent quotation again, and `QuotationDomain` rejects roll-up changes on quotations that are not Draft. Tests cover this.
5. **Shipment lane on conversion.** Origin, destination and distance come from the route that priced the quotation; weight and dates come from the request.
6. **Query budget.** Creating quotations for 200 requests costs 3 SOQL (requests and rate cards in the service, plus the request lock in the trigger), not the 2 stated in section 7.

Throughout this document:
- **[C]** means confirmed by CLAUDE.md, an approved project document or the deployed metadata.
- **[R]** means my recommendation.
- **[Q]** means an open question that needs your decision. I have not resolved any [Q] by assumption.

## 1. Scope

### 1.1 Confirmed Phase 3 scope

| # | Item | Source |
|---|---|---|
| S1 | `FreightCalculationService`: Base Freight + Weight × weight rate + Distance × distance rate + Fuel Surcharge + Insurance + Additional Charges − Discount + Applicable Tax. Dedicated service; no pricing hardcoded in Apex. | CLAUDE.md section 5 (Freight rules), section 7 |
| S2 | Rate card selection: configurable and date-aware. The card is matched on vehicle type, active flag and effective dates; the lowest `Selection_Priority__c` wins. | CLAUDE.md section 4G; BUSINESS_RULES "Pricing is date-aware…" (Planned P3) |
| S3 | Quotation service: create quotations from shipment requests, snapshotting the rate-card components into `Quotation__c`. Totals stay derived by the existing formulas. | PROJECT_STATUS phase plan; `Quotation__c` description; API_SPECIFICATION (`quote`, `applyToQuotations`) |
| S4 | Tax from `eLogix_Setting__mdt.Default_Tax_Percent` (12); validity from `Quotation_Validity_Days` (15). | Deployed settings; APEX_ARCHITECTURE section 4.3 ("first consumer is pricing") |
| S5 | Discount approval threshold `Max_Discount_Percent_No_Approval` (10%). Approvers hold `eLogix_Approve_Quotation`. The approval **stamp** (`Approved_By__c`, `Approval_Date__c`, protected fields) is written by Apex. The routing Flow is Phase 5. | AUTOMATION_DESIGN section 2 ("Approval stamp written by an Apex invocable", Flow in P5); BUSINESS_RULES |
| S6 | Unit tests: freight calculation, rate card selection, bulk processing, exception and rollback scenarios. | CLAUDE.md section 13 |

### 1.2 Explicitly out of Phase 3 (confirmed by existing plans)

| Item | Phase |
|---|---|
| Quotation Approval **Flow** (routing, auto-approve) and Shipment Request Validation Flow | P5 |
| `IDistanceProvider` mock / mapping adapter | P6 |
| LWCs (`quotationBuilder`, `shipmentBooking`) and their `@AuraEnabled` controllers | P7 |
| Roles and sharing rules (who sees whose requests and quotations) | P9 |
| Scheduled expiry of quotations (status → Expired) | Not planned anywhere yet; `Is_Expired__c` formula plus `QT_Cannot_Accept_Expired` already block expired acceptance |

### 1.3 Scope items needing your decision

| # | Item | Why it is unclear |
|---|---|---|
| Q1 | **Convert an accepted quotation into a `Shipment__c`** (status `Quoted`, `Freight_Amount__c` = quotation total, request → `Converted`) | CLAUDE.md Day 1 lists "Shipment and quotation services". The lifecycle allows initial status `Quoted` "from an accepted quotation". The demo step 5 conversion has no implementing service and is not assigned to any phase. **[R]** Include it in Phase 3, because it closes the request → quote → shipment chain the demo needs. |
| Q2 | **Quotation status rules** (Draft → Pending Approval → Approved → Sent → Accepted / Rejected / Expired / Superseded) | No transition configuration exists for quotations; `Shipment_Status_Transition__mdt` is shipment-specific. **Decided (section 0):** `QuotationDomain` enforces the fixed transition set and the money-safety rules; no CMDT. |
| Q3 | **Revisions**: `Version__c` + `Superseded` | The fields exist, but no rule says when a revision is created. **[R]** Defer, or keep minimal: re-pricing a Draft overwrites it in place, and a revision of a Sent quotation creates version n + 1 and supersedes the old one. |
| Q4 | **Request status side effects** (request → `Quoted` when quoted; → `Approved` when accepted; → `Converted` on conversion) | The request statuses exist, but no rule assigns ownership. **[R]** Owned by `QuotationService`, set in the same transaction as the quotation change. |

## 2. Dependencies on Phase 1 and Phase 2 (all deployed)

| Dependency | What Phase 3 uses |
|---|---|
| `Shipment_Request__c` | Customer, BU, Route, Origin/Destination, `Requested_Pickup_Date__c`, `Total_Weight__c`, `Declared_Value__c`, `Requested_Vehicle_Type__c`, `Status__c` |
| `Quotation__c` | Snapshot fields (`Rate_Card__c`, `Base_Freight__c`, `Weight_Charge__c`, `Distance_Charge__c`, `Fuel_Surcharge__c`, `Insurance_Charge__c`, `Tax_Percent__c`), `Discount__c`, `Valid_Until__c`, `Status__c`, `Version__c`, approval stamp. Formulas `Subtotal__c`, `Tax_Amount__c`, `Total_Amount__c`, roll-up `Line_Total__c` (verified in Phase 1: 10,500 + 12% = 11,760). |
| `Quotation_Line__c` | Additional charges; `Discount` type lines are negative (`QTL_Amount_Sign_Matches_Type`). |
| `Rate_Card__c` | `Vehicle_Type__c`, `Business_Unit__c`, `Region__c`, `Base_Freight__c`, `Rate_Per_KG__c`, `Rate_Per_KM__c`, `Fuel_Surcharge_Percent__c`, `Insurance_Percent__c`, `Minimum_Freight__c`, `Effective_From__c` / `Effective_To__c`, `Is_Active__c`, `Selection_Priority__c` |
| `Route__c` | `Distance__c` (the only distance source; the request has no distance field) |
| Validation rules (live) | `QT_Charges_Non_Negative`, `QT_Discount_Within_Charges`, `QT_Tax_Percent_In_Range`, `QT_Valid_Until_Required_When_Sent`, `QT_Cannot_Accept_Expired`, `QTL_*`, `RC_*`, `SR_*`. Phase 3 does not duplicate them. |
| Settings (live) | `Default_Tax_Percent` = 12, `Quotation_Validity_Days` = 15, `Max_Discount_Percent_No_Approval` = 10 |
| Security (live) | Quotation: Sales CRE, Logistics Manager CREV, Admin all, Ops / Finance / CS read. Rate Card: read for Sales, Ops, Finance (Finance CREV), LM. `eLogix_Approve_Quotation` is held by Admin and Logistics Manager. The quotation snapshot fields and stamp are **protected** (read-only FLS for every non-admin role). `Discount__c` is **not** protected; Sales can edit it. |
| Phase 2 framework | `TriggerHandler`, `ServiceResult`, exception hierarchy, `Logger`, `ExceptionHandler`, `PermissionService`, `SettingsService` (first consumer), selector conventions, `TestDataFactory`, custom-label conventions |
| Phase 2 shipment core (Q1 only) | `ShipmentTrigger` / `ShipmentStatusPolicy` accept initial status `Quoted`; `TrackingService` writes the `Created` event automatically. Conversion therefore needs no change to Phase 2 code. |

Org state (2026-11-19): 0 records in every pricing object, 1 trigger (`ShipmentTrigger`), 0 active Flows, data storage 5 MB.

## 3. Business rules and the ambiguities that block an exact implementation

### 3.1 Confirmed rules

1. Freight formula as in S1. The totals formula already exists on `Quotation__c`, so Apex writes **components only**.
2. No pricing values in Apex: rates come from `Rate_Card__c`, tax and thresholds from `eLogix_Setting__mdt`.
3. The rate card must be active and effective, match the vehicle type, and win by lowest `Selection_Priority__c`.
4. The discount cannot exceed the charges (validation rule, live).
5. A discount above 10% of gross freight requires approval by an `eLogix_Approve_Quotation` holder.
6. An expired quotation cannot be accepted (validation rule, live).
7. Inactive customers cannot raise requests (validation rule, live). **[R]** Quoting re-checks `Is_Active_Customer__c`, because a customer can be deactivated after the request.
8. Percent fields: Apex reads and writes **12** for 12%, while formulas see **0.12** (verified in Phase 1). The service divides by 100 exactly once.

### 3.2 Pricing questions

| # | Question | Options | **[R]** Recommendation |
|---|---|---|---|
| Q5 | What is the **fuel surcharge** a percentage of? | (a) line-haul = base + weight charge + distance charge; (b) base only; (c) distance charge only | (a), after the minimum-freight uplift |
| Q6 | What is **insurance** a percentage of? | (a) `Declared_Value__c` of the request (cargo value); (b) line-haul freight | (a). Blank declared value gives 0 insurance, shown in the breakdown. |
| Q7 | How does **`Minimum_Freight__c`** apply? | (a) line-haul = max(base + weight + distance, minimum), with the uplift added to `Base_Freight__c` (protected, so users cannot remove it); (b) the uplift as an auto-generated `Quotation_Line__c` ("Other"), which Sales could delete; (c) compare against the total before tax | (a); the breakdown reports `minimumUplift` separately |
| Q8 | **Distance source** when the request has no `Route__c` | (a) quoting requires a route (clear error); (b) add a distance field to the request (Phase 1 model change); (c) a lane table or mock provider (Phase 6 design) | (a) for Phase 3 |
| Q9 | **Pricing date** for "effective" | (a) `Requested_Pickup_Date__c` (price at service date); (b) quotation date (today) | (a) |
| Q10 | **Rate card specificity**: cards may carry an optional `Business_Unit__c` and `Region__c` | (a) Eligible: card BU blank or equal to the request BU, and card region blank or equal to the BU's region. Rank: BU match, then region match, then generic; then lowest priority; then latest `Effective_From__c`. A tie at the top is a configuration error (fail closed). (b) Ignore BU and region. | (a) |
| Q11 | **Vehicle type** when `Requested_Vehicle_Type__c` is blank | (a) required for quoting; (b) cheapest eligible card | (a) |
| Q12 | **Approval threshold base**: "percentage of gross freight" | (a) gross = base + weight + distance + fuel + insurance + positive additional lines, before discount and tax; (b) also include tax | (a) |
| Q13 | **Two discount mechanisms** exist: header `Discount__c` and negative `Discount`-type lines | (a) both count toward the threshold: total discount = `Discount__c` + abs(discount lines); (b) forbid discount lines (Phase 1 change) | (a) |
| Q14 | **`Quotation_Line__c.Is_Taxable__c` is ignored**: the deployed `Tax_Amount__c` formula taxes every line | (a) make the formula honour it with a taxable-lines roll-up (Phase 1 model change: 1 roll-up field and 2 formula edits); (b) document "all charges are taxable" and leave it | Your call. (a) is more correct but changes Phase 1 metadata. (b) changes nothing. |
| Q15 | **Rounding** | Each component rounded to 2 decimals, half-up, before saving; Apex never computes the total, it reads the formula | Adopt |
| Q16 | **Tax overrides** (the setting mentions "rate card or customer override", but no such fields exist) | (a) default setting only; (b) add override fields (Phase 1 change) | (a) |

### 3.3 Approval and integrity questions

| # | Question | **[R]** Recommendation |
|---|---|---|
| Q17 | May an approver approve **their own** quotation? | No (segregation of duties). Approval by the quotation owner is rejected even with the permission. |
| Q18 | After approval, may the discount or lines change? | No. Changing `Discount__c`, or any line, on a quotation that is not Draft is rejected; a revision is required. Lines are protected by a validation rule on `Quotation_Line__c` (parent status must be Draft or Pending Approval). That is a **Phase 1 model addition** needing your approval, or alternatively a `Quotation_Line__c` trigger. |
| Q19 | Can a quotation **within** the threshold go straight Draft → Sent without approval? | Yes. Approval is only required above the threshold. The P5 Flow will auto-approve; until then Apex simply does not demand approval below the threshold. |
| Q20 | One conversion per quotation (if Q1 is in scope) | Lock the quotation row (`FOR UPDATE`), refuse when a shipment with that `Quotation__c` already exists, and convert only `Accepted`, unexpired quotations. |

## 4. Proposed architecture

It follows the Phase 2 conventions exactly ([APEX_FRAMEWORK.md](APEX_FRAMEWORK.md)): one trigger per object, a thin handler, a domain for rules, services for use cases, selectors for SOQL, `ServiceResult` for per-record outcomes, labels for messages, and no bypass switches or static recursion flags.

### 4.1 Components

```mermaid
flowchart TB
    subgraph pricing
        FCS[FreightCalculationService<br/>quote(List&lt;FreightRequest&gt;)]
        FR[FreightRequest / FreightBreakdown DTOs]
    end
    subgraph crm
        QS[QuotationService<br/>createFromRequests · recalculate · submit · approve · convertToShipment*]
        QD[QuotationDomain<br/>money-safety rules]
    end
    subgraph selectors
        RCS[RateCardSelector]
        SRS[ShipmentRequestSelector]
        QSEL[QuotationSelector]
    end
    QT[QuotationTrigger] --> QH[QuotationTriggerHandler] --> QD
    QS --> FCS --> RCS
    QS --> SRS
    QS --> QSEL
    QS -->|*Q1: insert Shipment__c, status Quoted| ST[ShipmentTrigger - Phase 2, unchanged]
    FCS --> SET[SettingsService]
    QS --> PS[PermissionService]
```

`*` marks Q1, which is pending your decision.

| Class | Folder | Sharing | Responsibility |
|---|---|---|---|
| `FreightRequest`, `FreightBreakdown` | pricing | inherited | DTOs from API_SPECIFICATION. Request: vehicle type, weight, distance, declared value, pricing date, BU, region. Breakdown: rate card Id, every component, minimum uplift, tax %, gross, plus error code and message when unpriceable. |
| `FreightCalculationService` | pricing | with | `quote(List<FreightRequest>)`: selects the card (1 SOQL for the batch through `RateCardSelector`), then does the arithmetic. No DML. Pure arithmetic is in a `@TestVisible` method for exhaustive unit tests. |
| `RateCardSelector` | selectors | inherited | One user-mode query: active cards for the vehicle types in the batch, overlapping the min and max pricing dates. Ranking happens in Apex per request, so there is no SOQL per record. |
| `ShipmentRequestSelector`, `QuotationSelector` | selectors | inherited | User-mode reads; `FOR UPDATE` variants where a status changes. |
| `QuotationService` | crm | with | Use cases with per-record `ServiceResult` (see 4.3). |
| `QuotationDomain` | crm | with | Before-save rules on every entry path (see 4.4). |
| `QuotationTriggerHandler` | handlers | with | Routes contexts to `QuotationDomain`. |
| `QuotationTrigger` | triggers | n/a | `new QuotationTriggerHandler().run();` |

**[R]** The folder `crm/` matches CLAUDE.md section 7. Requests and quotations are commercial-intake objects; pricing arithmetic stays in `pricing/`.

### 4.2 Data flow: create quotations from requests

1. **Authorize.**
   - The user must be able to create `Quotation__c` (describe check), otherwise `AuthorizationException`.
   - Requests are read in user mode (`ShipmentRequestSelector`, which includes `Route__r.Distance__c`, `Customer__r.Is_Active_Customer__c` and `Business_Unit__r.Region__c`). A request the user cannot see gets `REQUEST_NOT_FOUND`.
2. **Check each request:**
   - status is `Submitted` or `Under Review` (Q21 decided);
   - customer is active;
   - route present (Q8), weight present, vehicle type present (Q11).
3. **Price:** `FreightCalculationService.quote(...)` for the valid ones: 1 SOQL plus 0-SOQL settings. Unpriceable ones (no card, ambiguous card) get per-record errors.
4. **Write:**
   - Insert quotations with partial success. `Discount__c` = 0, `Status__c` = Draft, `Valid_Until__c` = today + validity, components and `Tax_Percent__c` = setting.
   - This uses **system mode** for the protected fields only, after step 1. It runs `with sharing`; the user becomes the owner.
5. **Request status (Q4):**
   - Update succeeded requests to `Quoted` with partial success.
   - For any request whose update fails, delete its just-inserted quotation in the same transaction, and report that request only. This is the per-record compensation pattern adopted for Phase 6 in TRACKING_IMPLEMENTATION section 5.1, so there is **no batch-wide rollback**.
6. Return a `ServiceResult` with per-request errors and the created quotation Ids.

Cost for 200 requests: 2 SOQL (requests, rate cards) and 2 to 3 DML statements.

### 4.3 `QuotationService` API (proposed)

```apex
public with sharing class QuotationService {
    public ServiceResult createFromRequests(List<Id> shipmentRequestIds);   // 4.2
    public ServiceResult recalculate(List<Id> quotationIds);                // = API_SPECIFICATION applyToQuotations; Draft only; re-snapshots components
    public ServiceResult submitForApproval(List<Id> quotationIds);          // Draft -> Pending Approval (above threshold) or -> Approved (at or below threshold, no stamp needed)
    public ServiceResult approve(List<Id> quotationIds);                    // needs eLogix_Approve_Quotation; not the owner (Q17); writes the stamp in system mode
    public ServiceResult reject(List<Id> quotationIds, String reason);      // Pending Approval -> Draft (or Rejected; see Q22)
    public ServiceResult convertToShipment(List<Id> quotationIds);          // only if Q1 is approved
}
```

The Phase 5 Flow and the Phase 7 LWC call these methods. Phase 3 adds **no** `@AuraEnabled` or `@InvocableMethod` entry points: those are added with their consumers, keeping the external surface at zero, as in Phase 2.

### 4.4 `QuotationDomain` rules (before insert / before update, every entry path)

| Rule | Why it must be in a trigger and not only the service |
|---|---|
| D-1 | A quotation can move to `Sent` or `Accepted` only when its discount is at or below the threshold, **or** it carries an approval stamp. `Discount__c` is user-editable and Sales can update the status directly, so only a trigger closes this hole. |
| D-2 | On a quotation that is not Draft, `Discount__c` cannot change (Q18). |
| D-3 | The approval stamp is cleared, and the status returns to Draft, if a Draft re-price changes the discount after approval. Recommendation only; depends on Q18. |
| D-4 | `Status__c = Approved` is reachable only through `QuotationService.approve` or the at-or-below-threshold path, because only those write the stamp. Users with direct status edit cannot self-approve above the threshold, because D-1 checks the stamp, not the status label. |

**Technical note.** Formula fields (`Subtotal__c` and the rest) in `Trigger.new` do not reflect changes made in the same save. The domain therefore computes the threshold from stored components, or calls `Formula.recalculateFormulas()`, plus the `Line_Total__c` roll-up, which is current. Both are 0-SOQL. Line totals need the lines; `Line_Total__c` gives the net sum, but Q13 needs the discount lines separately. **[R]** One aggregate query per batch, only when a threshold check is actually needed.

### 4.5 Conversion (only if Q1 is approved)

1. Lock the quotations (`FOR UPDATE`).
2. Require `Accepted`, unexpired, and no existing `Shipment__c` with that `Quotation__c` (one SOQL).
3. Insert shipments: status `Quoted`, `Freight_Amount__c` = `Total_Amount__c` (protected, so system mode); weight and distance from the request and route; pickup and expected-delivery dates from the request. `ShipmentTrigger` then writes the `Created` event through Phase 2, unchanged.
4. Set the request to `Converted`.
5. Per-record compensation as in 4.2.

**Note:** under Private OWD, Operations users cannot see Sales-owned quotations until Phase 9 sharing. In Phase 3 the converter is the quotation owner or a View All role (Logistics Manager, Admin).

## 5. Security

| Concern | Design |
|---|---|
| Who can quote | Users with Create on `Quotation__c` (Sales, Logistics Manager, Admin). Others get `ACCESS_DENIED`, checked by describe, not by assumption. |
| Protected fields | Components, `Rate_Card__c`, `Tax_Percent__c`, `Version__c` and the stamp are written only by `QuotationService` in system mode, after the access checks. Users still cannot type them (FLS). |
| Sharing | All new classes are `with sharing`. **No `without sharing` code is proposed.** Requests and quotations are read in user mode; creating a quotation makes the user its owner. |
| Approval | Requires `eLogix_Approve_Quotation` (through `PermissionService`) plus Q17 (not the owner). The stamp uses `UserInfo.getUserId()` and `System.now()`; it cannot be supplied by the caller. |
| Discount bypass | D-1 and D-2 apply to UI, API, Data Loader and future Flows. Line edits need Q18's validation rule or trigger. |
| External surface | None added: no `@AuraEnabled` methods, REST or invocables in Phase 3. |
| Logging | Ids, codes and counts only. Never prices, discounts or customer names. |

## 6. Test strategy

New test classes (no `SeeAllData`; role users from `TestDataFactory`; no production test switches; settings through `SettingsService.testOverrides`):

| Class | Scenarios |
|---|---|
| `FreightCalculationServiceTest` | Formula per component (Chennai → Bangalore, 350 km, 500 kg, LCV card); percent ÷ 100 exactly once (12 → 0.12); minimum uplift on and off (Q7); fuel and insurance bases (Q5, Q6); zero, blank and boundary values; rounding to 2 dp; **the Apex breakdown matches the deployed formula totals** after insert (catches drift between Apex and formulas) |
| `RateCardSelectionTest` | Vehicle type match; inactive excluded; effective-from and effective-to boundaries inclusive on the pricing date (Q9); BU and region specificity (Q10); lowest priority wins; equal top candidates → `RATE_CARD_AMBIGUOUS`; none → `RATE_CARD_NOT_FOUND`; 200 requests across 3 vehicle types → **1 SOQL** |
| `QuotationServiceTest` | Create from 200 requests (bulk: SOQL and DML counted); protected fields populated; `Valid_Until__c` = today + setting; tax from setting; Sales allowed, Operations / Customer Service denied; invisible request → `REQUEST_NOT_FOUND`; inactive customer, missing route, missing vehicle type and ineligible status each rejected per record; **per-record compensation** (one request whose status update fails does not undo the others); recalculate only in Draft; submit at, just above and well above the threshold (10.00% versus 10.01%); approve with and without the permission, and as owner (Q17); reject |
| `QuotationTriggerHandlerTest` | D-1 to D-4 through direct DML as Sales (not through the service): Sent above the threshold without a stamp rejected; with a stamp allowed; discount change after Draft rejected; 200-row update without a relevant change costs 0 SOQL |
| `QuotationConversionTest` (Q1) | Accepted → shipment with status `Quoted` and the `Created` tracking event (Phase 2 integration); `Freight_Amount__c` = total; request `Converted`; second conversion refused; expired or not-accepted refused; bulk 200 |
| Regression | All 79 Phase 2 tests unchanged and passing; both verification scripts |

A new rolled-back script `scripts/apex/verify-phase3-pricing.apex` checks the end-to-end chain against live configuration: rate card → quotation → formula totals → approval gate → (Q1) conversion → tracking event.

## 7. Acceptance criteria

1. Freight for the reference lane equals a hand-calculated expected value, component by component, and `Total_Amount__c` (formula) equals the breakdown total.
2. Selection is deterministic: the same inputs always choose the same card; ambiguity and absence fail closed with labelled messages.
3. No pricing number is hardcoded in Apex (verified by code review and by tests that change settings and cards).
4. A quotation above the threshold cannot reach `Sent` or `Accepted` without a valid stamp, through any entry path.
5. Only `eLogix_Approve_Quotation` holders, other than the owner, can approve.
6. Bulk (200): 3 SOQL for create (see section 0.1, item 6), 1 SOQL for pricing; no SOQL or DML in loops.
7. Per-record failures never roll back unrelated records.
8. All tests pass; coverage of the new classes is at least 85% (Phase 2 achieved 98.5%); Phase 1 and Phase 2 verification scripts still pass.
9. Phase 1 metadata unchanged unless Q14 or Q18 approve a specific model change, made through the generator and validated separately.

## 8. Files expected to change

| Kind | Files |
|---|---|
| New Apex (about 10 production, 4 to 5 test) | `classes/pricing/FreightCalculationService`, `FreightRequest`, `FreightBreakdown`; `classes/crm/QuotationService`, `QuotationDomain`; `classes/handlers/QuotationTriggerHandler`; `classes/selectors/RateCardSelector`, `ShipmentRequestSelector`, `QuotationSelector`; `triggers/QuotationTrigger`; tests in `classes/test/` (see section 6) |
| Modified Apex | `classes/test/TestDataFactory.cls` (rate card, route, request and quotation builders). **No Phase 2 production class changes.** |
| Labels | `labels/CustomLabels.labels-meta.xml`: about 12 new labels (rate card not found or ambiguous, route required, vehicle type required, customer inactive, request status ineligible, approval required, cannot approve own, discount locked, already converted, quotation not accepted or expired) |
| Model (only if approved) | Q18: 1 validation rule on `Quotation_Line__c` (via `scripts/node/model/elogix-validation.mjs` and the generator). Q14: 1 roll-up and 2 formula edits on `Quotation__c` (via `elogix-datamodel.mjs`). |
| Scripts | `scripts/apex/verify-phase3-pricing.apex` |
| Docs | New `docs/PRICING_IMPLEMENTATION.md` and `docs/PHASE3_IMPLEMENTATION_REPORT.md`; updates to `APEX_TEST_MATRIX`, `BUSINESS_RULES` (statuses P3 → Live), `API_SPECIFICATION`, `SOLUTION_ARCHITECTURE` (package structure), `DEPLOYMENT_GUIDE`, `DEMO_SCRIPT` (step 3), `PROJECT_STATUS` |
| Permission sets | None expected. Apex class access is needed only when LWCs call Apex (Phase 7). |

## 9. Implementation sequence (after approval)

1. **Decisions:** record your answers to Q1 to Q22 in this document. Any Phase 1 model change (Q14, Q18) is made first, through the generator, `npm run metadata:validate`, and a separate check-only deploy.
2. **Pricing core:** DTOs, `RateCardSelector`, `FreightCalculationService` and their tests. These are pure, so they can be verified first.
3. **Factory and selectors:** `TestDataFactory` builders, `ShipmentRequestSelector`, `QuotationSelector`.
4. **`QuotationService.createFromRequests` and `recalculate`,** with compensation and tests.
5. **`QuotationDomain` and trigger,** then `submitForApproval`, `approve` and `reject`, with tests.
6. **(Q1) `convertToShipment`** with Phase 2 integration tests.
7. **Labels and the verification script.**
8. **Validator,** then check-only deploy (`RunLocalTests`), then fix, then **one** real deploy, then both earlier verification scripts plus the Phase 3 script.
9. **Docs and `PROJECT_STATUS.md`;** report, then wait for commit approval.

## 10. Risks and dependencies

| Risk | Impact | Mitigation |
|---|---|---|
| Unresolved Q5 to Q16 | Wrong prices in the demo | Do not implement pricing arithmetic until they are answered |
| Apex and formula divergence (percent units, rounding) | The breakdown shown in the UI disagrees with `Total_Amount__c` | Components rounded before saving; Apex never computes the stored total; a test asserts breakdown total = formula total |
| Formula fields stale in before triggers | Threshold check on old values | Compute from stored components and roll-up, or `Formula.recalculateFormulas()`; tested by direct-DML domain tests |
| Private OWD until Phase 9 | Operations cannot see Sales quotations; conversion and demo persona friction | Document; convert as owner or View All role in Phase 3; Phase 9 sharing |
| `Is_Taxable__c` ignored (Q14) | Non-taxable charges are taxed | Your decision; documented either way |
| Discount through lines after approval (Q18) | Approval bypass | Validation rule or line trigger, per Q18 |
| 5 MB storage | Bulk tests are fine (rolled back); demo data stays small | Plan for about 15 quotations and 40 lines in Phase 9 |
| Two-day schedule | Phase 3 is on the critical path (P1 → P2 → P3 → P5) | Q1 and Q3 can be deferred to keep Phase 3 lean |

## 11. Remaining open questions

| # | Question |
|---|---|
| Q21 | Which request statuses may be quoted? **Decided:** `Submitted` and `Under Review` only (see section 0). |
| Q22 | Does rejecting an approval set the quotation to `Rejected` (terminal) or back to `Draft` (editable)? **Decided:** `Draft`, with the reason in `Notes__c` (see section 0). |

Summary of decisions needed: Q1 to Q4 (scope), Q5 to Q16 (pricing), Q17 to Q20 (approval and integrity), Q21 and Q22 (statuses). Recommendations are given for each, so you can approve them all in one reply, or change only the ones you disagree with.
