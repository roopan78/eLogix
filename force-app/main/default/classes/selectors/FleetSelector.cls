/**
 * SOQL for fleet allocation: vehicles, drivers, assignments, maintenance, tracking history and the
 * shipment data the fleet rules need.
 *
 * Enforcement reads (locks, conflicts, maintenance, shipment facts, dispatch history) run in system
 * mode and without sharing, in the private EnforcementReader: a booking conflict or a quoted vehicle
 * type must never be hidden by the caller's field access or record visibility. They return only what
 * the rules need. Every public method that reaches the reader first checks that it runs inside the
 * trigger context it was built for (object and operation); any other caller gets an
 * AuthorizationException (FLEET_ENFORCEMENT_TRIGGER_ONLY), so no controller, REST resource, invocable
 * action or Flow can use the reader to read data that ignores sharing.
 *
 * User-facing reads used for access checks run in user mode with the caller's sharing (inherited).
 *
 * Virtual so that a test can substitute a selector whose lock query times out (decision Q16) without
 * any switch in production code. A subclass cannot reach the reader except through these methods.
 */
public inherited sharing virtual class FleetSelector {
    public static final Set<String> OPEN_STATUSES = new Set<String>{ 'Planned', 'Active' };
    public static final String ENFORCEMENT_TRIGGER_ONLY = 'FLEET_ENFORCEMENT_TRIGGER_ONLY';

    /* ---------------- permitted trigger contexts ---------------- */

    /** Allocation rules: the assignment before-save trigger, and the Ready for Dispatch guard. */
    @TestVisible
    private static final Set<String> RULE_CONTEXTS = new Set<String>{
        'Vehicle_Assignment__c.BEFORE_INSERT',
        'Vehicle_Assignment__c.BEFORE_UPDATE',
        'Shipment__c.BEFORE_UPDATE'
    };
    /** Q9 dispatch history: only changes to existing assignments can be locked by it. */
    private static final Set<String> HISTORY_CONTEXTS = new Set<String>{ 'Vehicle_Assignment__c.BEFORE_UPDATE' };
    /** Ready for Dispatch / In Transit guard, the cancellation clear-down and the shipment deletion check. */
    private static final Set<String> SHIPMENT_BEFORE_UPDATE_OR_DELETE = new Set<String>{ 'Shipment__c.BEFORE_UPDATE', 'Shipment__c.BEFORE_DELETE' };
    /** Cancellation release. */
    private static final Set<String> SHIPMENT_AFTER_UPDATE = new Set<String>{ 'Shipment__c.AFTER_UPDATE' };
    /** Shipment mirror. */
    private static final Set<String> ASSIGNMENT_AFTER_SAVE = new Set<String>{
        'Vehicle_Assignment__c.AFTER_INSERT',
        'Vehicle_Assignment__c.AFTER_UPDATE'
    };

    private static final EnforcementReader ENFORCEMENT = new EnforcementReader();

    /** "Object.OPERATION" of the trigger that is executing now, or null outside a trigger. */
    @TestVisible
    private static String currentTriggerContext() {
        return TriggerContext.current();
    }

    private static void requireContext(Set<String> permitted) {
        TriggerContext.require(permitted, ENFORCEMENT_TRIGGER_ONLY);
    }

    /* ---------------- enforcement reads (trigger context only, without sharing) ---------------- */

    /** Vehicles locked for the rest of the transaction. Locks are taken vehicles first, then drivers. */
    public virtual Map<Id, Vehicle__c> lockVehicles(Set<Id> vehicleIds) {
        requireContext(RULE_CONTEXTS);
        return ENFORCEMENT.lockVehicles(vehicleIds);
    }

    public virtual Map<Id, Driver__c> lockDrivers(Set<Id> driverIds) {
        requireContext(RULE_CONTEXTS);
        return ENFORCEMENT.lockDrivers(driverIds);
    }

    /** Shipment facts the fleet rules use, including the vehicle type the customer was quoted for (Q7). */
    public Map<Id, Shipment__c> shipmentsForAssignments(Set<Id> shipmentIds) {
        requireContext(RULE_CONTEXTS);
        return ENFORCEMENT.shipmentsForAssignments(shipmentIds);
    }

    /**
     * Open (Planned or Active) assignments that could conflict: any on the same shipments, plus those
     * of the same vehicles or drivers whose window overlaps [fromAt, toAt]. Excludes the assignments
     * being evaluated themselves.
     */
    public List<Vehicle_Assignment__c> openAssignmentsInWindow(
        Set<Id> shipmentIds,
        Set<Id> vehicleIds,
        Set<Id> driverIds,
        Datetime fromAt,
        Datetime toAt,
        Set<Id> excludeIds
    ) {
        requireContext(RULE_CONTEXTS);
        return ENFORCEMENT.openAssignmentsInWindow(shipmentIds, vehicleIds, driverIds, fromAt, toAt, excludeIds);
    }

    /** Scheduled or in-progress maintenance of the given vehicles (decision Q5). */
    public List<Vehicle_Maintenance__c> openMaintenance(Set<Id> vehicleIds) {
        requireContext(RULE_CONTEXTS);
        return ENFORCEMENT.openMaintenance(vehicleIds);
    }

    /**
     * Shipments whose status history (Tracking_Event__c.To_Status__c) contains a status outside the
     * given pre-dispatch statuses, that is, shipments that have reached Ready for Dispatch or a later
     * operational status at least once (Q9). Tracking events are immutable and written only by
     * TrackingService, so the current status (for example On Hold) cannot reset this.
     */
    public Set<Id> shipmentsWithHistoryBeyond(Set<Id> shipmentIds, Set<String> preDispatchStatuses) {
        requireContext(HISTORY_CONTEXTS);
        return ENFORCEMENT.shipmentsWithHistoryBeyond(shipmentIds, preDispatchStatuses);
    }

    /** Open assignments of the given shipments, with their windows (dispatch guard, cancellation, deletion check). */
    public List<Vehicle_Assignment__c> openAssignmentsOfShipments(Set<Id> shipmentIds) {
        requireContext(SHIPMENT_BEFORE_UPDATE_OR_DELETE);
        return ENFORCEMENT.openAssignmentsOfShipments(shipmentIds);
    }

    /**
     * Planned and Active assignments of the given shipments, locked (Phase 5 automatic lifecycle:
     * activation at dispatch, completion when the trip ends). Shipment after update only.
     */
    public virtual List<Vehicle_Assignment__c> lockOpenAssignmentsOfShipments(Set<Id> shipmentIds) {
        requireContext(SHIPMENT_AFTER_UPDATE);
        return ENFORCEMENT.lockOpenAssignmentsOfShipments(shipmentIds);
    }

    /** Planned assignments of the given shipments, locked (automatic release on cancellation, Q11). */
    public virtual List<Vehicle_Assignment__c> lockPlannedAssignmentsOfShipments(Set<Id> shipmentIds) {
        requireContext(SHIPMENT_AFTER_UPDATE);
        return ENFORCEMENT.lockPlannedAssignmentsOfShipments(shipmentIds);
    }

    /** Shipments locked for the vehicle and driver mirror (Q18). */
    public virtual Map<Id, Shipment__c> lockShipmentsForMirror(Set<Id> shipmentIds) {
        requireContext(ASSIGNMENT_AFTER_SAVE);
        return ENFORCEMENT.lockShipmentsForMirror(shipmentIds);
    }

    /* ---------------- user-mode reads (access checks) ---------------- */

    /**
     * Vehicle numbers and driver names for the correction history, read with the caller's access
     * (user mode); an unreadable record is simply absent and is shown by its Id.
     */
    public Map<Id, String> vehicleAndDriverNames(Set<Id> vehicleIds, Set<Id> driverIds) {
        Map<Id, String> names = new Map<Id, String>();
        Set<Id> vehicles = vehicleIds == null ? new Set<Id>() : vehicleIds;
        Set<Id> drivers = driverIds == null ? new Set<Id>() : driverIds;
        if (!vehicles.isEmpty()) {
            for (Vehicle__c vehicle : [SELECT Id, Vehicle_Number__c FROM Vehicle__c WHERE Id IN :vehicles WITH USER_MODE]) {
                names.put(vehicle.Id, vehicle.Vehicle_Number__c);
            }
        }
        if (!drivers.isEmpty()) {
            for (Driver__c driver : [SELECT Id, Name FROM Driver__c WHERE Id IN :drivers WITH USER_MODE]) {
                names.put(driver.Id, driver.Name);
            }
        }
        return names;
    }

    /**
     * Shipments the running user can read, locked: shipments are locked before vehicles and drivers.
     * The dates let reallocation refresh the assignment window (Q3).
     */
    public virtual Map<Id, Shipment__c> shipmentsForAllocation(Set<Id> shipmentIds) {
        if (shipmentIds == null || shipmentIds.isEmpty()) {
            return new Map<Id, Shipment__c>();
        }
        return new Map<Id, Shipment__c>(
            [
                SELECT Id, Name, Status__c, Pickup_Date__c, Expected_Delivery_Date__c
                FROM Shipment__c
                WHERE Id IN :shipmentIds
                WITH USER_MODE
                FOR UPDATE
            ]
        );
    }

    public Set<Id> readableVehicleIds(Set<Id> vehicleIds) {
        if (vehicleIds == null || vehicleIds.isEmpty()) {
            return new Set<Id>();
        }
        return new Map<Id, Vehicle__c>([SELECT Id FROM Vehicle__c WHERE Id IN :vehicleIds WITH USER_MODE]).keySet();
    }

    public Set<Id> readableDriverIds(Set<Id> driverIds) {
        if (driverIds == null || driverIds.isEmpty()) {
            return new Set<Id>();
        }
        return new Map<Id, Driver__c>([SELECT Id FROM Driver__c WHERE Id IN :driverIds WITH USER_MODE]).keySet();
    }

    /** Assignments the running user can read, locked for a status change. */
    public virtual Map<Id, Vehicle_Assignment__c> assignmentsForUpdate(Set<Id> assignmentIds) {
        if (assignmentIds == null || assignmentIds.isEmpty()) {
            return new Map<Id, Vehicle_Assignment__c>();
        }
        return new Map<Id, Vehicle_Assignment__c>(
            [
                SELECT Id, Name, Status__c, Shipment__c, Vehicle__c, Driver__c, Assignment_Start__c, Assignment_End__c
                FROM Vehicle_Assignment__c
                WHERE Id IN :assignmentIds
                WITH USER_MODE
                FOR UPDATE
            ]
        );
    }

    /** The Planned assignment of each shipment the running user can read (reallocation). */
    public virtual Map<Id, Vehicle_Assignment__c> plannedAssignmentByShipment(Set<Id> shipmentIds) {
        Map<Id, Vehicle_Assignment__c> byShipment = new Map<Id, Vehicle_Assignment__c>();
        if (shipmentIds == null || shipmentIds.isEmpty()) {
            return byShipment;
        }
        for (Vehicle_Assignment__c assignment : [
            SELECT Id, Shipment__c, Vehicle__c, Driver__c, Status__c, Correction_Reason__c
            FROM Vehicle_Assignment__c
            WHERE Shipment__c IN :shipmentIds AND Status__c = 'Planned'
            WITH USER_MODE
            FOR UPDATE
        ]) {
            byShipment.put(assignment.Shipment__c, assignment);
        }
        return byShipment;
    }

    /**
     * The enforcement queries, without sharing. Integrity checks must see every conflicting
     * assignment, maintenance record, vehicle, driver, quotation and status event, whoever owns them
     * and whatever the caller can see: WITH SYSTEM_MODE alone skips CRUD and FLS but still applies the
     * sharing of the calling class, so a Fleet Manager would otherwise not see a quotation it cannot
     * read and the quoted vehicle type rule (Q7) would be skipped silently. Reachable only through the
     * trigger-context-checked methods above. Results go only to the fleet rules, never back to the
     * caller as records; violation messages name only the shipment, vehicle and driver involved.
     */
    private without sharing class EnforcementReader {
        public Map<Id, Vehicle__c> lockVehicles(Set<Id> vehicleIds) {
            if (vehicleIds == null || vehicleIds.isEmpty()) {
                return new Map<Id, Vehicle__c>();
            }
            return new Map<Id, Vehicle__c>(
                [
                    SELECT Id, Vehicle_Number__c, Vehicle_Type__c, Capacity__c, Status__c, Business_Unit__c,
                        Registration_Expiry__c, Insurance_Expiry__c, Fitness_Expiry__c
                    FROM Vehicle__c
                    WHERE Id IN :vehicleIds
                    WITH SYSTEM_MODE
                    FOR UPDATE
                ]
            );
        }

        public Map<Id, Driver__c> lockDrivers(Set<Id> driverIds) {
            if (driverIds == null || driverIds.isEmpty()) {
                return new Map<Id, Driver__c>();
            }
            return new Map<Id, Driver__c>(
                [
                    SELECT Id, Name, Status__c, Business_Unit__c, License_Expiry__c
                    FROM Driver__c
                    WHERE Id IN :driverIds
                    WITH SYSTEM_MODE
                    FOR UPDATE
                ]
            );
        }

        public Map<Id, Shipment__c> shipmentsForAssignments(Set<Id> shipmentIds) {
            if (shipmentIds == null || shipmentIds.isEmpty()) {
                return new Map<Id, Shipment__c>();
            }
            return new Map<Id, Shipment__c>(
                [
                    SELECT Id, Name, Status__c, Business_Unit__c, Weight__c, Pickup_Date__c, Expected_Delivery_Date__c,
                        Quotation__c, Quotation__r.Rate_Card__r.Vehicle_Type__c
                    FROM Shipment__c
                    WHERE Id IN :shipmentIds
                    WITH SYSTEM_MODE
                ]
            );
        }

        public List<Vehicle_Assignment__c> openAssignmentsInWindow(
            Set<Id> shipmentIds,
            Set<Id> vehicleIds,
            Set<Id> driverIds,
            Datetime fromAt,
            Datetime toAt,
            Set<Id> excludeIds
        ) {
            Set<String> openStatuses = OPEN_STATUSES;
            Set<Id> excluded = excludeIds == null ? new Set<Id>() : excludeIds;
            // Phase 5 (D3): an Active trip holds its vehicle and driver until it is Completed, so its
            // planned end does not release them.
            return [
                SELECT Id, Shipment__c, Vehicle__c, Driver__c, Assignment_Start__c, Assignment_End__c, Status__c
                FROM Vehicle_Assignment__c
                WHERE
                    Status__c IN :openStatuses
                    AND Id NOT IN :excluded
                    AND (Shipment__c IN :shipmentIds
                    OR ((Vehicle__c IN :vehicleIds
                    OR Driver__c IN :driverIds)
                    AND Assignment_Start__c < :toAt
                    AND (Assignment_End__c = NULL
                    OR Assignment_End__c > :fromAt
                    OR Status__c = 'Active')))
                WITH SYSTEM_MODE
            ];
        }

        public List<Vehicle_Maintenance__c> openMaintenance(Set<Id> vehicleIds) {
            if (vehicleIds == null || vehicleIds.isEmpty()) {
                return new List<Vehicle_Maintenance__c>();
            }
            return [
                SELECT Id, Vehicle__c, Status__c, Scheduled_Date__c, Completion_Date__c
                FROM Vehicle_Maintenance__c
                WHERE Vehicle__c IN :vehicleIds AND Status__c IN ('Scheduled', 'In Progress')
                WITH SYSTEM_MODE
            ];
        }

        public Set<Id> shipmentsWithHistoryBeyond(Set<Id> shipmentIds, Set<String> preDispatchStatuses) {
            Set<Id> result = new Set<Id>();
            if (shipmentIds == null || shipmentIds.isEmpty()) {
                return result;
            }
            Set<String> excluded = preDispatchStatuses == null ? new Set<String>() : preDispatchStatuses;
            for (AggregateResult row : [
                SELECT Shipment__c
                FROM Tracking_Event__c
                WHERE Shipment__c IN :shipmentIds AND To_Status__c != NULL AND To_Status__c NOT IN :excluded
                WITH SYSTEM_MODE
                GROUP BY Shipment__c
            ]) {
                result.add((Id) row.get('Shipment__c'));
            }
            return result;
        }

        public List<Vehicle_Assignment__c> openAssignmentsOfShipments(Set<Id> shipmentIds) {
            if (shipmentIds == null || shipmentIds.isEmpty()) {
                return new List<Vehicle_Assignment__c>();
            }
            Set<String> openStatuses = OPEN_STATUSES;
            return [
                SELECT Id, Shipment__c, Vehicle__c, Driver__c, Status__c, Assignment_Start__c, Assignment_End__c
                FROM Vehicle_Assignment__c
                WHERE Shipment__c IN :shipmentIds AND Status__c IN :openStatuses
                WITH SYSTEM_MODE
            ];
        }

        public List<Vehicle_Assignment__c> lockOpenAssignmentsOfShipments(Set<Id> shipmentIds) {
            if (shipmentIds == null || shipmentIds.isEmpty()) {
                return new List<Vehicle_Assignment__c>();
            }
            Set<String> openStatuses = OPEN_STATUSES;
            return [
                SELECT Id, Shipment__c, Status__c, Assignment_Start__c
                FROM Vehicle_Assignment__c
                WHERE Shipment__c IN :shipmentIds AND Status__c IN :openStatuses
                WITH SYSTEM_MODE
                FOR UPDATE
            ];
        }

        public List<Vehicle_Assignment__c> lockPlannedAssignmentsOfShipments(Set<Id> shipmentIds) {
            if (shipmentIds == null || shipmentIds.isEmpty()) {
                return new List<Vehicle_Assignment__c>();
            }
            return [
                SELECT Id, Shipment__c, Status__c
                FROM Vehicle_Assignment__c
                WHERE Shipment__c IN :shipmentIds AND Status__c = 'Planned'
                WITH SYSTEM_MODE
                FOR UPDATE
            ];
        }

        public Map<Id, Shipment__c> lockShipmentsForMirror(Set<Id> shipmentIds) {
            if (shipmentIds == null || shipmentIds.isEmpty()) {
                return new Map<Id, Shipment__c>();
            }
            return new Map<Id, Shipment__c>(
                [SELECT Id, Name, Vehicle__c, Driver__c FROM Shipment__c WHERE Id IN :shipmentIds WITH SYSTEM_MODE FOR UPDATE]
            );
        }
    }
}
