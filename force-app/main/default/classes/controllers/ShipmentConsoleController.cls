/**
 * Phase 7 LWC controller for shipment screens (shipmentManagement, shipmentDetails). Thin: reads run
 * in user mode; status changes go through ShipmentService.changeStatus, so the Shipment__c trigger
 * (ShipmentStatusPolicy, guards, validation rules) enforces every save.
 *
 * Status options (decision P5, option A): the real ShipmentStatusPolicy is evaluated for every
 * candidate status. Two guards cannot verify their rule outside the Shipment__c trigger and fail closed
 * there (ShipmentAllocationGuard, ShipmentDeliveryGuard); a status rejected only by their codes is
 * offered and marked as validated on save. Every other rejection hides the status. Out for Delivery,
 * Delivered and Failed Delivery are never offered and never accepted here: DeliveryService owns them.
 */
public with sharing class ShipmentConsoleController {
    private static final String LOG_CONTEXT = 'ShipmentConsoleController';
    public static final String DELIVERY_ACTION_REQUIRED = 'DELIVERY_ACTION_REQUIRED';
    @TestVisible
    private static final Set<String> DELIVERY_OWNED = new Set<String>{ 'Out for Delivery', 'Delivered', 'Failed Delivery' };
    /** Guard codes that mean "verified only on save", never "not allowed". */
    @TestVisible
    private static final Set<String> SAVE_TIME_CODES = new Set<String>{
        ShipmentAllocationGuard.ALLOCATION_REQUIRED,
        ShipmentDeliveryGuard.DELIVERY_REQUIRED
    };
    private static final Integer MAX_ROWS = 200;

    public class StatusOption {
        @AuraEnabled
        public String value;
        @AuraEnabled
        public String label;
        /** True when a guard checks this transition only when the change is saved. */
        @AuraEnabled
        public Boolean validatedOnSave;
        /** The guard message to show next to the option, when validatedOnSave. */
        @AuraEnabled
        public String note;
        /** True when the transition is allowed only through the status override permission. */
        @AuraEnabled
        public Boolean byOverride;

        StatusOption(String value, String label, Boolean validatedOnSave, String note, Boolean byOverride) {
            this.value = value;
            this.label = label;
            this.validatedOnSave = validatedOnSave;
            this.note = note;
            this.byOverride = byOverride;
        }
    }

    /** Shipments the user can see, newest first. Optional status filter and search on number, origin or destination. */
    @AuraEnabled(cacheable=true)
    public static List<Shipment__c> getShipments(String status, String searchTerm, Integer maxRows) {
        try {
            Integer rowLimit = maxRows == null || maxRows < 1 || maxRows > MAX_ROWS ? MAX_ROWS : maxRows;
            Map<String, Object> binds = new Map<String, Object>{ 'rowLimit' => rowLimit };
            List<String> filters = new List<String>();
            if (String.isNotBlank(status) && ShipmentStatusPolicy.validStatuses().contains(status)) {
                filters.add('Status__c = :status');
                binds.put('status', status);
            }
            if (String.isNotBlank(searchTerm)) {
                filters.add('(Name LIKE :pattern OR Origin__c LIKE :pattern OR Destination__c LIKE :pattern)');
                binds.put('pattern', '%' + searchTerm.trim() + '%');
            }
            String query =
                'SELECT Id, Name, Customer__r.Name, Origin__c, Destination__c, Status__c, Priority__c, Weight__c, Pickup_Date__c,' +
                ' Expected_Delivery_Date__c, Latest_Location__c, Latest_Tracking_Timestamp__c, Vehicle__r.Vehicle_Number__c, Driver__r.Name' +
                ' FROM Shipment__c' +
                (filters.isEmpty() ? '' : ' WHERE ' + String.join(filters, ' AND ')) +
                ' ORDER BY LastModifiedDate DESC LIMIT :rowLimit';
            // Only bind variables carry user input; the query text is fixed.
            return (List<Shipment__c>) Database.queryWithBinds(query, binds, AccessLevel.USER_MODE);
        } catch (Exception e) {
            throw toAura(e);
        }
    }

    /** The statuses the user may try to move this shipment to, in picklist order (decision P5). */
    @AuraEnabled
    public static List<StatusOption> getStatusOptions(Id shipmentId) {
        try {
            List<Shipment__c> rows = [
                SELECT Id, Status__c, Item_Count__c, Vehicle__c, Driver__c
                FROM Shipment__c
                WHERE Id = :shipmentId
                WITH USER_MODE
            ];
            if (rows.isEmpty()) {
                throw new ValidationException(String.format(Label.eLogix_Tracking_Shipment_Not_Found, new List<Object>{ shipmentId }));
            }
            Shipment__c shipment = rows[0];

            List<Schema.PicklistEntry> entries = new List<Schema.PicklistEntry>();
            List<ShipmentStatusPolicy.StatusChange> changes = new List<ShipmentStatusPolicy.StatusChange>();
            Set<String> valid = ShipmentStatusPolicy.validStatuses();
            for (Schema.PicklistEntry entry : Shipment__c.Status__c.getDescribe().getPicklistValues()) {
                String value = entry.getValue();
                if (entry.isActive() && valid.contains(value) && !DELIVERY_OWNED.contains(value) && !value.equals(shipment.Status__c)) {
                    changes.add(new ShipmentStatusPolicy.StatusChange(changes.size(), shipment, shipment.Status__c, value));
                    entries.add(entry);
                }
            }

            List<StatusOption> options = new List<StatusOption>();
            List<ShipmentStatusPolicy.Decision> decisions = new ShipmentStatusPolicy().evaluate(changes);
            for (ShipmentStatusPolicy.Decision decision : decisions) {
                Schema.PicklistEntry entry = entries[decision.index];
                Boolean byOverride = decision.outcome == ShipmentStatusPolicy.Outcome.ALLOWED_BY_OVERRIDE;
                if (decision.isAllowed()) {
                    options.add(new StatusOption(entry.getValue(), entry.getLabel(), false, null, byOverride));
                } else if (decision.isRejected() && SAVE_TIME_CODES.contains(decision.reasonCode)) {
                    options.add(new StatusOption(entry.getValue(), entry.getLabel(), true, decision.message, byOverride));
                }
            }
            return options;
        } catch (Exception e) {
            throw toAura(e);
        }
    }

    /** One status change through ShipmentService; reason fills the hold or cancellation reason. */
    @AuraEnabled
    public static ServiceResult changeStatus(Id shipmentId, String targetStatus, String reason) {
        try {
            if (targetStatus != null && DELIVERY_OWNED.contains(targetStatus.trim())) {
                return new ServiceResult()
                    .addError(
                        DELIVERY_ACTION_REQUIRED,
                        String.format(Label.eLogix_Status_Use_Delivery_Actions, new List<Object>{ targetStatus.trim() }),
                        0,
                        shipmentId
                    );
            }
            return new ShipmentService()
                .changeStatus(new List<ShipmentService.StatusChangeRequest>{ new ShipmentService.StatusChangeRequest(shipmentId, targetStatus, reason) });
        } catch (Exception e) {
            throw toAura(e);
        }
    }

    private static AuraHandledException toAura(Exception e) {
        String message = ExceptionHandler.toUserMessage(e, LOG_CONTEXT);
        AuraHandledException error = new AuraHandledException(message);
        error.setMessage(message);
        return error;
    }
}
