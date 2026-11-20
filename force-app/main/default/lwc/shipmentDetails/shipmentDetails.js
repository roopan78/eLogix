import { LightningElement, api, wire } from "lwc";
import {
  getRecord,
  getFieldValue,
  notifyRecordUpdateAvailable
} from "lightning/uiRecordApi";
import NAME_FIELD from "@salesforce/schema/Shipment__c.Name";
import STATUS_FIELD from "@salesforce/schema/Shipment__c.Status__c";
import getStatusOptions from "@salesforce/apex/ShipmentConsoleController.getStatusOptions";
import changeStatus from "@salesforce/apex/ShipmentConsoleController.changeStatus";
import ConfirmationDialog from "c/confirmationDialog";
import { handleServiceResult, showError, errorMessage } from "c/elogixUtils";
import LABEL_TITLE from "@salesforce/label/c.eLogix_UI_Shipment_Details";
import LABEL_CHANGE_STATUS from "@salesforce/label/c.eLogix_UI_Change_Status";
import LABEL_NEW_STATUS from "@salesforce/label/c.eLogix_UI_New_Status";
import LABEL_CHECKED_ON_SAVE from "@salesforce/label/c.eLogix_UI_Checked_On_Save";
import LABEL_STATUS_CHECKED_ON_SAVE from "@salesforce/label/c.eLogix_UI_Status_Checked_On_Save";
import LABEL_OVERRIDE from "@salesforce/label/c.eLogix_UI_Override";
import LABEL_NO_OPTIONS from "@salesforce/label/c.eLogix_UI_No_Status_Options";
import LABEL_DELIVERY_NOTE from "@salesforce/label/c.eLogix_UI_Delivery_Statuses_Note";
import LABEL_CONFIRM_CHANGE from "@salesforce/label/c.eLogix_UI_Confirm_Status_Change";
import LABEL_STATUS_CHANGED from "@salesforce/label/c.eLogix_UI_Status_Changed";
import LABEL_HOLD_REASON from "@salesforce/label/c.eLogix_UI_Hold_Reason";
import LABEL_CANCELLATION_REASON from "@salesforce/label/c.eLogix_UI_Cancellation_Reason";

/** Statuses whose validation rules need a reason; the reason fills Hold_Reason__c or Cancellation_Reason__c. */
const REASON_LABEL_BY_STATUS = {
  "On Hold": LABEL_HOLD_REASON,
  Cancelled: LABEL_CANCELLATION_REASON
};
const REASON_MAX_LENGTH = 255;

function format(template, ...values) {
  return values.reduce(
    (text, value, index) => text.replace(`{${index}}`, value),
    template
  );
}

/**
 * Shipment record page panel: key fields (lightning-record-view-form, so FLS applies), the status
 * badge, and the status change. Options come from ShipmentConsoleController.getStatusOptions (the real
 * ShipmentStatusPolicy, decision P5); options checked only on save are marked. The change itself goes
 * through ShipmentService, so the Shipment__c trigger enforces every rule.
 */
export default class ShipmentDetails extends LightningElement {
  @api recordId;

  labels = {
    title: LABEL_TITLE,
    changeStatus: LABEL_CHANGE_STATUS,
    newStatus: LABEL_NEW_STATUS,
    noOptions: LABEL_NO_OPTIONS,
    deliveryNote: LABEL_DELIVERY_NOTE
  };

  shipmentName;
  status;
  options = [];
  selectedStatus;
  optionsError;
  isLoadingOptions = true;
  isSaving = false;

  @wire(getRecord, {
    recordId: "$recordId",
    fields: [NAME_FIELD, STATUS_FIELD]
  })
  wiredShipment({ data, error }) {
    if (data) {
      const status = getFieldValue(data, STATUS_FIELD);
      this.shipmentName = getFieldValue(data, NAME_FIELD);
      if (status !== this.status) {
        this.status = status;
        this.loadOptions();
      }
    } else if (error) {
      this.optionsError = errorMessage(error);
      this.isLoadingOptions = false;
    }
  }

  get comboboxOptions() {
    return this.options.map((option) => {
      const notes = [];
      if (option.validatedOnSave) {
        notes.push(LABEL_CHECKED_ON_SAVE);
      }
      if (option.byOverride) {
        notes.push(LABEL_OVERRIDE);
      }
      return {
        label: notes.length
          ? `${option.label} (${notes.join(", ")})`
          : option.label,
        value: option.value
      };
    });
  }

  get hasOptions() {
    return this.options.length > 0;
  }

  get selectedOption() {
    return this.options.find((option) => option.value === this.selectedStatus);
  }

  get selectedNote() {
    const option = this.selectedOption;
    return option && option.validatedOnSave && option.note
      ? format(LABEL_STATUS_CHECKED_ON_SAVE, option.note)
      : null;
  }

  get isChangeDisabled() {
    return !this.selectedStatus || this.isSaving;
  }

  async loadOptions() {
    if (!this.recordId) {
      return;
    }
    this.isLoadingOptions = true;
    this.optionsError = undefined;
    try {
      this.options =
        (await getStatusOptions({ shipmentId: this.recordId })) || [];
    } catch (error) {
      this.options = [];
      this.optionsError = errorMessage(error);
    } finally {
      this.selectedStatus = undefined;
      this.isLoadingOptions = false;
    }
  }

  handleSelect(event) {
    this.selectedStatus = event.detail.value;
  }

  async handleChangeStatus() {
    const option = this.selectedOption;
    if (!option) {
      return;
    }
    const reasonLabel = REASON_LABEL_BY_STATUS[option.value];
    const answer = await ConfirmationDialog.open({
      size: "small",
      label: this.labels.changeStatus,
      message: format(
        LABEL_CONFIRM_CHANGE,
        this.shipmentName,
        this.status,
        option.label
      ),
      confirmLabel: this.labels.changeStatus,
      variant: option.value === "Cancelled" ? "destructive" : "brand",
      reasonLabel,
      reasonRequired: !!reasonLabel,
      reasonMaxLength: REASON_MAX_LENGTH
    });
    if (!answer || !answer.confirmed) {
      return;
    }

    this.isSaving = true;
    try {
      const result = await changeStatus({
        shipmentId: this.recordId,
        targetStatus: option.value,
        reason: answer.reason
      });
      const changed = handleServiceResult(
        this,
        result,
        format(LABEL_STATUS_CHANGED, option.label)
      );
      if (changed) {
        await notifyRecordUpdateAvailable([{ recordId: this.recordId }]);
        this.dispatchEvent(
          new CustomEvent("statuschange", {
            detail: { recordId: this.recordId, status: option.value }
          })
        );
      }
    } catch (error) {
      showError(this, error);
    } finally {
      this.isSaving = false;
    }
  }
}
