import { LightningElement, api, wire } from "lwc";
import {
  getRecord,
  getFieldValue,
  notifyRecordUpdateAvailable
} from "lightning/uiRecordApi";
import STATUS_FIELD from "@salesforce/schema/Shipment__c.Status__c";
import getAllocationContext from "@salesforce/apex/FleetConsoleController.getAllocationContext";
import allocate from "@salesforce/apex/FleetConsoleController.allocate";
import reallocate from "@salesforce/apex/FleetConsoleController.reallocate";
import correctDispatchedAllocation from "@salesforce/apex/FleetConsoleController.correctDispatchedAllocation";
import release from "@salesforce/apex/FleetConsoleController.release";
import ConfirmationDialog from "c/confirmationDialog";
import {
  handleServiceResult,
  showError,
  errorMessage,
  formatLabel
} from "c/elogixUtils";
import LABEL_TITLE from "@salesforce/label/c.eLogix_UI_Allocation";
import LABEL_NOT_ALLOCATED from "@salesforce/label/c.eLogix_UI_Not_Allocated";
import LABEL_VEHICLE from "@salesforce/label/c.eLogix_UI_Vehicle";
import LABEL_DRIVER from "@salesforce/label/c.eLogix_UI_Driver";
import LABEL_REMARKS from "@salesforce/label/c.eLogix_UI_Remarks";
import LABEL_ALLOCATE from "@salesforce/label/c.eLogix_UI_Allocate";
import LABEL_ALLOCATED from "@salesforce/label/c.eLogix_UI_Allocated";
import LABEL_REALLOCATE from "@salesforce/label/c.eLogix_UI_Reallocate";
import LABEL_REALLOCATED from "@salesforce/label/c.eLogix_UI_Reallocated";
import LABEL_RELEASE from "@salesforce/label/c.eLogix_UI_Release";
import LABEL_RELEASED from "@salesforce/label/c.eLogix_UI_Released";
import LABEL_CONFIRM_RELEASE from "@salesforce/label/c.eLogix_UI_Confirm_Release";
import LABEL_CORRECT from "@salesforce/label/c.eLogix_UI_Correct_Allocation";
import LABEL_CORRECTED from "@salesforce/label/c.eLogix_UI_Corrected";
import LABEL_CORRECTION_REASON from "@salesforce/label/c.eLogix_UI_Correction_Reason";
import LABEL_NO_PERMISSION from "@salesforce/label/c.eLogix_UI_No_Allocation_Permission";
import LABEL_NO_CANDIDATES from "@salesforce/label/c.eLogix_UI_No_Candidates";
import LABEL_CHECKED_ON_SAVE from "@salesforce/label/c.eLogix_UI_Allocation_Checked_On_Save";

const PLANNED = "Planned";
const ON_HOLD = "On Hold";

/**
 * Shipment record page panel for fleet allocation. Shows the open assignment and, for users with
 * eLogix_Allocate_Fleet (reported by the controller), allocate, reallocate, release and, with
 * eLogix_Correct_Dispatched_Allocation on an On Hold shipment, the controlled correction. The
 * suggested vehicles and drivers are a convenience; FleetAllocationService and the assignment trigger
 * check every rule (capacity, documents, licence, maintenance, overlaps, locking) on save.
 */
export default class VehicleAllocation extends LightningElement {
  @api recordId;

  labels = {
    title: LABEL_TITLE,
    notAllocated: LABEL_NOT_ALLOCATED,
    vehicle: LABEL_VEHICLE,
    driver: LABEL_DRIVER,
    remarks: LABEL_REMARKS,
    noPermission: LABEL_NO_PERMISSION,
    noCandidates: LABEL_NO_CANDIDATES,
    checkedOnSave: LABEL_CHECKED_ON_SAVE
  };

  context;
  loadError;
  isLoading = true;
  isWorking = false;
  vehicleId;
  driverId;
  remarks = "";
  _status;

  /** Reload whenever the shipment's status changes (allocation actions depend on it). */
  @wire(getRecord, { recordId: "$recordId", fields: [STATUS_FIELD] })
  wiredShipment({ data, error }) {
    if (data) {
      const status = getFieldValue(data, STATUS_FIELD);
      if (status !== this._status) {
        this._status = status;
        this.load();
      }
    } else if (error) {
      this.loadError = errorMessage(error);
      this.isLoading = false;
    }
  }

  async load() {
    this.isLoading = true;
    this.loadError = undefined;
    try {
      this.context = await getAllocationContext({ shipmentId: this.recordId });
      this.vehicleId = undefined;
      this.driverId = undefined;
      this.remarks = "";
    } catch (error) {
      this.context = undefined;
      this.loadError = errorMessage(error);
    } finally {
      this.isLoading = false;
    }
  }

