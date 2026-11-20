import { LightningElement, wire } from "lwc";
import { refreshApex } from "@salesforce/apex";
import { notifyRecordUpdateAvailable } from "lightning/uiRecordApi";
import { getObjectInfo, getPicklistValues } from "lightning/uiObjectInfoApi";
import EVENT_OBJECT from "@salesforce/schema/Tracking_Event__c";
import EVENT_TYPE_FIELD from "@salesforce/schema/Tracking_Event__c.Event_Type__c";
import SHIPMENT_OBJECT from "@salesforce/schema/Shipment__c";
import getActiveShipments from "@salesforce/apex/TrackingConsoleController.getActiveShipments";
import recordEvent from "@salesforce/apex/TrackingConsoleController.recordEvent";
import { handleServiceResult, showError } from "c/elogixUtils";
import LABEL_TITLE from "@salesforce/label/c.eLogix_UI_Tracking_Console";
import LABEL_NO_ACTIVE from "@salesforce/label/c.eLogix_UI_No_Active_Shipments";
import LABEL_SELECT from "@salesforce/label/c.eLogix_UI_Select_Shipment";
import LABEL_RECORD_EVENT from "@salesforce/label/c.eLogix_UI_Record_Event";
import LABEL_EVENT_TYPE from "@salesforce/label/c.eLogix_UI_Event_Type";
import LABEL_LOCATION from "@salesforce/label/c.eLogix_UI_Location";
import LABEL_EVENT_TIME from "@salesforce/label/c.eLogix_UI_Event_Time";
import LABEL_REMARKS from "@salesforce/label/c.eLogix_UI_Remarks";
import LABEL_RECORDED from "@salesforce/label/c.eLogix_UI_Event_Recorded";
import LABEL_REFRESH from "@salesforce/label/c.eLogix_UI_Refresh";
import LABEL_SAVE from "@salesforce/label/c.eLogix_UI_Save";

/**
 * Tracking console: shipments on the road with their latest known location; selecting one shows its
 * history (shipmentTimeline) and a form to record a manual operational event. The controller always
 * records the Manual source, and TrackingService refuses status event types (those come only from
 * status changes) and future timestamps, so those rules are not repeated here.
 */
export default class TrackingConsole extends LightningElement {
  labels = {
    title: LABEL_TITLE,
    noActive: LABEL_NO_ACTIVE,
    select: LABEL_SELECT,
    recordEvent: LABEL_RECORD_EVENT,
    eventType: LABEL_EVENT_TYPE,
    location: LABEL_LOCATION,
    eventTime: LABEL_EVENT_TIME,
    remarks: LABEL_REMARKS,
    refresh: LABEL_REFRESH,
    save: LABEL_SAVE
  };

  shipments = [];
  error;
  isLoading = true;
  isSaving = false;
  selectedId;
  eventTypes = [];
  shipmentLabels = {};
  form = {};
  _wired;
  _eventRecordTypeId;

  @wire(getActiveShipments)
  wiredShipments(result) {
    this._wired = result;
    if (result.data) {
      this.shipments = result.data.map((row) => ({
        ...row,
        vehicleNumber: row.Vehicle__r ? row.Vehicle__r.Vehicle_Number__c : null,
        driverName: row.Driver__r ? row.Driver__r.Name : null
      }));
      this.error = undefined;
      this.isLoading = false;
    } else if (result.error) {
      this.shipments = [];
      this.error = result.error;
      this.isLoading = false;
    }
  }

  @wire(getObjectInfo, { objectApiName: SHIPMENT_OBJECT })
  wiredShipmentInfo({ data }) {
    if (data) {
      this.shipmentLabels = Object.fromEntries(
        Object.entries(data.fields).map(([name, field]) => [name, field.label])
      );
    }
  }

  @wire(getObjectInfo, { objectApiName: EVENT_OBJECT })
  wiredEventInfo({ data }) {
    if (data) {
      this._eventRecordTypeId = data.defaultRecordTypeId;
    }
  }

  @wire(getPicklistValues, {
    recordTypeId: "$_eventRecordTypeId",
    fieldApiName: EVENT_TYPE_FIELD
  })
  wiredEventTypes({ data }) {
    if (data) {
      this.eventTypes = data.values.map((v) => ({
        label: v.label,
        value: v.value
      }));
    }
  }

  get columns() {
    const l = (field) => this.shipmentLabels[field] || field;
    return [
      { label: l("Name"), fieldName: "Name", sortable: true },
      { label: l("Status__c"), fieldName: "Status__c", sortable: true },
      { label: l("Origin__c"), fieldName: "Origin__c", sortable: true },
      {
        label: l("Destination__c"),
        fieldName: "Destination__c",
        sortable: true
      },
      { label: l("Vehicle__c"), fieldName: "vehicleNumber", sortable: true },
      { label: l("Latest_Location__c"), fieldName: "Latest_Location__c" },
      {
        label: l("Latest_Tracking_Timestamp__c"),
        fieldName: "Latest_Tracking_Timestamp__c",
        type: "date",
        sortable: true,
        typeAttributes: {
          day: "2-digit",
          month: "short",
          hour: "2-digit",
          minute: "2-digit"
        }
      }
    ];
  }

  get selectedShipment() {
    return this.shipments.find((s) => s.Id === this.selectedId);
  }

  get hasSelection() {
    return !!this.selectedShipment;
  }

  get isSaveDisabled() {
    return this.isSaving || !this.form.eventType;
  }

  handleRowSelection(event) {
    const rows = event.detail.selectedRows || [];
    this.selectedId = rows.length ? rows[0].Id : undefined;
    this.form = {};
  }

  handleField(event) {
    const name = event.target.dataset.field;
    const value = event.detail.value;
    this.form = { ...this.form, [name]: value === "" ? null : value };
  }

  async handleSave() {
    const inputs = [...this.template.querySelectorAll(".elogix-event-field")];
    if (!inputs.every((input) => input.reportValidity())) {
      return;
    }
    this.isSaving = true;
    try {
      const result = await recordEvent({
        request: {
          shipmentId: this.selectedId,
          eventType: this.form.eventType,
          location: this.form.location || null,
          remarks: this.form.remarks || null,
          eventTimestamp: this.form.eventTimestamp || null
        }
      });
      if (handleServiceResult(this, result, LABEL_RECORDED)) {
        this.form = {};
        // The shipment summary changed in Apex: let LDS (and the embedded timeline) reload it.
        await notifyRecordUpdateAvailable([{ recordId: this.selectedId }]);
        await this.handleRefresh();
      }
    } catch (error) {
      showError(this, error);
    } finally {
      this.isSaving = false;
    }
  }

  handleRefresh() {
    if (!this._wired) {
      return Promise.resolve();
    }
    return refreshApex(this._wired);
  }
}
