import { LightningElement, api, wire } from "lwc";
import { NavigationMixin } from "lightning/navigation";
import { refreshApex } from "@salesforce/apex";
import {
  getRecord,
  getFieldValue,
  updateRecord,
  notifyRecordUpdateAvailable
} from "lightning/uiRecordApi";
import { getObjectInfo } from "lightning/uiObjectInfoApi";
import LINE_OBJECT from "@salesforce/schema/Quotation_Line__c";
import NAME_FIELD from "@salesforce/schema/Quotation__c.Name";
import STATUS_FIELD from "@salesforce/schema/Quotation__c.Status__c";
import getLines from "@salesforce/apex/QuotationConsoleController.getLines";
import createFromRequest from "@salesforce/apex/QuotationConsoleController.createFromRequest";
import recalculate from "@salesforce/apex/QuotationConsoleController.recalculate";
import submitForApproval from "@salesforce/apex/QuotationConsoleController.submitForApproval";
import approve from "@salesforce/apex/QuotationConsoleController.approve";
import reject from "@salesforce/apex/QuotationConsoleController.reject";
import convertToShipment from "@salesforce/apex/QuotationConsoleController.convertToShipment";
import canApprove from "@salesforce/customPermission/eLogix_Approve_Quotation";
import ConfirmationDialog from "c/confirmationDialog";
import {
  handleServiceResult,
  showError,
  showSuccess,
  formatLabel
} from "c/elogixUtils";
import LABEL_TITLE from "@salesforce/label/c.eLogix_UI_Quotation_Builder";
import LABEL_LINES from "@salesforce/label/c.eLogix_UI_Charge_Lines";
import LABEL_NO_LINES from "@salesforce/label/c.eLogix_UI_No_Charge_Lines";
import LABEL_CREATE from "@salesforce/label/c.eLogix_UI_Create_Quotation";
import LABEL_CREATED from "@salesforce/label/c.eLogix_UI_Quotation_Created";
import LABEL_RECALCULATE from "@salesforce/label/c.eLogix_UI_Recalculate";
import LABEL_RECALCULATED from "@salesforce/label/c.eLogix_UI_Recalculated";
import LABEL_SUBMIT from "@salesforce/label/c.eLogix_UI_Submit_For_Approval";
import LABEL_SUBMITTED from "@salesforce/label/c.eLogix_UI_Submitted_For_Approval";
import LABEL_APPROVE from "@salesforce/label/c.eLogix_UI_Approve";
import LABEL_APPROVED from "@salesforce/label/c.eLogix_UI_Approved";
import LABEL_REJECT from "@salesforce/label/c.eLogix_UI_Reject";
import LABEL_REJECTED from "@salesforce/label/c.eLogix_UI_Rejected";
import LABEL_REJECTION_REASON from "@salesforce/label/c.eLogix_UI_Rejection_Reason";
import LABEL_CONFIRM_REJECT from "@salesforce/label/c.eLogix_UI_Confirm_Reject";
import LABEL_MARK_SENT from "@salesforce/label/c.eLogix_UI_Mark_Sent";
import LABEL_MARKED_SENT from "@salesforce/label/c.eLogix_UI_Marked_Sent";
import LABEL_ACCEPT from "@salesforce/label/c.eLogix_UI_Record_Acceptance";
import LABEL_ACCEPTED from "@salesforce/label/c.eLogix_UI_Acceptance_Recorded";
import LABEL_CONVERT from "@salesforce/label/c.eLogix_UI_Convert";
import LABEL_CONVERTED from "@salesforce/label/c.eLogix_UI_Converted";
import LABEL_CONFIRM_CONVERT from "@salesforce/label/c.eLogix_UI_Confirm_Convert";
import LABEL_NO_ACTIONS from "@salesforce/label/c.eLogix_UI_No_Quotation_Actions";

/**
 * Which actions to offer per quotation status. This only decides which buttons to show; every action
 * is validated again by QuotationService (or, for Sent and Accepted, by the Quotation__c trigger).
 */
const ACTIONS_BY_STATUS = {
  Draft: ["recalculate", "submit"],
  "Pending Approval": ["approve", "reject"],
  Approved: ["markSent"],
  Sent: ["accept"],
  Accepted: ["convert"]
};

/**
 * Quotation record page panel: pricing breakdown (lightning-record-view-form, so FLS applies), charge
 * lines and the lifecycle actions. Pricing, the approval threshold, the approval permission and
 * conversion all stay in QuotationService. On a Shipment Request page it offers "Create quotation".
 */
