/*
 * Jest stub for lightning/modal (LightningModal), which @salesforce/sfdx-lwc-jest does not provide.
 * Mirrors what the components use: the modal properties, close() and the static open().
 * close(result) dispatches a "close" event with the result as detail, so tests can observe it
 * (component prototypes are frozen and cannot be patched). open() is a jest mock.
 */
import { LightningElement } from "lwc";

export default class LightningModal extends LightningElement {
  // Plain fields (this folder is linted without the LWC decorator parser); enough for the template.
  label;
  size;
  description;
  disableClose;

  close(result) {
    this.dispatchEvent(new CustomEvent("close", { detail: result }));
  }
}

LightningModal.open = jest.fn(() => Promise.resolve());
