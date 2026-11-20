/**
 * Fleet eligibility rules (CLAUDE.md section 5, Fleet Rules; Phase 4 decisions Q1 to Q9). Pure: it
 * evaluates candidate assignments against data the caller has loaded and locked, and performs no
 * SOQL or DML, so every rule is unit-tested in isolation. VehicleAssignmentDomain is its only
 * production caller and the single enforcement point for every entry path.
 *
 * Rules, in order (the first failure is reported):
 *   shipment present; window derivable; vehicle and driver present
 *   vehicle not Inactive or Under Maintenance; driver not Inactive or On Leave (Q2)
 *   shipment, vehicle and driver in the same business unit (Q8)
 *   vehicle capacity >= shipment weight (Q6)
 *   vehicle type = quoted vehicle type, when the shipment came from a quotation (Q7)
 *   registration and insurance valid through the window end; fitness too when filled in (Q4)
 *   driver licence valid through the window end (Q4)
 *   no In Progress maintenance; no Scheduled maintenance overlapping the window (Q5)
 *   one open assignment per shipment (Q9)
 *   no overlapping open assignment for the vehicle or the driver, including within the batch (Q1)
 */
public with sharing class VehicleAvailabilityService {
    public static final String SHIPMENT_REQUIRED = 'SHIPMENT_REQUIRED';
    public static final String WINDOW_INVALID = 'WINDOW_INVALID';
    public static final String RECORD_NOT_FOUND = 'RECORD_NOT_FOUND';
    public static final String VEHICLE_INACTIVE = 'VEHICLE_INACTIVE';
    public static final String VEHICLE_UNDER_MAINTENANCE = 'VEHICLE_UNDER_MAINTENANCE';
    public static final String DRIVER_UNAVAILABLE = 'DRIVER_UNAVAILABLE';
    public static final String BUSINESS_UNIT_MISMATCH = 'BUSINESS_UNIT_MISMATCH';
    public static final String CAPACITY_INSUFFICIENT = 'CAPACITY_INSUFFICIENT';
    public static final String VEHICLE_TYPE_MISMATCH = 'VEHICLE_TYPE_MISMATCH';
    public static final String VEHICLE_DOCUMENT_INVALID = 'VEHICLE_DOCUMENT_INVALID';
    public static final String DRIVER_LICENCE_INVALID = 'DRIVER_LICENCE_INVALID';
    public static final String MAINTENANCE_CONFLICT = 'MAINTENANCE_CONFLICT';
    public static final String SHIPMENT_ALREADY_ALLOCATED = 'SHIPMENT_ALREADY_ALLOCATED';
    public static final String VEHICLE_DOUBLE_BOOKED = 'VEHICLE_DOUBLE_BOOKED';
    public static final String DRIVER_DOUBLE_BOOKED = 'DRIVER_DOUBLE_BOOKED';

    @TestVisible
    private static final Set<String> VEHICLE_BLOCKED_STATUSES = new Set<String>{ 'Inactive', 'Under Maintenance' };
    @TestVisible
    private static final Set<String> DRIVER_BLOCKED_STATUSES = new Set<String>{ 'Inactive', 'On Leave' };
    private static final String MAINTENANCE_IN_PROGRESS = 'In Progress';
    private static final String MAINTENANCE_SCHEDULED = 'Scheduled';

    /** Returns violations keyed by Candidate.index; candidates that pass are absent. */
    public Map<Integer, Violation> evaluate(List<Candidate> candidates, Context context) {
        Map<Integer, Violation> violations = new Map<Integer, Violation>();
        Map<Id, List<Vehicle_Maintenance__c>> maintenanceByVehicle = new Map<Id, List<Vehicle_Maintenance__c>>();
        for (Vehicle_Maintenance__c maintenance : context.maintenance) {
            if (!maintenanceByVehicle.containsKey(maintenance.Vehicle__c)) {
                maintenanceByVehicle.put(maintenance.Vehicle__c, new List<Vehicle_Maintenance__c>());
            }
            maintenanceByVehicle.get(maintenance.Vehicle__c).add(maintenance);
        }
        // Candidates accepted so far in this batch: later candidates must not conflict with them (Q1).
        List<Candidate> accepted = new List<Candidate>();
        for (Candidate candidate : candidates) {
            Violation violation = check(candidate, context, maintenanceByVehicle, accepted);
            if (violation == null) {
                accepted.add(candidate);
            } else {
                violations.put(candidate.index, violation);
            }
        }
        return violations;
    }

    private Violation check(Candidate candidate, Context context, Map<Id, List<Vehicle_Maintenance__c>> maintenanceByVehicle, List<Candidate> accepted) {
        Shipment__c shipment = candidate.shipmentId == null ? null : context.shipments.get(candidate.shipmentId);
        if (shipment == null) {
            return new Violation(SHIPMENT_REQUIRED, Label.eLogix_Fleet_Shipment_Required);
        }
        if (candidate.startDate == null || candidate.endDate == null || candidate.endDate < candidate.startDate) {
            return new Violation(WINDOW_INVALID, format(Label.eLogix_Fleet_Window_Invalid, new List<Object>{ shipment.Name }));
        }
        Vehicle__c vehicle = context.vehicles.get(candidate.vehicleId);
        Driver__c driver = context.drivers.get(candidate.driverId);
        if (vehicle == null || driver == null) {
            Id missing = vehicle == null ? candidate.vehicleId : candidate.driverId;
            return new Violation(RECORD_NOT_FOUND, format(Label.eLogix_Fleet_Record_Not_Found, new List<Object>{ missing }));
        }
        String vehicleName = vehicle.Vehicle_Number__c;

        if ('Inactive'.equals(vehicle.Status__c)) {
            return new Violation(VEHICLE_INACTIVE, format(Label.eLogix_Fleet_Vehicle_Inactive, new List<Object>{ vehicleName }));
        }
        if ('Under Maintenance'.equals(vehicle.Status__c)) {
            return new Violation(VEHICLE_UNDER_MAINTENANCE, format(Label.eLogix_Fleet_Vehicle_Under_Maintenance, new List<Object>{ vehicleName }));
        }
        if (DRIVER_BLOCKED_STATUSES.contains(driver.Status__c)) {
            return new Violation(DRIVER_UNAVAILABLE, format(Label.eLogix_Fleet_Driver_Unavailable, new List<Object>{ driver.Name, driver.Status__c }));
        }
        if (vehicle.Business_Unit__c != shipment.Business_Unit__c || driver.Business_Unit__c != shipment.Business_Unit__c) {
            return new Violation(BUSINESS_UNIT_MISMATCH, format(Label.eLogix_Fleet_Business_Unit_Mismatch, new List<Object>{ vehicleName, driver.Name }));
        }
        if (vehicle.Capacity__c == null || shipment.Weight__c == null || vehicle.Capacity__c < shipment.Weight__c) {
            return new Violation(
                CAPACITY_INSUFFICIENT,
                format(Label.eLogix_Fleet_Capacity_Insufficient, new List<Object>{ vehicleName, display(vehicle.Capacity__c), display(shipment.Weight__c) })
            );
        }
        String quotedType = shipment.Quotation__r?.Rate_Card__r?.Vehicle_Type__c;
        if (String.isNotBlank(quotedType) && quotedType != vehicle.Vehicle_Type__c) {
            return new Violation(
                VEHICLE_TYPE_MISMATCH,
                format(Label.eLogix_Fleet_Vehicle_Type_Mismatch, new List<Object>{ quotedType, vehicleName, vehicle.Vehicle_Type__c })
            );
        }

        Violation documents = documentViolation(candidate, vehicle, driver);
        if (documents != null) {
            return documents;
        }
        if (hasMaintenanceConflict(candidate, maintenanceByVehicle.get(vehicle.Id))) {
            return new Violation(MAINTENANCE_CONFLICT, format(Label.eLogix_Fleet_Maintenance_Conflict, new List<Object>{ vehicleName }));
        }
        return bookingViolation(candidate, context, accepted, shipment, vehicleName, driver.Name);
    }

    /** Q4: valid through the end of the window; fitness only when filled in. */
    private Violation documentViolation(Candidate candidate, Vehicle__c vehicle, Driver__c driver) {
        Date mustLast = candidate.endDate;
        List<Schema.SObjectField> required = new List<Schema.SObjectField>{ Vehicle__c.Registration_Expiry__c, Vehicle__c.Insurance_Expiry__c };
        for (Schema.SObjectField field : required) {
            Date expiry = (Date) vehicle.get(field);
            if (expiry == null || expiry < mustLast) {
                return vehicleDocument(vehicle, field, mustLast);
            }
        }
        if (vehicle.Fitness_Expiry__c != null && vehicle.Fitness_Expiry__c < mustLast) {
            return vehicleDocument(vehicle, Vehicle__c.Fitness_Expiry__c, mustLast);
        }
        if (driver.License_Expiry__c == null || driver.License_Expiry__c < mustLast) {
            return new Violation(DRIVER_LICENCE_INVALID, format(Label.eLogix_Fleet_Driver_Licence_Invalid, new List<Object>{ driver.Name, mustLast.format() }));
        }
        return null;
    }

    private static Violation vehicleDocument(Vehicle__c vehicle, Schema.SObjectField field, Date mustLast) {
        return new Violation(
            VEHICLE_DOCUMENT_INVALID,
            format(Label.eLogix_Fleet_Vehicle_Document_Invalid, new List<Object>{ vehicle.Vehicle_Number__c, field.getDescribe().getLabel(), mustLast.format() })
        );
    }

    /**
     * Q5: In Progress maintenance always blocks (an ongoing job has no known end). Scheduled
     * maintenance occupies [Scheduled_Date, Completion_Date or Scheduled_Date] and blocks when that
     * period overlaps the window's days.
     */
    private Boolean hasMaintenanceConflict(Candidate candidate, List<Vehicle_Maintenance__c> maintenance) {
        for (Vehicle_Maintenance__c job : maintenance == null ? new List<Vehicle_Maintenance__c>() : maintenance) {
            if (MAINTENANCE_IN_PROGRESS.equals(job.Status__c)) {
                return true;
            }
            if (MAINTENANCE_SCHEDULED.equals(job.Status__c) && job.Scheduled_Date__c != null) {
                Date jobEnd = job.Completion_Date__c == null ? job.Scheduled_Date__c : job.Completion_Date__c;
                if (AssignmentWindow.overlapsDays(job.Scheduled_Date__c, jobEnd, candidate.startDate, candidate.endDate)) {
                    return true;
                }
            }
        }
        return false;
    }

    /** Q9 one open assignment per shipment; Q1 no overlapping bookings, against stored and in-batch assignments. */
    private Violation bookingViolation(Candidate candidate, Context context, List<Candidate> accepted, Shipment__c shipment, String vehicleName, String driverName) {
        for (Vehicle_Assignment__c existing : context.openAssignments) {
            if (existing.Id != null && existing.Id == candidate.assignmentId) {
                continue;
            }
            if (existing.Shipment__c == candidate.shipmentId) {
                return new Violation(SHIPMENT_ALREADY_ALLOCATED, format(Label.eLogix_Fleet_Shipment_Already_Allocated, new List<Object>{ shipment.Name }));
            }
        }
        for (Candidate other : accepted) {
            if (other.shipmentId == candidate.shipmentId) {
                return new Violation(SHIPMENT_ALREADY_ALLOCATED, format(Label.eLogix_Fleet_Shipment_Already_Allocated, new List<Object>{ shipment.Name }));
            }
        }
        for (Vehicle_Assignment__c existing : context.openAssignments) {
            if (existing.Id != null && existing.Id == candidate.assignmentId) {
                continue;
            }
            // Phase 5 (D3): an Active trip is open-ended until it is Completed.
            Datetime existingEnd = 'Active'.equals(existing.Status__c) ? null : existing.Assignment_End__c;
            if (!AssignmentWindow.overlaps(candidate.startAt, candidate.endAt, existing.Assignment_Start__c, existingEnd)) {
                continue;
            }
            if (existing.Vehicle__c == candidate.vehicleId) {
                return new Violation(VEHICLE_DOUBLE_BOOKED, format(Label.eLogix_Fleet_Vehicle_Double_Booked, new List<Object>{ vehicleName }));
            }
            if (existing.Driver__c == candidate.driverId) {
                return new Violation(DRIVER_DOUBLE_BOOKED, format(Label.eLogix_Fleet_Driver_Double_Booked, new List<Object>{ driverName }));
            }
        }
        for (Candidate other : accepted) {
            if (!AssignmentWindow.overlaps(candidate.startAt, candidate.endAt, other.startAt, other.endAt)) {
                continue;
            }
            if (other.vehicleId == candidate.vehicleId) {
                return new Violation(VEHICLE_DOUBLE_BOOKED, format(Label.eLogix_Fleet_Vehicle_Double_Booked, new List<Object>{ vehicleName }));
            }
            if (other.driverId == candidate.driverId) {
                return new Violation(DRIVER_DOUBLE_BOOKED, format(Label.eLogix_Fleet_Driver_Double_Booked, new List<Object>{ driverName }));
            }
        }
        return null;
    }

    private static String format(String template, List<Object> values) {
        return String.format(template, values);
    }

    private static String display(Decimal value) {
        return value == null ? '-' : value.format();
    }

    /* ---------------- types ---------------- */

    /** One proposed or changed assignment. The window is derived from the shipment by the caller (Q3). */
    public class Candidate {
        public Integer index;
        public Id assignmentId;
        public Id shipmentId;
        public Id vehicleId;
        public Id driverId;
        public Datetime startAt;
        public Datetime endAt;
        public Date startDate;
        public Date endDate;
    }

    /** Data the rules read, loaded (and locked) by the caller. */
    public class Context {
        public Map<Id, Shipment__c> shipments = new Map<Id, Shipment__c>();
        public Map<Id, Vehicle__c> vehicles = new Map<Id, Vehicle__c>();
        public Map<Id, Driver__c> drivers = new Map<Id, Driver__c>();
        public List<Vehicle_Assignment__c> openAssignments = new List<Vehicle_Assignment__c>();
        public List<Vehicle_Maintenance__c> maintenance = new List<Vehicle_Maintenance__c>();
    }

    public class Violation {
        public String code;
        public String message;

        public Violation(String code, String message) {
            this.code = code;
            this.message = message;
        }
    }
}