  get assignment() {
    return this.context && this.context.openAssignment;
  }

  get hasAssignment() {
    return !!this.assignment;
  }

  get assignmentVehicle() {
    const a = this.assignment;
    return a && a.Vehicle__r ? a.Vehicle__r.Vehicle_Number__c : null;
  }

  get assignmentDriver() {
    const a = this.assignment;
    return a && a.Driver__r ? a.Driver__r.Name : null;
  }

  get canAllocate() {
    return !!(this.context && this.context.canAllocate);
  }

  get vehicleOptions() {
    return ((this.context && this.context.vehicles) || []).map((v) => ({
      label: `${v.Vehicle_Number__c} · ${v.Vehicle_Type__c || ""} · ${v.Capacity__c ?? ""} kg`,
      value: v.Id
    }));
  }

  get driverOptions() {
    return ((this.context && this.context.drivers) || []).map((d) => ({
      label: d.License_Number__c
        ? `${d.Name} · ${d.License_Number__c}`
        : d.Name,
      value: d.Id
    }));
  }

  get showNoPermission() {
    return !!this.context && !this.canAllocate;
  }

  get hasCandidates() {
    return this.vehicleOptions.length > 0 && this.driverOptions.length > 0;
  }

  get isPlanned() {
    return this.hasAssignment && this.assignment.Status__c === PLANNED;
  }

  /** The form is for a new allocation, or a change to a Planned or (correction) dispatched one. */
  get showForm() {
    return (
      this.canAllocate &&
      (!this.hasAssignment || this.isPlanned || this.showCorrect)
    );
  }

  get showAllocate() {
    return this.canAllocate && !this.hasAssignment;
  }

  get showReallocate() {
    return this.canAllocate && this.isPlanned;
  }

  get showRelease() {
    return this.canAllocate && this.isPlanned;
  }

  get showCorrect() {
    return (
      !!(this.context && this.context.canCorrect) &&
      this.hasAssignment &&
      !this.isPlanned &&
      this._status === ON_HOLD
    );
  }

  get isSaveDisabled() {
    return this.isWorking || !this.vehicleId || !this.driverId;
  }

  get allocateLabel() {
    return LABEL_ALLOCATE;
  }

  get reallocateLabel() {
    return LABEL_REALLOCATE;
  }

  get releaseLabel() {
    return LABEL_RELEASE;
  }

  get correctLabel() {
    return LABEL_CORRECT;
  }

  handleVehicle(event) {
    this.vehicleId = event.detail.value;
  }

  handleDriver(event) {
    this.driverId = event.detail.value;
  }

  handleRemarks(event) {
    this.remarks = event.detail.value;
  }

  request(extra = {}) {
    return {
      shipmentId: this.recordId,
      vehicleId: this.vehicleId,
      driverId: this.driverId,
      remarks: this.remarks || null,
      ...extra
    };
  }

  handleAllocate() {
    return this.run(
      () => allocate({ request: this.request() }),
      LABEL_ALLOCATED
    );
  }

  handleReallocate() {
    return this.run(
      () => reallocate({ request: this.request() }),
      LABEL_REALLOCATED
    );
  }

  async handleRelease() {
    const answer = await ConfirmationDialog.open({
      size: "small",
      label: LABEL_RELEASE,
      message: formatLabel(LABEL_CONFIRM_RELEASE, this.context.shipment.Name),
      confirmLabel: LABEL_RELEASE,
      variant: "destructive"
    });
    if (answer && answer.confirmed) {
      await this.run(
        () => release({ assignmentId: this.assignment.Id }),
        LABEL_RELEASED
      );
    }
  }

  async handleCorrect() {
    const answer = await ConfirmationDialog.open({
      size: "small",
      label: LABEL_CORRECT,
      confirmLabel: LABEL_CORRECT,
      reasonLabel: LABEL_CORRECTION_REASON,
      reasonRequired: true
    });
    if (answer && answer.confirmed) {
      await this.run(
        () =>
          correctDispatchedAllocation({
            request: this.request({ correctionReason: answer.reason })
          }),
        LABEL_CORRECTED
      );
    }
  }

  async run(action, successMessage) {
    this.isWorking = true;
    try {
      const result = await action();
      if (handleServiceResult(this, result, successMessage)) {
        await notifyRecordUpdateAvailable([{ recordId: this.recordId }]);
        await this.load();
      }
    } catch (error) {
      showError(this, error);
    } finally {
      this.isWorking = false;
    }
  }
}
