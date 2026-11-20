import { LightningElement, api } from "lwc";
import { NavigationMixin } from "lightning/navigation";
import { showSuccess } from "c/elogixUtils";
import LABEL_TITLE from "@salesforce/label/c.eLogix_UI_Book_Shipment";
import LABEL_SAVE_DRAFT from "@salesforce/label/c.eLogix_UI_Save_Draft";
import LABEL_SUBMIT from "@salesforce/label/c.eLogix_UI_Submit_Request";
import LABEL_SAVED from "@salesforce/label/c.eLogix_UI_Request_Saved";
import LABEL_SUBMITTED from "@salesforce/label/c.eLogix_UI_Request_Submitted";

const DRAFT = "Draft";
const SUBMITTED = "Submitted";

/**
 * Shipment booking: a Shipment_Request__c form (lightning-record-edit-form, so Lightning Data Service
 * applies CRUD, FLS and the request validation rules). "Save as draft" saves it as Draft; "Submit
 * request" saves it as Submitted, ready for quotation. On an Account record page the customer is
 * pre-filled. Raises "requestcreated" with the new record Id, then opens the new request, or clears
 * the form for the next booking when stay-on-page is set.
 */
export default class ShipmentBooking extends NavigationMixin(LightningElement) {
  /** Record context: on an Account page, the customer to pre-fill. */
  @api recordId;
  @api objectApiName;
  /** Clear the form for another booking instead of opening the new request. */
  @api stayOnPage = false;

  labels = {
    title: LABEL_TITLE,
    saveDraft: LABEL_SAVE_DRAFT,
    submit: LABEL_SUBMIT
  };

  isSaving = false;
  _targetStatus = DRAFT;

  get customerId() {
    return this.objectApiName === "Account" ? this.recordId : null;
  }

  handleSaveDraft() {
    this._targetStatus = DRAFT;
  }

  handleSubmitRequest() {
    this._targetStatus = SUBMITTED;
  }

  /** Adds the status chosen by the clicked button; validation stays with LDS and the validation rules. */
  handleSubmit(event) {
    event.preventDefault();
    const fields = { ...event.detail.fields, Status__c: this._targetStatus };
    this.isSaving = true;
    this.template.querySelector("lightning-record-edit-form").submit(fields);
  }

  handleSuccess(event) {
    this.isSaving = false;
    const recordId = event.detail.id;
    showSuccess(
      this,
      this._targetStatus === SUBMITTED ? LABEL_SUBMITTED : LABEL_SAVED
    );
    this.dispatchEvent(
      new CustomEvent("requestcreated", { detail: { recordId } })
    );
    if (this.stayOnPage) {
      this.resetForm();
    } else {
      this[NavigationMixin.Navigate]({
        type: "standard__recordPage",
        attributes: {
          recordId,
          objectApiName: "Shipment_Request__c",
          actionName: "view"
        }
      });
    }
  }

  /** Errors are shown by lightning-messages; only the saving state is cleared here. */
  handleError() {
    this.isSaving = false;
  }

  resetForm() {
    this.template
      .querySelectorAll("lightning-input-field")
      .forEach((field) => field.reset());
  }
}
