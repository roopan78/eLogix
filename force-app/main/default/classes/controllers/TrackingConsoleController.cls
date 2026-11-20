/**
 * Phase 7 LWC controller for shipmentTimeline and trackingConsole. Thin: reads run in user mode;
 * manual events go through TrackingService.recordEvents, the single tracking write path. The source is
 * always Manual here, so a user cannot record an event as the GPS integration or another system.
 */
public with sharing class TrackingConsoleController {
    private static final String LOG_CONTEXT = 'TrackingConsoleController';
    private static final Integer MAX_ROWS = 200;
    /** Shipments on the road: the tracking console's working set. */
    @TestVisible
    private static final List<String> ON_THE_ROAD = new List<String>{ 'Dispatched', 'In Transit', 'Out for Delivery', 'Delayed', 'Failed Delivery' };

    /** The shipment's tracking history, newest first. */
    @AuraEnabled(cacheable=true)
    public static List<Tracking_Event__c> getTimeline(Id shipmentId) {
        try {
            return [
                SELECT Id, Event_Type__c, Event_Timestamp__c, Location__c, From_Status__c, To_Status__c, Source__c, Remarks__c, Latitude__c, Longitude__c
                FROM Tracking_Event__c
                WHERE Shipment__c = :shipmentId
                WITH USER_MODE
                ORDER BY Event_Timestamp__c DESC, CreatedDate DESC
                LIMIT :MAX_ROWS
            ];
        } catch (Exception e) {
            throw toAura(e);
        }
    }

    /** Shipments on the road that the user can see, with their latest known location. */
    @AuraEnabled(cacheable=true)
    public static List<Shipment__c> getActiveShipments() {
        try {
            return [
                SELECT
                    Id,
                    Name,
                    Status__c,
                    Origin__c,
                    Destination__c,
                    Latest_Location__c,
                    Latest_Tracking_Timestamp__c,
                    Expected_Delivery_Date__c,
                    Vehicle__r.Vehicle_Number__c,
                    Driver__r.Name
                FROM Shipment__c
                WHERE Status__c IN :ON_THE_ROAD
                WITH USER_MODE
                ORDER BY Latest_Tracking_Timestamp__c DESC NULLS LAST
                LIMIT :MAX_ROWS
            ];
        } catch (Exception e) {
            throw toAura(e);
        }
    }

    /** Records one operational (non-status) event entered by the user. */
    @AuraEnabled
    public static ServiceResult recordEvent(TrackingEventRequest request) {
        try {
            if (request != null) {
                request.source = TrackingService.SOURCE_MANUAL;
                request.externalEventId = null;
            }
            return new TrackingService().recordEvents(new List<TrackingEventRequest>{ request });
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
