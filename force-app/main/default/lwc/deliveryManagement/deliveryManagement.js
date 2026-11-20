import { LightningElement, api, wire } from "lwc";
import {
  getRecord,
  getFieldValue,
  notifyRecordUpdateAvailable
} from "lightning/uiRecordApi";
import { getObjectInfo, getPicklistValues } from "lightning/uiObjectInfoApi";
import NAME_FIELD from "@salesforce/schema/Shipment__c.Name";
import STATUS_FIELD from "@salesforce/schema/Shipment__c.Status__c";
import DELIVERY_OBJECT from "@salesforce/schema/Delivery__c";
import FAILURE_REASON_FIELD from "@salesforce/schema/Delivery__c.Failure_Reason__c";
import PROOF_OBJECT from "@salesforce/schema/Proof_of_Delivery__c";
import getDeliveryState from "@salesforce/apex/DeliveryConsoleController.getDeliveryState";
import startAttempt from "@salesforce/apex/DeliveryConsoleController.startAttempt";
import recordProof from "@salesforce/apex/DeliveryConsoleController.recordProof";
import confirmDelivery from "@salesforce/apex/DeliveryConsoleController.confirmDelivery";
import recordFailure from "@salesforce/apex/DeliveryConsoleController.recordFailure";
import verifyProof from "@salesforce/apex/DeliveryConsoleController.verifyProof";
import ConfirmationDialog from "c/confirmationDialog";
import {
  handleServiceResult,
  showError,
  showSuccess,
  errorMessage,
  formatLabel
} from "c/elogixUtils";
import LABEL_TITLE from "@salesforce/label/c.eLogix_UI_Delivery";
import LABEL_NO_ATTEMPTS from "@salesforce/label/c.eLogix_UI_No_Attempts";
import LABEL_START from "@salesforce/label/c.eLogix_UI_Start_Attempt";
import LABEL_STARTED from "@salesforce/label/c.eLogix_UI_Attempt_Started";
import LABEL_RECORD_PROOF from "@salesforce/label/c.eLogix_UI_Record_Proof";
import LABEL_PROOF_RECORDED from "@salesforce/label/c.eLogix_UI_Proof_Recorded";
import LABEL_RECEIVER from "@salesforce/label/c.eLogix_UI_Receiver_Name";
import LABEL_RECEIVED_AT from "@salesforce/label/c.eLogix_UI_Received_At";
import LABEL_SIGNATURE from "@salesforce/label/c.eLogix_UI_Signature_Reference";
import LABEL_NOTES from "@salesforce/label/c.eLogix_UI_Delivery_Notes";
import LABEL_HAS_EXCEPTION from "@salesforce/label/c.eLogix_UI_Has_Exception";
import LABEL_EXCEPTION_NOTES from "@salesforce/label/c.eLogix_UI_Exception_Notes";
import LABEL_UPLOAD from "@salesforce/label/c.eLogix_UI_Upload_Evidence";
import LABEL_UPLOADED from "@salesforce/label/c.eLogix_UI_Evidence_Uploaded";
import LABEL_CONFIRM from "@salesforce/label/c.eLogix_UI_Confirm_Delivery";
import LABEL_CONFIRMED from "@salesforce/label/c.eLogix_UI_Delivery_Confirmed";
import LABEL_CONFIRM_QUESTION from "@salesforce/label/c.eLogix_UI_Confirm_Delivery_Question";
import LABEL_RECORD_FAILURE from "@salesforce/label/c.eLogix_UI_Record_Failure";
import LABEL_FAILURE_RECORDED from "@salesforce/label/c.eLogix_UI_Failure_Recorded";
import LABEL_FAILURE_REASON from "@salesforce/label/c.eLogix_UI_Failure_Reason";
import LABEL_FAILURE_NOTES from "@salesforce/label/c.eLogix_UI_Failure_Notes";
import LABEL_VERIFY from "@salesforce/label/c.eLogix_UI_Verify_Proof";
import LABEL_VERIFIED from "@salesforce/label/c.eLogix_UI_Proof_Verified";
import LABEL_PROOFS from "@salesforce/label/c.eLogix_UI_Proofs";
import LABEL_SAVE from "@salesforce/label/c.eLogix_UI_Save";
import LABEL_CANCEL from "@salesforce/label/c.eLogix_UI_Cancel";

/** Attempt statuses that are still open (DeliveryDomain.OPEN). */
const OPEN_ATTEMPT = ["Scheduled", "Out for Delivery"];
/** Shipment statuses from which DeliveryService starts an attempt; it re-checks them on save. */
const STARTABLE = ["In Transit", "Delayed", "Failed Delivery"];

