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

/** lightning-input-field reports a lookup value as an Id, or as a one-element array of Ids. */
function lookupId(value) {
  const id = Array.isArray(value) ? value[0] : value;
  return id || null;
}

/**
 * Shipment booking: a Shipment_Request__c form (lightning-record-edit-form, so Lightning Data Service
 * applies CRUD, FLS and the request validation rules). Customer and Business Unit are the standard
 * Salesforce lookups. "Save as draft" saves it as Draft; "Submit request" saves it as Submitted,
 * ready for quotation. On an Account record page the customer is pre-filled. Raises "requestcreated"
 * with the new record Id, then opens the new request, or clears the form for the next booking when
 * stay-on-page is set.
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
  /** The lookup values; undefined until the user changes them. */
  _customerId;
  _unitId;
  _targetStatus = DRAFT;

  get customerId() {
    if (this._customerId !== undefined) {
      return this._customerId;
    }
    return this.objectApiName === "Account" ? this.recordId : null;
  }

  get businessUnitId() {
    return this._unitId === undefined ? null : this._unitId;
  }

  handleCustomerChange(event) {
    this._customerId = lookupId(event.detail.value);
  }

  handleUnitChange(event) {
    this._unitId = lookupId(event.detail.value);
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
    this.template
      .querySelector("lightning-record-edit-form.elogix-booking")
      .submit(fields);
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
    this._customerId = undefined;
    this._unitId = undefined;
    this.template
      .querySelectorAll(
        "lightning-record-edit-form.elogix-booking lightning-input-field"
      )
      .forEach((field) => field.reset());
  }
}