export default class QuotationBuilder extends NavigationMixin(
  LightningElement
) {
  @api recordId;
  @api objectApiName;

  labels = {
    title: LABEL_TITLE,
    lines: LABEL_LINES,
    noLines: LABEL_NO_LINES,
    create: LABEL_CREATE,
    noActions: LABEL_NO_ACTIONS
  };

  name;
  status;
  lines = [];
  linesError;
  isLoadingLines = true;
  isWorking = false;
  lineLabels = {};
  _wiredLines;

  get isRequestPage() {
    return this.objectApiName === "Shipment_Request__c";
  }

  get quotationId() {
    return this.isRequestPage ? undefined : this.recordId;
  }

  @wire(getRecord, {
    recordId: "$quotationId",
    fields: [NAME_FIELD, STATUS_FIELD]
  })
  wiredQuotation({ data, error }) {
    if (data) {
      this.name = getFieldValue(data, NAME_FIELD);
      this.status = getFieldValue(data, STATUS_FIELD);
    } else if (error) {
      showError(this, error);
    }
  }

  @wire(getLines, { quotationId: "$quotationId" })
  wiredLines(result) {
    this._wiredLines = result;
    if (result.data) {
      this.lines = result.data;
      this.linesError = undefined;
      this.isLoadingLines = false;
    } else if (result.error) {
      this.lines = [];
      this.linesError = result.error;
      this.isLoadingLines = false;
    }
  }

  /** Column labels are the fields' own (translated) labels. */
  @wire(getObjectInfo, { objectApiName: LINE_OBJECT })
  wiredLineInfo({ data }) {
    if (data) {
      this.lineLabels = Object.fromEntries(
        Object.entries(data.fields).map(([name, field]) => [name, field.label])
      );
    }
  }

  get lineColumns() {
    const label = (field) => this.lineLabels[field] || field;
    return [
      { label: label("Charge_Type__c"), fieldName: "Charge_Type__c" },
      { label: label("Description__c"), fieldName: "Description__c" },
      { label: label("Quantity__c"), fieldName: "Quantity__c", type: "number" },
      {
        label: label("Unit_Price__c"),
        fieldName: "Unit_Price__c",
        type: "currency"
      },
      { label: label("Amount__c"), fieldName: "Amount__c", type: "currency" }
    ];
  }

  get actions() {
    const allowed = ACTIONS_BY_STATUS[this.status] || [];
    const all = [
      { name: "recalculate", label: LABEL_RECALCULATE },
      { name: "submit", label: LABEL_SUBMIT, variant: "brand" },
      {
        name: "approve",
        label: LABEL_APPROVE,
        variant: "brand",
        approval: true
      },
      {
        name: "reject",
        label: LABEL_REJECT,
        variant: "destructive",
        approval: true
      },
      { name: "markSent", label: LABEL_MARK_SENT, variant: "brand" },
      { name: "accept", label: LABEL_ACCEPT, variant: "brand" },
      { name: "convert", label: LABEL_CONVERT, variant: "brand" }
    ];
    return all
      .filter((action) => allowed.includes(action.name))
      .filter((action) => !action.approval || canApprove)
      .map((action) => ({ variant: "neutral", ...action }));
  }

  get hasActions() {
    return this.actions.length > 0;
  }

  async handleAction(event) {
    const name = event.target.dataset.name;
    switch (name) {
      case "recalculate":
        return this.run(
          () => recalculate({ quotationId: this.recordId }),
          LABEL_RECALCULATED
        );
      case "submit":
        return this.run(
          () => submitForApproval({ quotationId: this.recordId }),
          LABEL_SUBMITTED
        );
      case "approve":
        return this.run(
          () => approve({ quotationId: this.recordId }),
          LABEL_APPROVED
        );
      case "reject":
        return this.rejectQuotation();
      case "markSent":
        return this.updateStatus("Sent", LABEL_MARKED_SENT);
      case "accept":
        return this.updateStatus("Accepted", LABEL_ACCEPTED);
      case "convert":
        return this.convert();
      default:
        return undefined;
    }
  }

  async rejectQuotation() {
    const answer = await ConfirmationDialog.open({
      size: "small",
      label: LABEL_REJECT,
      message: formatLabel(LABEL_CONFIRM_REJECT, this.name),
      confirmLabel: LABEL_REJECT,
      variant: "destructive",
      reasonLabel: LABEL_REJECTION_REASON,
      reasonRequired: true
    });
    if (answer && answer.confirmed) {
      await this.run(
        () => reject({ quotationId: this.recordId, reason: answer.reason }),
        LABEL_REJECTED
      );
    }
  }

  async convert() {
    const answer = await ConfirmationDialog.open({
      size: "small",
      label: LABEL_CONVERT,
      message: formatLabel(LABEL_CONFIRM_CONVERT, this.name),
      confirmLabel: LABEL_CONVERT
    });
    if (!answer || !answer.confirmed) {
      return;
    }
    const result = await this.run(
      () => convertToShipment({ quotationId: this.recordId }),
      LABEL_CONVERTED
    );
    if (
      result &&
      result.isSuccess &&
      result.recordIds &&
      result.recordIds.length
    ) {
      this.openRecord(result.recordIds[0], "Shipment__c");
    }
  }

  /** Sent and Accepted are plain field changes; the Quotation__c trigger validates the transition. */
  async updateStatus(status, successMessage) {
    this.isWorking = true;
    try {
      await updateRecord({ fields: { Id: this.recordId, Status__c: status } });
      showSuccess(this, successMessage);
    } catch (error) {
      showError(this, error);
    } finally {
      this.isWorking = false;
    }
  }

  async handleCreate() {
    const result = await this.run(
      () => createFromRequest({ shipmentRequestId: this.recordId }),
      LABEL_CREATED
    );
    if (
      result &&
      result.isSuccess &&
      result.recordIds &&
      result.recordIds.length
    ) {
      this.openRecord(result.recordIds[0], "Quotation__c");
    }
  }

  /** Runs one controller action, toasts its ServiceResult and refreshes the record and lines. */
  async run(action, successMessage) {
    this.isWorking = true;
    try {
      const result = await action();
      if (handleServiceResult(this, result, successMessage)) {
        await this.refresh();
      }
      return result;
    } catch (error) {
      showError(this, error);
      return undefined;
    } finally {
      this.isWorking = false;
    }
  }

  async refresh() {
    await notifyRecordUpdateAvailable([{ recordId: this.recordId }]);
    if (this._wiredLines) {
      await refreshApex(this._wiredLines);
    }
  }

  openRecord(recordId, objectApiName) {
    this[NavigationMixin.Navigate]({
      type: "standard__recordPage",
      attributes: { recordId, objectApiName, actionName: "view" }
    });
  }
}
