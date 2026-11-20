import { LightningElement, api } from "lwc";
import LABEL_LOADING from "@salesforce/label/c.eLogix_UI_Loading";

/**
 * SLDS spinner with an accessible label and an optional visible message. The spinner covers its
 * nearest positioned container, so it sits inside its own relative block of a minimum height.
 */
export default class LoadingIndicator extends LightningElement {
  /** Text read by screen readers; defaults to the eLogix "Loading" label. */
  @api alternativeText;
  /** Optional message shown under the spinner and announced politely. */
  @api message;
  /** lightning-spinner size: small, medium or large. */
  @api size = "medium";
  /** lightning-spinner variant: base, brand or inverse. */
  @api variant = "brand";

  get spinnerText() {
    return this.alternativeText || LABEL_LOADING;
  }
}
