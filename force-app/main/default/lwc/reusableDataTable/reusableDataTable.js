import { LightningElement, api } from "lwc";
import { errorMessage } from "c/elogixUtils";
import LABEL_NO_RECORDS from "@salesforce/label/c.eLogix_UI_No_Records";
import LABEL_RETRY from "@salesforce/label/c.eLogix_UI_Retry";
import LABEL_ERROR_TITLE from "@salesforce/label/c.eLogix_UI_Error_Title";

/**
 * lightning-datatable with loading, error and empty states and client-side sorting. The parent owns the
 * data (wire or imperative Apex) and passes `records`, `isLoading` and `error`.
 *
 * Events: rowaction and rowselection (re-dispatched lightning-datatable details), retry (from the
 * error state's Retry button).
 */
export default class ReusableDataTable extends LightningElement {
  @api columns = [];
  @api keyField = "Id";
  @api isLoading = false;
  /** Any error shape (wire error, AuraHandledException, string); reduced with elogixUtils. */
  @api error;
  @api emptyMessage;
  /** Accessible name of the table, for example "Shipments". */
  @api tableLabel;
  @api hideCheckboxColumn = false;
  @api maxRowSelection;

  sortedBy;
  sortDirection = "asc";
  _records = [];

  @api
  get records() {
    return this._records;
  }
  set records(value) {
    this._records = Array.isArray(value) ? value : [];
  }

  get hasError() {
    return !this.isLoading && !!this.error;
  }

  get errorText() {
    return errorMessage(this.error);
  }

  get isEmpty() {
    return !this.isLoading && !this.error && this._records.length === 0;
  }

  get hasRows() {
    return !this.isLoading && !this.error && this._records.length > 0;
  }

  get emptyText() {
    return this.emptyMessage || LABEL_NO_RECORDS;
  }

  get errorTitle() {
    return LABEL_ERROR_TITLE;
  }

  get retryLabel() {
    return LABEL_RETRY;
  }

  get rows() {
    if (!this.sortedBy) {
      return this._records;
    }
    const field = this.sortedBy;
    const direction = this.sortDirection === "desc" ? -1 : 1;
    return [...this._records].sort((a, b) =>
      compare(a[field], b[field], direction)
    );
  }

  handleSort(event) {
    this.sortedBy = event.detail.fieldName;
    this.sortDirection = event.detail.sortDirection;
  }

  handleRowAction(event) {
    this.dispatchEvent(
      new CustomEvent("rowaction", {
        detail: { action: event.detail.action, row: event.detail.row }
      })
    );
  }

  handleRowSelection(event) {
    this.dispatchEvent(
      new CustomEvent("rowselection", {
        detail: { selectedRows: event.detail.selectedRows }
      })
    );
  }

  handleRetry() {
    this.dispatchEvent(new CustomEvent("retry"));
  }
}

/** Blanks last in either direction; numbers numerically; everything else as case-insensitive natural text. */
function compare(a, b, direction) {
  const aBlank = a === undefined || a === null || a === "";
  const bBlank = b === undefined || b === null || b === "";
  if (aBlank || bBlank) {
    return aBlank === bBlank ? 0 : aBlank ? 1 : -1;
  }
  if (typeof a === "number" && typeof b === "number") {
    return direction * (a - b);
  }
  return (
    direction *
    String(a).localeCompare(String(b), undefined, {
      sensitivity: "base",
      numeric: true
    })
  );
}
