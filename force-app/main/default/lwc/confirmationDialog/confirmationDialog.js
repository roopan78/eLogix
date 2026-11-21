import { api } from "lwc";
import LightningModal from "lightning/modal";
import LABEL_CONFIRM from "@salesforce/label/c.eLogix_UI_Confirm";
import LABEL_CANCEL from "@salesforce/label/c.eLogix_UI_Cancel";

/**
 * Confirmation modal (LightningModal). Optionally collects a reason, for example the hold or
 * cancellation reason a status change needs.
 *
 *   const result = await ConfirmationDialog.open({
 *       size: 'small', label: 'Cancel shipment', message: 'This cannot be undone.',
 *       confirmLabel: 'Cancel shipment', variant: 'destructive',
 *       reasonLabel: 'Cancellation reason', reasonRequired: true
 *   });
 *   if (result?.confirmed) { ... result.reason ... }
 *
 * Resolves to { confirmed: true, reason } on confirm, { confirmed: false } on cancel, and undefined
 * when closed with the header X or Escape.
 */
export default class ConfirmationDialog extends LightningModal {
  /** Body text. The header text is LightningModal's own `label`. */
  @api message;
  @api confirmLabel;
  @api cancelLabel;
  /** Confirm button variant: brand (default) or destructive. */
  @api variant = "brand";
  /** When set, shows a reason text area with this label. */
  @api reasonLabel;
  @api reasonRequired = false;
  /** Maximum reason length (for example the target field's length). */
  @api reasonMaxLength = 255;

  reason = "";

  get confirmText() {
    return this.confirmLabel || LABEL_CONFIRM;
  }

  get cancelText() {
    return this.cancelLabel || LABEL_CANCEL;
  }

  get confirmVariant() {
    return this.variant === "destructive" ? "destructive" : "brand";
  }

  get showReason() {
    return !!this.reasonLabel;
  }

  handleReasonChange(event) {
    this.reason = event.detail.value;
  }

  handleCancel() {
    this.close({ confirmed: false });
  }

  handleConfirm() {
    if (this.showReason) {
      const input = this.template.querySelector("lightning-textarea");
      if (input && !input.reportValidity()) {
        return;
      }
    }
    const reason = typeof this.reason === "string" ? this.reason.trim() : "";
    this.close({ confirmed: true, reason: reason || null });
  }
}
