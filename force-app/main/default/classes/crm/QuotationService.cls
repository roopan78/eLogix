/**
 * Quotation use cases: create from shipment requests, recalculate, submit, approve, reject and
 * convert to a shipment. Results are per record (ServiceResult); one record's failure never undoes
 * another's. Business rules that must hold on every entry path live in QuotationDomain (trigger);
 * pricing arithmetic lives in FreightCalculationService. See docs/PRICING_IMPLEMENTATION.md.
 *
 * Writes of protected fields (price components, approval stamp, Freight_Amount__c) use system mode,
 * after explicit checks: object access by describe, record access by a user-mode read, the custom
 * permission where one applies, and the business state.
 */
public with sharing class QuotationService {
  public static final String REQUEST_INVALID = 'REQUEST_INVALID';
  public static final String REQUEST_NOT_FOUND = 'REQUEST_NOT_FOUND';
  public static final String CUSTOMER_INACTIVE = 'CUSTOMER_INACTIVE';
  public static final String ROUTE_REQUIRED = 'ROUTE_REQUIRED';
  public static final String VEHICLE_TYPE_REQUIRED = 'VEHICLE_TYPE_REQUIRED';
  public static final String WEIGHT_REQUIRED = 'WEIGHT_REQUIRED';
  public static final String QUOTATION_NOT_FOUND = 'QUOTATION_NOT_FOUND';
  public static final String QUOTATION_NOT_DRAFT = 'QUOTATION_NOT_DRAFT';
  public static final String QUOTATION_NOT_PENDING = 'QUOTATION_NOT_PENDING';
  public static final String SELF_APPROVAL = 'SELF_APPROVAL';
  public static final String REASON_REQUIRED = 'REASON_REQUIRED';
  public static final String QUOTATION_NOT_CONVERTIBLE = 'QUOTATION_NOT_CONVERTIBLE';
  public static final String QUOTATION_ALREADY_CONVERTED = 'QUOTATION_ALREADY_CONVERTED';
  public static final String REQUEST_NOT_APPROVED = 'REQUEST_NOT_APPROVED';

  @TestVisible
  private static final String VALIDITY_SETTING = 'Quotation_Validity_Days';
  private static final String SHIPMENT_INITIAL_STATUS = 'Quoted';
  private static final String REQUEST_APPROVED = 'Approved';
  private static final String REQUEST_CONVERTED = 'Converted';
  private static final String CONTEXT = 'QuotationService';

  /* ------------------------------------------------------------------ */
  /* Create and recalculate                                              */
  /* ------------------------------------------------------------------ */

  /**
   * Prices each request and creates one Draft quotation for it. Request eligibility (Submitted or
   * Under Review) and the request's move to Quoted are enforced by the quotation trigger, so they
   * hold on every entry path; a request that cannot move fails only its own quotation.
   */
  public ServiceResult createFromRequests(List<Id> shipmentRequestIds) {
    ServiceResult result = new ServiceResult();
    if (shipmentRequestIds == null || shipmentRequestIds.isEmpty()) {
      return result;
    }
    requireAccess(Schema.SObjectType.Quotation__c.isCreateable());
    Integer validityDays = SettingsService.getNumber(VALIDITY_SETTING)
      .intValue();

    Map<Id, Shipment_Request__c> requests = new ShipmentRequestSelector()
      .selectForQuotation(nonNull(shipmentRequestIds));
    List<FreightRequest> pricing = new List<FreightRequest>();
    List<Integer> pricingIndexes = new List<Integer>();
    Set<Id> seen = new Set<Id>();
    for (Integer i = 0; i < shipmentRequestIds.size(); i++) {
      Id requestId = shipmentRequestIds[i];
      if (requestId == null || !seen.add(requestId)) {
        result.addError(
          REQUEST_INVALID,
          format(Label.eLogix_Request_Invalid, i + 1),
          i,
          requestId
        );
        continue;
      }
      Shipment_Request__c request = requests.get(requestId);
      if (request == null) {
        result.addError(
          REQUEST_NOT_FOUND,
          format(Label.eLogix_Request_Not_Found, requestId),
          i,
          requestId
        );
        continue;
      }
      if (addPricingProblem(result, request, i)) {
        continue;
      }
      pricing.add(
        toFreightRequest(
          request,
          request.Business_Unit__r?.Region__c,
          request.Route__r?.Distance__c
        )
      );
      pricingIndexes.add(i);
    }

    List<FreightBreakdown> breakdowns = new FreightCalculationService()
      .quote(pricing);
    List<Quotation__c> inserts = new List<Quotation__c>();
    List<Integer> insertIndexes = new List<Integer>();
    for (Integer j = 0; j < breakdowns.size(); j++) {
      FreightBreakdown breakdown = breakdowns[j];
      Integer index = pricingIndexes[j];
      if (!breakdown.isPriced) {
        result.addError(
          breakdown.errorCode,
          breakdown.errorMessage,
          index,
          shipmentRequestIds[index]
        );
        continue;
      }
      Quotation__c quotation = new Quotation__c(
        Shipment_Request__c = shipmentRequestIds[index],
        Status__c = QuotationDomain.DRAFT,
        Discount__c = 0,
        Valid_Until__c = Date.today().addDays(validityDays)
      );
      applyComponents(quotation, breakdown);
      inserts.add(quotation);
      insertIndexes.add(index);
    }
    // System mode for the protected price components only; the user's access was checked above.
    recordSaveResults(
      result,
      Database.insert(inserts, false, AccessLevel.SYSTEM_MODE),
      insertIndexes,
      shipmentRequestIds
    );
    Logger.info(
      CONTEXT,
      'createFromRequests requested=' +
        shipmentRequestIds.size() +
        ' created=' +
        result.recordIds.size()
    );
    return result;
  }

  /** Re-prices Draft quotations in place from the current request and rate cards (decision Q3). */
  public ServiceResult recalculate(List<Id> quotationIds) {
    ServiceResult result = new ServiceResult();
    if (quotationIds == null || quotationIds.isEmpty()) {
      return result;
    }
    requireAccess(Schema.SObjectType.Quotation__c.isUpdateable());
    Map<Id, Quotation__c> quotations = new QuotationSelector()
      .selectForUpdate(nonNull(quotationIds));

    List<FreightRequest> pricing = new List<FreightRequest>();
    List<Integer> pricingIndexes = new List<Integer>();
    for (Integer i = 0; i < quotationIds.size(); i++) {
      Quotation__c quotation = quotations.get(quotationIds[i]);
      if (quotation == null) {
        result.addError(
          QUOTATION_NOT_FOUND,
          format(Label.eLogix_Quotation_Not_Found, quotationIds[i]),
          i,
          quotationIds[i]
        );
        continue;
      }
      if (!QuotationDomain.DRAFT.equals(quotation.Status__c)) {
        result.addError(
          QUOTATION_NOT_DRAFT,
          format(Label.eLogix_Quotation_Not_Draft, quotation.Name),
          i,
          quotation.Id
        );
        continue;
      }
      Shipment_Request__c request = quotation.Shipment_Request__r;
      if (addPricingProblem(result, request, i)) {
        continue;
      }
      pricing.add(
        toFreightRequest(
          request,
          request.Business_Unit__r?.Region__c,
          request.Route__r?.Distance__c
        )
      );
      pricingIndexes.add(i);
    }

    List<FreightBreakdown> breakdowns = new FreightCalculationService()
      .quote(pricing);
    List<Quotation__c> updates = new List<Quotation__c>();
    List<Integer> updateIndexes = new List<Integer>();
    for (Integer j = 0; j < breakdowns.size(); j++) {
      Integer index = pricingIndexes[j];
      if (!breakdowns[j].isPriced) {
        result.addError(
          breakdowns[j].errorCode,
          breakdowns[j].errorMessage,
          index,
          quotationIds[index]
        );
        continue;
      }
      Quotation__c change = new Quotation__c(Id = quotationIds[index]);
      applyComponents(change, breakdowns[j]);
      updates.add(change);
      updateIndexes.add(index);
    }
    // System mode for the protected components; sharing still applies, so only editable quotations change.
    recordSaveResults(
      result,
      Database.update(updates, false, AccessLevel.SYSTEM_MODE),
      updateIndexes,
      quotationIds
    );
    return result;
  }

  /* ------------------------------------------------------------------ */
  /* Approval                                                            */
  /* ------------------------------------------------------------------ */

  /**
   * Draft -> Approved when the discount is within the threshold (automatic path, decision Q19),
   * otherwise Draft -> Pending Approval. Runs in user mode: the owner submits their own quotation.
   */
  public ServiceResult submitForApproval(List<Id> quotationIds) {
    ServiceResult result = new ServiceResult();
    if (quotationIds == null || quotationIds.isEmpty()) {
      return result;
    }
    requireAccess(Schema.SObjectType.Quotation__c.isUpdateable());
    Map<Id, Quotation__c> quotations = new QuotationSelector()
      .selectForUpdate(nonNull(quotationIds));
    Map<Id, Decimal> discountLines = new QuotationSelector()
      .sumDiscountLines(quotations.keySet());

    List<Quotation__c> updates = new List<Quotation__c>();
    List<Integer> updateIndexes = new List<Integer>();
    for (Integer i = 0; i < quotationIds.size(); i++) {
      Quotation__c quotation = quotations.get(quotationIds[i]);
      if (quotation == null) {
        result.addError(
          QUOTATION_NOT_FOUND,
          format(Label.eLogix_Quotation_Not_Found, quotationIds[i]),
          i,
          quotationIds[i]
        );
        continue;
      }
      if (!QuotationDomain.DRAFT.equals(quotation.Status__c)) {
        result.addError(
          QUOTATION_NOT_DRAFT,
          format(Label.eLogix_Quotation_Not_Draft, quotation.Name),
          i,
          quotation.Id
        );
        continue;
      }
      Boolean withinThreshold = FreightCalculationService.isDiscountWithinThreshold(
        freightCharges(quotation),
        quotation.Line_Total__c,
        discountLines.get(quotation.Id),
        quotation.Discount__c
      );
      updates.add(
        new Quotation__c(
          Id = quotation.Id,
          Status__c = withinThreshold
            ? QuotationDomain.APPROVED
            : QuotationDomain.PENDING_APPROVAL
        )
      );
      updateIndexes.add(i);
    }
    recordSaveResults(
      result,
      Database.update(updates, false, AccessLevel.USER_MODE),
      updateIndexes,
      quotationIds
    );
    return result;
  }

  /**
   * Pending Approval -> Approved with the approval stamp. Needs eLogix_Approve_Quotation; the
   * approver must be able to read the quotation and must not own it (decision Q17). The stamp is
   * re-verified by QuotationDomain, which also sets the approval time.
   */
  public ServiceResult approve(List<Id> quotationIds) {
    return decide(quotationIds, true, null);
  }

  /** Pending Approval -> Draft with the reason appended to Notes__c (decision Q22). Approvers only. */
  public ServiceResult reject(List<Id> quotationIds, String reason) {
    return decide(quotationIds, false, reason);
  }

  private ServiceResult decide(
    List<Id> quotationIds,
    Boolean approve,
    String reason
  ) {
    ServiceResult result = new ServiceResult();
    if (quotationIds == null || quotationIds.isEmpty()) {
      return result;
    }
    requireAccess(
      PermissionService.hasPermission(QuotationDomain.APPROVE_PERMISSION)
    );
    if (!approve && String.isBlank(reason)) {
      for (Integer i = 0; i < quotationIds.size(); i++) {
        result.addError(
          REASON_REQUIRED,
          Label.eLogix_Quotation_Reason_Required,
          i,
          quotationIds[i]
        );
      }
      return result;
    }
    Id approver = UserInfo.getUserId();
    Map<Id, Quotation__c> quotations = new QuotationSelector()
      .selectForUpdate(nonNull(quotationIds));

    List<Quotation__c> updates = new List<Quotation__c>();
    List<Integer> updateIndexes = new List<Integer>();
    for (Integer i = 0; i < quotationIds.size(); i++) {
      Quotation__c quotation = quotations.get(quotationIds[i]);
      if (quotation == null) {
        result.addError(
          QUOTATION_NOT_FOUND,
          format(Label.eLogix_Quotation_Not_Found, quotationIds[i]),
          i,
          quotationIds[i]
        );
        continue;
      }
      if (!QuotationDomain.PENDING_APPROVAL.equals(quotation.Status__c)) {
        result.addError(
          QUOTATION_NOT_PENDING,
          format(Label.eLogix_Quotation_Not_Pending, quotation.Name),
          i,
          quotation.Id
        );
        continue;
      }
      if (approve && quotation.OwnerId == approver) {
        result.addError(
          SELF_APPROVAL,
          Label.eLogix_Quotation_Self_Approval,
          i,
          quotation.Id
        );
        continue;
      }
      Quotation__c change = new Quotation__c(Id = quotation.Id);
      if (approve) {
        change.Status__c = QuotationDomain.APPROVED;
        change.Approved_By__c = approver;
        change.Approval_Date__c = System.now();
      } else {
        change.Status__c = QuotationDomain.DRAFT;
        String note = format(
          Label.eLogix_Quotation_Rejection_Note,
          reason.trim()
        );
        change.Notes__c = String.isBlank(quotation.Notes__c)
          ? note
          : quotation.Notes__c + '\n' + note;
      }
      updates.add(change);
      updateIndexes.add(i);
    }
    recordSaveResults(
      result,
      new Writer().updateQuotations(updates),
      updateIndexes,
      quotationIds
    );
    return result;
  }

  /* ------------------------------------------------------------------ */
  /* Conversion (decisions Q1, Q4, Q20)                                  */
  /* ------------------------------------------------------------------ */

  /**
   * Creates one shipment (status Quoted) per accepted, unexpired quotation and moves its request
   * from Approved to Converted. The quotation row lock plus the existing-shipment check give one
   * shipment per quotation; the request row lock and a status re-check under that lock keep a
   * request that someone else changed from being overwritten (follow-up A3). The shipment lane (origin, destination, distance) comes from the route
   * that priced the quotation; weight and dates come from the request. ShipmentTrigger (Phase 2)
   * applies the lifecycle policy and writes the Created tracking event. A shipment whose request
   * cannot move is deleted again in the same transaction, and only that record is reported.
   */
  public ServiceResult convertToShipment(List<Id> quotationIds) {
    ServiceResult result = new ServiceResult();
    if (quotationIds == null || quotationIds.isEmpty()) {
      return result;
    }
    requireAccess(Schema.SObjectType.Shipment__c.isCreateable());
    QuotationSelector selector = new QuotationSelector();
    Map<Id, Quotation__c> quotations = selector.selectForUpdate(
      nonNull(quotationIds)
    );
    Set<Id> converted = selector.selectConvertedQuotationIds(
      quotations.keySet()
    );

    // A3: lock the requests and re-read their status under the lock, so a request that someone
    // else changed (for example to Cancelled) is never overwritten with Converted. Locks are
    // taken quotation first, then request, the same order as the quotation trigger.
    Set<Id> requestIds = new Set<Id>();
    for (Quotation__c quotation : quotations.values()) {
      requestIds.add(quotation.Shipment_Request__c);
    }
    Map<Id, Shipment_Request__c> lockedRequests = new ShipmentRequestSelector()
      .selectStatusForUpdate(requestIds);

    List<Shipment__c> shipments = new List<Shipment__c>();
    List<Integer> shipmentIndexes = new List<Integer>();
    Set<Id> seen = new Set<Id>();
    for (Integer i = 0; i < quotationIds.size(); i++) {
      Id quotationId = quotationIds[i];
      Quotation__c quotation = quotations.get(quotationId);
      if (quotation == null) {
        result.addError(
          QUOTATION_NOT_FOUND,
          format(Label.eLogix_Quotation_Not_Found, quotationId),
          i,
          quotationId
        );
        continue;
      }
      if (converted.contains(quotation.Id) || !seen.add(quotation.Id)) {
        result.addError(
          QUOTATION_ALREADY_CONVERTED,
          format(Label.eLogix_Quotation_Already_Converted, quotation.Name),
          i,
          quotation.Id
        );
        continue;
      }
      if (
        !QuotationDomain.ACCEPTED.equals(quotation.Status__c) ||
        quotation.Is_Expired__c
      ) {
        result.addError(
          QUOTATION_NOT_CONVERTIBLE,
          format(Label.eLogix_Quotation_Not_Convertible, quotation.Name),
          i,
          quotation.Id
        );
        continue;
      }
      Shipment_Request__c request = quotation.Shipment_Request__r;
      Shipment_Request__c locked = lockedRequests.get(request.Id);
      String currentStatus = locked == null ? null : locked.Status__c;
      if (!REQUEST_APPROVED.equals(currentStatus)) {
        result.addError(
          REQUEST_NOT_APPROVED,
          String.format(
            Label.eLogix_Request_Not_Approved,
            new List<Object>{ request.Name, currentStatus }
          ),
          i,
          quotation.Id
        );
        continue;
      }
      if (request.Route__c == null) {
        result.addError(
          ROUTE_REQUIRED,
          format(Label.eLogix_Request_Route_Required, request.Name),
          i,
          quotation.Id
        );
        continue;
      }
      shipments.add(
        new Shipment__c(
          Shipment_Request__c = request.Id,
          Quotation__c = quotation.Id,
          Customer__c = request.Customer__c,
          Business_Unit__c = request.Business_Unit__c,
          Route__c = request.Route__c,
          Origin__c = request.Route__r.Origin__c,
          Destination__c = request.Route__r.Destination__c,
          Distance__c = request.Route__r.Distance__c,
          Weight__c = request.Total_Weight__c,
          Pickup_Date__c = request.Requested_Pickup_Date__c,
          Expected_Delivery_Date__c = request.Expected_Delivery_Date__c,
          Priority__c = request.Priority__c,
          Special_Instructions__c = request.Special_Instructions__c,
          Freight_Amount__c = quotation.Total_Amount__c,
          Status__c = SHIPMENT_INITIAL_STATUS
        )
      );
      shipmentIndexes.add(i);
    }

    // System mode for the protected Freight_Amount__c only; shipment create access was checked above.
    List<Database.SaveResult> inserted = Database.insert(
      shipments,
      false,
      AccessLevel.SYSTEM_MODE
    );
    List<Shipment_Request__c> requestUpdates = new List<Shipment_Request__c>();
    List<Integer> requestIndexes = new List<Integer>();
    List<Id> createdShipmentIds = new List<Id>();
    for (Integer j = 0; j < inserted.size(); j++) {
      Integer index = shipmentIndexes[j];
      if (!inserted[j].isSuccess()) {
        addSaveErrors(result, inserted[j], index, quotationIds[index]);
        continue;
      }
      requestUpdates.add(
        new Shipment_Request__c(
          Id = shipments[j].Shipment_Request__c,
          Status__c = REQUEST_CONVERTED
        )
      );
      requestIndexes.add(index);
      createdShipmentIds.add(inserted[j].getId());
    }

    Writer writer = new Writer();
    List<Database.SaveResult> requestResults = writer.updateRequests(
      requestUpdates
    );
    List<Id> orphanedShipments = new List<Id>();
    for (Integer k = 0; k < requestResults.size(); k++) {
      Integer index = requestIndexes[k];
      if (requestResults[k].isSuccess()) {
        result.addRecordId(createdShipmentIds[k]);
      } else {
        orphanedShipments.add(createdShipmentIds[k]);
        addSaveErrors(result, requestResults[k], index, quotationIds[index]);
      }
    }
    writer.deleteShipments(orphanedShipments);
    Logger.info(
      CONTEXT,
      'convertToShipment requested=' +
        quotationIds.size() +
        ' converted=' +
        result.recordIds.size()
    );
    return result;
  }

  /* ------------------------------------------------------------------ */
  /* Helpers                                                             */
  /* ------------------------------------------------------------------ */

  /** Pricing prerequisites of a request (decisions Q8, Q11; active customer). Adds the error and returns true. */
  private static Boolean addPricingProblem(
    ServiceResult result,
    Shipment_Request__c request,
    Integer index
  ) {
    String code;
    String template;
    if (
      request.Customer__r == null ||
      request.Customer__r.Is_Active_Customer__c != true
    ) {
      code = CUSTOMER_INACTIVE;
      template = Label.eLogix_Request_Customer_Inactive;
    } else if (
      request.Route__c == null ||
      request.Route__r?.Distance__c == null
    ) {
      code = ROUTE_REQUIRED;
      template = Label.eLogix_Request_Route_Required;
    } else if (String.isBlank(request.Requested_Vehicle_Type__c)) {
      code = VEHICLE_TYPE_REQUIRED;
      template = Label.eLogix_Request_Vehicle_Type_Required;
    } else if (
      request.Total_Weight__c == null ||
      request.Total_Weight__c <= 0
    ) {
      code = WEIGHT_REQUIRED;
      template = Label.eLogix_Request_Weight_Required;
    }
    if (code == null) {
      return false;
    }
    result.addError(code, format(template, request.Name), index, request.Id);
    return true;
  }

  private static FreightRequest toFreightRequest(
    Shipment_Request__c request,
    String region,
    Decimal distance
  ) {
    FreightRequest pricing = new FreightRequest();
    pricing.key = request.Id;
    pricing.vehicleType = request.Requested_Vehicle_Type__c;
    pricing.weightKg = request.Total_Weight__c;
    pricing.distanceKm = distance;
    pricing.declaredValue = request.Declared_Value__c;
    pricing.pricingDate = request.Requested_Pickup_Date__c;
    pricing.businessUnitId = request.Business_Unit__c;
    pricing.region = region;
    return pricing;
  }

  private static void applyComponents(
    Quotation__c quotation,
    FreightBreakdown breakdown
  ) {
    quotation.Rate_Card__c = breakdown.rateCardId;
    quotation.Base_Freight__c = breakdown.baseFreight;
    quotation.Weight_Charge__c = breakdown.weightCharge;
    quotation.Distance_Charge__c = breakdown.distanceCharge;
    quotation.Fuel_Surcharge__c = breakdown.fuelSurcharge;
    quotation.Insurance_Charge__c = breakdown.insuranceCharge;
    quotation.Tax_Percent__c = breakdown.taxPercent;
  }

  private static Decimal freightCharges(Quotation__c quotation) {
    return orZero(quotation.Base_Freight__c) +
      orZero(quotation.Weight_Charge__c) +
      orZero(quotation.Distance_Charge__c) +
      orZero(quotation.Fuel_Surcharge__c) +
      orZero(quotation.Insurance_Charge__c);
  }

  private static void recordSaveResults(
    ServiceResult result,
    List<Database.SaveResult> saveResults,
    List<Integer> indexes,
    List<Id> inputIds
  ) {
    for (Integer j = 0; j < saveResults.size(); j++) {
      if (saveResults[j].isSuccess()) {
        result.addRecordId(saveResults[j].getId());
      } else {
        addSaveErrors(result, saveResults[j], indexes[j], inputIds[indexes[j]]);
      }
    }
  }

  private static void addSaveErrors(
    ServiceResult result,
    Database.SaveResult saveResult,
    Integer index,
    Id recordId
  ) {
    for (Database.Error error : saveResult.getErrors()) {
      result.addError(
        String.valueOf(error.getStatusCode()),
        error.getMessage(),
        index,
        recordId
      );
    }
  }

  private static void requireAccess(Boolean allowed) {
    if (!allowed) {
      throw new AuthorizationException(Label.eLogix_Access_Denied)
        .withCode(AuthorizationException.ACCESS_DENIED);
    }
  }

  private static Set<Id> nonNull(List<Id> ids) {
    Set<Id> result = new Set<Id>(ids);
    result.remove(null);
    return result;
  }

  private static String format(String template, Object value) {
    return String.format(template, new List<Object>{ value });
  }

  private static Decimal orZero(Decimal value) {
    return value == null ? 0 : value;
  }

  /**
   * The narrow system-mode writer preserves protected approval fields while honoring record sharing.
   * Phase 9 role hierarchy gives the Logistics Manager access to records owned by subordinate roles.
   * Every call follows explicit checks in this class: the approval permission (approve, reject) or
   * shipment create access (conversion), a user-mode read of each quotation, and the business state.
   * Only the approval fields and Notes__c (quotations), Status__c (requests), and the just-created
   * shipments (compensation) are written. QuotationDomain re-verifies the approval stamp.
   */
  private with sharing class Writer {
    public List<Database.SaveResult> updateQuotations(
      List<Quotation__c> quotations
    ) {
      if (quotations.isEmpty()) {
        return new List<Database.SaveResult>();
      }
      return Database.update(quotations, false, AccessLevel.SYSTEM_MODE);
    }

    public List<Database.SaveResult> updateRequests(
      List<Shipment_Request__c> requests
    ) {
      if (requests.isEmpty()) {
        return new List<Database.SaveResult>();
      }
      return Database.update(requests, false, AccessLevel.SYSTEM_MODE);
    }

    public void deleteShipments(List<Id> shipmentIds) {
      if (!shipmentIds.isEmpty()) {
        Database.delete(shipmentIds, true, AccessLevel.SYSTEM_MODE);
      }
    }
  }
}
