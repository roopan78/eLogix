/**
 * Phase 7 LWC controller for vehicleAllocation and fleetManagement. Thin: candidate lists are a
 * convenience filter only (same business unit, allocatable, enough capacity); every allocation rule
 * (capacity, documents, licence, maintenance, overlaps, locking) is enforced by FleetAllocationService
 * and the Vehicle_Assignment__c trigger when the user saves.
 */
public with sharing class FleetConsoleController {
    private static final String LOG_CONTEXT = 'FleetConsoleController';
    private static final Integer MAX_ROWS = 200;

    public class AllocationContext {
        @AuraEnabled
        public Shipment__c shipment;
        /** The shipment's open (Planned or Active) assignment, if any. */
        @AuraEnabled
        public Vehicle_Assignment__c openAssignment;
        @AuraEnabled
        public List<Vehicle__c> vehicles = new List<Vehicle__c>();
        @AuraEnabled
        public List<Driver__c> drivers = new List<Driver__c>();
        /** True when the user holds eLogix_Allocate_Fleet; the UI hides actions otherwise. */
        @AuraEnabled
        public Boolean canAllocate;
        /** True when the user also holds eLogix_Correct_Dispatched_Allocation. */
        @AuraEnabled
        public Boolean canCorrect;
    }

    public class FleetOverview {
        @AuraEnabled
        public List<Vehicle__c> vehicles;
        @AuraEnabled
        public List<Driver__c> drivers;
    }

    /** The shipment, its open assignment and suggested vehicles and drivers (allocation is validated on save). */
    @AuraEnabled
    public static AllocationContext getAllocationContext(Id shipmentId) {
        try {
            List<Shipment__c> rows = [
                SELECT Id, Name, Status__c, Business_Unit__c, Weight__c, Pickup_Date__c, Expected_Delivery_Date__c, Vehicle__c, Driver__c
                FROM Shipment__c
                WHERE Id = :shipmentId
                WITH USER_MODE
            ];
            if (rows.isEmpty()) {
                throw new ValidationException(String.format(Label.eLogix_Tracking_Shipment_Not_Found, new List<Object>{ shipmentId }));
            }
            AllocationContext result = new AllocationContext();
            result.shipment = rows[0];
            result.canAllocate = PermissionService.hasPermission(VehicleAssignmentDomain.ALLOCATE_PERMISSION);
            result.canCorrect = result.canAllocate && PermissionService.hasPermission(VehicleAssignmentDomain.CORRECT_PERMISSION);
            for (Vehicle_Assignment__c assignment : [
                SELECT Id, Name, Status__c, Vehicle__c, Vehicle__r.Vehicle_Number__c, Driver__c, Driver__r.Name, Assignment_Start__c, Assignment_End__c, Correction_Reason__c
                FROM Vehicle_Assignment__c
                WHERE Shipment__c = :shipmentId AND Status__c IN ('Planned', 'Active')
                WITH USER_MODE
                ORDER BY CreatedDate DESC
                LIMIT 1
            ]) {
                result.openAssignment = assignment;
            }
            Id businessUnitId = result.shipment.Business_Unit__c;
            Decimal weight = result.shipment.Weight__c == null ? 0 : result.shipment.Weight__c;
            result.vehicles = [
                SELECT Id, Name, Vehicle_Number__c, Vehicle_Type__c, Capacity__c, Status__c
                FROM Vehicle__c
                WHERE Business_Unit__c = :businessUnitId AND Is_Allocatable__c = TRUE AND Capacity__c >= :weight
                WITH USER_MODE
                ORDER BY Capacity__c, Vehicle_Number__c
                LIMIT :MAX_ROWS
            ];
            result.drivers = [
                SELECT Id, Name, License_Number__c, License_Expiry__c, Status__c
                FROM Driver__c
                WHERE Business_Unit__c = :businessUnitId AND Is_Allocatable__c = TRUE
                WITH USER_MODE
                ORDER BY Name
                LIMIT :MAX_ROWS
            ];
            return result;
        } catch (Exception e) {
            throw toAura(e);
        }
    }

    /** Vehicles and drivers the user can see, for the fleet board. */
    @AuraEnabled(cacheable=true)
    public static FleetOverview getFleetOverview() {
        try {
            FleetOverview overview = new FleetOverview();
            overview.vehicles = [
                SELECT
                    Id,
                    Name,
                    Vehicle_Number__c,
                    Vehicle_Type__c,
                    Capacity__c,
                    Status__c,
                    Registration_Expiry__c,
                    Insurance_Expiry__c,
                    Is_Allocatable__c,
                    Business_Unit__r.Name
                FROM Vehicle__c
                WITH USER_MODE
                ORDER BY Vehicle_Number__c
                LIMIT :MAX_ROWS
            ];
            overview.drivers = [
                SELECT Id, Name, License_Number__c, License_Expiry__c, Status__c, Phone__c, Is_Allocatable__c, Business_Unit__r.Name
                FROM Driver__c
                WITH USER_MODE
                ORDER BY Name
                LIMIT :MAX_ROWS
            ];
            return overview;
        } catch (Exception e) {
            throw toAura(e);
        }
    }

    @AuraEnabled
    public static ServiceResult allocate(AllocationRequest request) {
        try {
            return new FleetAllocationService().allocate(new List<AllocationRequest>{ request });
        } catch (Exception e) {
            throw toAura(e);
        }
    }

    @AuraEnabled
    public static ServiceResult reallocate(AllocationRequest request) {
        try {
            return new FleetAllocationService().reallocate(new List<AllocationRequest>{ request });
        } catch (Exception e) {
            throw toAura(e);
        }
    }

    @AuraEnabled
    public static ServiceResult correctDispatchedAllocation(AllocationRequest request) {
        try {
            return new FleetAllocationService().correctDispatchedAllocation(new List<AllocationRequest>{ request });
        } catch (Exception e) {
            throw toAura(e);
        }
    }

    @AuraEnabled
    public static ServiceResult release(Id assignmentId) {
        try {
            return new FleetAllocationService().release(new List<Id>{ assignmentId });
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
