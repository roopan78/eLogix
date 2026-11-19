/**
 * Shipment use cases for UI and API callers.
 *
 * changeStatus performs a user-mode update, so CRUD, FLS and sharing apply to the caller. The
 * status policy itself is enforced by ShipmentTrigger, the single enforcement point for every
 * entry path; this service never re-implements it.
 */
public with sharing class ShipmentService {
    public static final String REQUEST_INVALID = 'REQUEST_INVALID';
    public static final String OPERATION_FAILED = 'OPERATION_FAILED';
    @TestVisible
    private static final String ON_HOLD = 'On Hold';
    @TestVisible
    private static final String CANCELLED = 'Cancelled';
    private static final String CONTEXT = 'ShipmentService.changeStatus';

    /**
     * Moves each shipment to its requested status. `reason` fills Hold_Reason__c for On Hold and
     * Cancellation_Reason__c for Cancelled. Results are per request (partial success).
     */
    public ServiceResult changeStatus(List<StatusChangeRequest> requests) {
        ServiceResult result = new ServiceResult();
        if (requests == null || requests.isEmpty()) {
            return result;
        }

        List<Shipment__c> updates = new List<Shipment__c>();
        List<Integer> requestIndexes = new List<Integer>();
        for (Integer i = 0; i < requests.size(); i++) {
            StatusChangeRequest request = requests[i];
            if (!isValid(request)) {
                result.addError(REQUEST_INVALID, String.format(Label.eLogix_Request_Invalid, new List<Object>{ i + 1 }), i, request?.shipmentId);
                continue;
            }
            Shipment__c shipment = new Shipment__c(Id = request.shipmentId, Status__c = request.targetStatus.trim());
            if (String.isNotBlank(request.reason) && ON_HOLD.equals(shipment.Status__c)) {
                shipment.Hold_Reason__c = request.reason;
            } else if (String.isNotBlank(request.reason) && CANCELLED.equals(shipment.Status__c)) {
                shipment.Cancellation_Reason__c = request.reason;
            }
            updates.add(shipment);
            requestIndexes.add(i);
        }
        if (updates.isEmpty()) {
            return result;
        }

        List<Database.SaveResult> saveResults;
        try {
            saveResults = Database.update(updates, false, AccessLevel.USER_MODE);
        } catch (Exception e) {
            // Defensive. With allOrNone=false, user-mode access failures come back as row errors in
            // saveResults and are handled below. Observed in ShipmentServiceTest: a Sales Executive with
            // no edit access to the shipment got a row error, not an exception. Any exception that does
            // occur is reported against every request rather than thrown to the caller.
            String message = ExceptionHandler.toUserMessage(e, CONTEXT);
            for (Integer j = 0; j < updates.size(); j++) {
                result.addError(OPERATION_FAILED, message, requestIndexes[j], updates[j].Id);
            }
            return result;
        }

        for (Integer j = 0; j < saveResults.size(); j++) {
            Database.SaveResult saveResult = saveResults[j];
            if (saveResult.isSuccess()) {
                result.addRecordId(saveResult.getId());
                continue;
            }
            for (Database.Error error : saveResult.getErrors()) {
                result.addError(String.valueOf(error.getStatusCode()), error.getMessage(), requestIndexes[j], updates[j].Id);
            }
        }
        Logger.info(CONTEXT, 'requested=' + requests.size() + ' updated=' + result.recordIds.size() + ' errors=' + result.errors.size());
        return result;
    }

    private static Boolean isValid(StatusChangeRequest request) {
        return request != null &&
            request.shipmentId != null &&
            request.shipmentId.getSObjectType() == Shipment__c.SObjectType &&
            String.isNotBlank(request.targetStatus);
    }

    public class StatusChangeRequest {
        @AuraEnabled
        public Id shipmentId { get; set; }
        @AuraEnabled
        public String targetStatus { get; set; }
        @AuraEnabled
        public String reason { get; set; }

        public StatusChangeRequest() {
        }

        public StatusChangeRequest(Id shipmentId, String targetStatus, String reason) {
            this.shipmentId = shipmentId;
            this.targetStatus = targetStatus;
            this.reason = reason;
        }
    }
}