/**
 * Shipment record page panel for delivery (decision P5: the only UI path to Out for Delivery,
 * Delivered and Failed Delivery). Start attempt, record the proof of delivery, upload evidence to it,
 * confirm, record a failure and verify a delivered proof. Every action is DeliveryService's, which
 * enforces the attempt sequence, the required proof and evidence, the attempt limit and access; the
 * buttons only follow the current state.
 */
export default class DeliveryManagement extends LightningElement {
  @api recordId;

  labels = {
    title: LABEL_TITLE,
    noAttempts: LABEL_NO_ATTEMPTS,
    start: LABEL_START,
    recordProof: LABEL_RECORD_PROOF,
    receiver: LABEL_RECEIVER,
    receivedAt: LABEL_RECEIVED_AT,
    signature: LABEL_SIGNATURE,
    notes: LABEL_NOTES,
    hasException: LABEL_HAS_EXCEPTION,
    exceptionNotes: LABEL_EXCEPTION_NOTES,
    upload: LABEL_UPLOAD,
    confirm: LABEL_CONFIRM,
    recordFailure: LABEL_RECORD_FAILURE,
    failureReason: LABEL_FAILURE_REASON,
    failureNotes: LABEL_FAILURE_NOTES,
    verify: LABEL_VERIFY,
    proofs: LABEL_PROOFS,
    save: LABEL_SAVE,
    cancel: LABEL_CANCEL
  };

  name;
  status;
  attempts = [];
  proofs = [];
  loadError;
  isLoading = true;
  isWorking = false;
  mode; // "proof" | "failure" while a form is open
  proofForm = {};
  failureForm = {};
  failureReasons = [];
  canVerify = false;
  deliveryLabels = {};
  _deliveryRecordTypeId;

  @wire(getRecord, {
    recordId: "$recordId",
    fields: [NAME_FIELD, STATUS_FIELD]
  })
  wiredShipment({ data, error }) {
    if (data) {
      this.name = getFieldValue(data, NAME_FIELD);
      const status = getFieldValue(data, STATUS_FIELD);
      if (status !== this.status) {
        this.status = status;
        this.load();
      }
    } else if (error) {
      this.loadError = errorMessage(error);
      this.isLoading = false;
    }
  }

  @wire(getObjectInfo, { objectApiName: DELIVERY_OBJECT })
  wiredDeliveryInfo({ data }) {
    if (data) {
      this._deliveryRecordTypeId = data.defaultRecordTypeId;
      this.deliveryLabels = Object.fromEntries(
        Object.entries(data.fields).map(([name, field]) => [name, field.label])
      );
    }
  }

  @wire(getPicklistValues, {
    recordTypeId: "$_deliveryRecordTypeId",
    fieldApiName: FAILURE_REASON_FIELD
  })
  wiredReasons({ data }) {
    if (data) {
      this.failureReasons = data.values.map((v) => ({
        label: v.label,
        value: v.value
      }));
    }
  }

  /** Verification is a field permission (Verified_By__c); the service checks it again. */
  @wire(getObjectInfo, { objectApiName: PROOF_OBJECT })
  wiredProofInfo({ data }) {
    if (data) {
      const field = data.fields.Verified_By__c;
      this.canVerify = !!(field && field.updateable);
    }
  }

  async load() {
    this.isLoading = true;
    this.loadError = undefined;
    try {
      const state = await getDeliveryState({ shipmentId: this.recordId });
      this.attempts = (state && state.attempts) || [];
      this.proofs = (state && state.proofs) || [];
    } catch (error) {
      this.attempts = [];
      this.proofs = [];
      this.loadError = errorMessage(error);
    } finally {
      this.isLoading = false;
    }
  }

  get latestAttempt() {
    return this.attempts.length ? this.attempts[0] : undefined;
  }

  get openAttempt() {
    const latest = this.latestAttempt;
    return latest && OPEN_ATTEMPT.includes(latest.Delivery_Status__c)
      ? latest
      : undefined;
  }

  get openProof() {
    const attempt = this.openAttempt;
    return attempt
      ? this.proofs.find((p) => p.Delivery__c === attempt.Id)
      : undefined;
  }

  get hasAttempts() {
    return this.attempts.length > 0;
  }

  get attemptRows() {
    return this.attempts.map((a) => ({
      ...a,
      deliveredBy: a.Delivered_By__r ? a.Delivered_By__r.Name : null
    }));
  }

