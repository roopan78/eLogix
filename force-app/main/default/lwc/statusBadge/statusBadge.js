import { LightningElement, api } from "lwc";

/**
 * Colour-coded SLDS badge for eLogix statuses (shipment, assignment, delivery, quotation, integration
 * log). Presentation only: the mapping groups statuses by meaning; unknown statuses are neutral.
 */
const THEME_BY_STATUS = {
  success: [
    "Delivered",
    "Closed",
    "Approved",
    "Accepted",
    "Converted",
    "Active",
    "Available",
    "Completed",
    "Success",
    "Paid",
    "Verified"
  ],
  warning: [
    "On Hold",
    "Delayed",
    "Pending Approval",
    "Retrying",
    "Under Maintenance",
    "Return Initiated",
    "Partially Paid",
    "On Leave"
  ],
  error: [
    "Cancelled",
    "Failed Delivery",
    "Failed",
    "Damaged",
    "Lost",
    "Rejected",
    "Dead Letter",
    "Inactive",
    "Expired",
    "Overdue"
  ],
  inverse: [
    "Requested",
    "Quoted",
    "Confirmed",
    "Ready for Dispatch",
    "Dispatched",
    "In Transit",
    "Out for Delivery",
    "Submitted",
    "Sent",
    "Scheduled",
    "On Duty",
    "Assigned"
  ]
};

const CLASS_BY_VARIANT = {
  success: "slds-badge slds-theme_success",
  warning: "slds-badge slds-theme_warning",
  error: "slds-badge slds-theme_error",
  inverse: "slds-badge slds-badge_inverse",
  lightest: "slds-badge slds-badge_lightest"
};

const VARIANT_LOOKUP = Object.entries(THEME_BY_STATUS).reduce(
  (lookup, [variant, statuses]) => {
    statuses.forEach((status) => {
      lookup[status.toLowerCase()] = variant;
    });
    return lookup;
  },
  {}
);

export default class StatusBadge extends LightningElement {
  /** The status value, for example "In Transit". */
  @api status;
  /** Optional display text (for example a translated picklist label); defaults to the status. */
  @api label;
  /** Optional explicit variant: success, warning, error, inverse or lightest. */
  @api variant;

  get hasStatus() {
    return !!(this.label || this.status);
  }

  get text() {
    return this.label || this.status;
  }

  get resolvedVariant() {
    if (this.variant && CLASS_BY_VARIANT[this.variant]) {
      return this.variant;
    }
    const key =
      typeof this.status === "string" ? this.status.trim().toLowerCase() : "";
    return VARIANT_LOOKUP[key] || "lightest";
  }

  get badgeClass() {
    return CLASS_BY_VARIANT[this.resolvedVariant];
  }
}
