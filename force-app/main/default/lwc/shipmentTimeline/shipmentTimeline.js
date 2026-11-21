import { LightningElement, api, wire } from "lwc";
import { refreshApex } from "@salesforce/apex";
import { getRecord } from "lightning/uiRecordApi";
import STATUS_FIELD from "@salesforce/schema/Shipment__c.Status__c";
import TRACKED_AT_FIELD from "@salesforce/schema/Shipment__c.Latest_Tracking_Timestamp__c";
import getTimeline from "@salesforce/apex/TrackingConsoleController.getTimeline";
import { errorMessage } from "c/elogixUtils";
import LABEL_TITLE from "@salesforce/label/c.eLogix_UI_Tracking_History";
import LABEL_EMPTY from "@salesforce/label/c.eLogix_UI_No_Tracking_Events";
import LABEL_REFRESH from "@salesforce/label/c.eLogix_UI_Refresh";

/**
 * Shipment tracking history (newest first) as an SLDS timeline. Reads through
 * TrackingConsoleController.getTimeline (user mode). Refreshes itself when the shipment's status or
 * latest tracking time changes in Lightning Data Service, for example after a status change on the
 * same page.
 */
export default class ShipmentTimeline extends LightningElement {
  @api recordId;

  labels = { title: LABEL_TITLE, empty: LABEL_EMPTY, refresh: LABEL_REFRESH };

  events = [];
  error;
  isLoading = true;

  _wiredTimeline;
  _version;

  @wire(getTimeline, { shipmentId: "$recordId" })
  wiredTimeline(result) {
    this._wiredTimeline = result;
    const { data, error } = result;
    if (data) {
      this.events = data.map((event) => ({
        ...event,
        isStatusEvent: !!event.To_Status__c
      }));
      this.error = undefined;
      this.isLoading = false;
    } else if (error) {
      this.events = [];
      this.error = errorMessage(error);
      this.isLoading = false;
    }
  }

  /** A change to the shipment's status or tracking summary means new history: reload it. */
  @wire(getRecord, {
    recordId: "$recordId",
    fields: [STATUS_FIELD, TRACKED_AT_FIELD]
  })
  wiredShipment({ data }) {
    if (!data) {
      return;
    }
    const version = `${data.fields.Status__c.value}|${data.fields.Latest_Tracking_Timestamp__c.value}`;
    if (this._version !== undefined && this._version !== version) {
      this.handleRefresh();
    }
    this._version = version;
  }

  get isEmpty() {
    return !this.isLoading && !this.error && this.events.length === 0;
  }

  get hasEvents() {
    return !this.isLoading && !this.error && this.events.length > 0;
  }

  handleRefresh() {
    if (!this._wiredTimeline) {
      return Promise.resolve();
    }
    this.isLoading = true;
    return refreshApex(this._wiredTimeline).finally(() => {
      this.isLoading = false;
    });
  }
}