  /** Column headers are the fields' own (translated) labels. */
  get attemptColumns() {
    const l = (field) => this.deliveryLabels[field] || field;
    return [
      {
        label: l("Attempt_Number__c"),
        fieldName: "Attempt_Number__c",
        type: "number",
        initialWidth: 90
      },
      { label: l("Delivery_Status__c"), fieldName: "Delivery_Status__c" },
      { label: l("Receiver_Name__c"), fieldName: "Receiver_Name__c" },
      { label: l("Failure_Reason__c"), fieldName: "Failure_Reason__c" },
      { label: l("Delivered_By__c"), fieldName: "deliveredBy" },
      {
        label: l("Delivery_Date__c"),
        fieldName: "Delivery_Date__c",
        type: "date",
        typeAttributes: {
          day: "2-digit",
          month: "short",
          hour: "2-digit",
          minute: "2-digit"
        }
      }
    ];
  }

  get proofRows() {
    return this.proofs.map((p) => ({
      ...p,
      verifiedBy: p.Verified_By__r ? p.Verified_By__r.Name : null,
      canVerifyRow:
        this.canVerify &&
        !p.Verified_By__r &&
        this.attempts.some(
          (a) => a.Id === p.Delivery__c && a.Delivery_Status__c === "Delivered"
        )
    }));
  }

  get hasProofs() {
    return this.proofs.length > 0;
  }

  get canStart() {
    return !this.openAttempt && STARTABLE.includes(this.status);
  }

  get showProofForm() {
    return this.mode === "proof";
  }

  get showFailureForm() {
    return this.mode === "failure";
  }

  get showOpenActions() {
    return !!this.openAttempt && !this.mode;
  }

  get canRecordProof() {
    return !this.openProof;
  }

  get openProofId() {
    return this.openProof ? this.openProof.Id : undefined;
  }

  handleStart() {
    return this.run(
      () => startAttempt({ shipmentId: this.recordId }),
      LABEL_STARTED
    );
  }

  handleShowProof() {
    this.proofForm = {};
    this.mode = "proof";
  }

  handleShowFailure() {
    this.failureForm = {};
    this.mode = "failure";
  }

  handleCancelForm() {
    this.mode = undefined;
  }

  handleProofField(event) {
    const name = event.target.dataset.field;
    const value =
      event.target.type === "checkbox"
        ? event.target.checked
        : event.detail.value;
    this.proofForm = { ...this.proofForm, [name]: value };
  }

  handleFailureField(event) {
    this.failureForm = {
      ...this.failureForm,
      [event.target.dataset.field]: event.detail.value
    };
  }

  async handleSaveProof() {
    if (!this.validate(".elogix-proof-field")) {
      return;
    }
    const f = this.proofForm;
    await this.run(
      () =>
        recordProof({
          request: {
            shipmentId: this.recordId,
            receiverName: f.receiverName,
            receivedAt: f.receivedAt || null,
            signatureReference: f.signatureReference || null,
            deliveryNotes: f.deliveryNotes || null,
            hasException: !!f.hasException,
            exceptionNotes: f.exceptionNotes || null
          }
        }),
      LABEL_PROOF_RECORDED
    );
  }

  async handleSaveFailure() {
    if (!this.validate(".elogix-failure-field")) {
      return;
    }
    await this.run(
      () =>
        recordFailure({
          request: {
            shipmentId: this.recordId,
            reason: this.failureForm.reason,
            notes: this.failureForm.notes || null
          }
        }),
      LABEL_FAILURE_RECORDED
    );
  }

  async handleConfirm() {
    const answer = await ConfirmationDialog.open({
      size: "small",
      label: LABEL_CONFIRM,
      message: formatLabel(LABEL_CONFIRM_QUESTION, this.name),
      confirmLabel: LABEL_CONFIRM
    });
    if (answer && answer.confirmed) {
      await this.run(
        () => confirmDelivery({ shipmentId: this.recordId }),
        LABEL_CONFIRMED
      );
    }
  }

  handleVerify(event) {
    const proofId = event.target.dataset.id;
    return this.run(() => verifyProof({ proofId }), LABEL_VERIFIED);
  }

  handleUploadFinished() {
    showSuccess(this, LABEL_UPLOADED);
  }

  validate(selector) {
    return [...this.template.querySelectorAll(selector)].every((input) =>
      input.reportValidity()
    );
  }

  async run(action, successMessage) {
    this.isWorking = true;
    try {
      const result = await action();
      if (handleServiceResult(this, result, successMessage)) {
        this.mode = undefined;
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
