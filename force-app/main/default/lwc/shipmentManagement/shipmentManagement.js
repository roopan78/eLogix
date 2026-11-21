import { LightningElement, wire } from "lwc";
import { NavigationMixin } from "lightning/navigation";
import { refreshApex } from "@salesforce/apex";
import { getObjectInfo, getPicklistValues } from "lightning/uiObjectInfoApi";
import SHIPMENT_OBJECT from "@salesforce/schema/Shipment__c";
import STATUS_FIELD from "@salesforce/schema/Shipment__c.Status__c";
import getShipments from "@salesforce/apex/ShipmentConsoleController.getShipments";
import LABEL_SHIPMENTS from "@salesforce/label/c.eLogix_UI_Shipments";
import LABEL_STATUS from "@salesforce/label/c.eLogix_UI_Status";
import LABEL_ALL_STATUSES from "@salesforce/label/c.eLogix_UI_All_Statuses";
import LABEL_SEARCH from "@salesforce/label/c.eLogix_UI_Search_Shipments";
import LABEL_SEARCH_PLACEHOLDER from "@salesforce/label/c.eLogix_UI_Search_Placeholder";
import LABEL_REFRESH from "@salesforce/label/c.eLogix_UI_Refresh";
import LABEL_VIEW from "@salesforce/label/c.eLogix_UI_View";
import LABEL_NO_SHIPMENTS from "@salesforce/label/c.eLogix_UI_No_Shipments";

const SEARCH_DELAY_MS = 300;
const MAX_ROWS = 200;

/**
 * Shipment list for the eLogix app: status filter, search, refresh and a link to each record.
 * Reads through ShipmentConsoleController.getShipments (user mode, so sharing and FLS apply).
 * Status changes happen on the record page (shipmentDetails), where the policy offers the options.
 */
export default class ShipmentManagement extends NavigationMixin(
  LightningElement
) {
  labels = {
    title: LABEL_SHIPMENTS,
    status: LABEL_STATUS,
    allStatuses: LABEL_ALL_STATUSES,
    search: LABEL_SEARCH,
    searchPlaceholder: LABEL_SEARCH_PLACEHOLDER,
    refresh: LABEL_REFRESH,
    noShipments: LABEL_NO_SHIPMENTS
  };

  status = "";
  searchTerm = "";
  records = [];
  error;
  isLoading = true;
  fieldLabels = {};
  statusValues = [];

  _recordTypeId;
  _wiredResult;
  _searchTimer;

  @wire(getObjectInfo, { objectApiName: SHIPMENT_OBJECT })
  wiredObjectInfo({ data }) {
    if (data) {
      this.fieldLabels = Object.fromEntries(
        Object.entries(data.fields).map(([name, field]) => [name, field.label])
      );
      this._recordTypeId = data.defaultRecordTypeId;
    }
  }

  @wire(getPicklistValues, {
    recordTypeId: "$_recordTypeId",
    fieldApiName: STATUS_FIELD
  })
  wiredStatuses({ data }) {
    if (data) {
      this.statusValues = data.values.map((entry) => ({
        label: entry.label,
        value: entry.value
      }));
    }
  }

  @wire(getShipments, {
    status: "$status",
    searchTerm: "$searchTerm",
    maxRows: MAX_ROWS
  })
  wiredShipments(result) {
    this._wiredResult = result;
    const { data, error } = result;
    if (data) {
      this.records = data.map((row) => ({
        Id: row.Id,
        Name: row.Name,
        recordUrl: `/lightning/r/Shipment__c/${row.Id}/view`,
        customerName: row.Customer__r ? row.Customer__r.Name : null,
        Origin__c: row.Origin__c,
        Destination__c: row.Destination__c,
        Status__c: row.Status__c,
        Priority__c: row.Priority__c,
        Pickup_Date__c: row.Pickup_Date__c,
        Expected_Delivery_Date__c: row.Expected_Delivery_Date__c,
        vehicleNumber: row.Vehicle__r ? row.Vehicle__r.Vehicle_Number__c : null,
        Latest_Location__c: row.Latest_Location__c
      }));
      this.error = undefined;
      this.isLoading = false;
    } else if (error) {
      this.records = [];
      this.error = error;
      this.isLoading = false;
    }
  }

  get statusOptions() {
    return [
      { label: this.labels.allStatuses, value: "" },
      ...this.statusValues
    ];
  }

  get columns() {
    const label = (field, fallback) => this.fieldLabels[field] || fallback;
    return [
      {
        label: label("Name", "Shipment"),
        fieldName: "recordUrl",
        type: "url",
        sortable: true,
        typeAttributes: { label: { fieldName: "Name" }, target: "_self" }
      },
      {
        label: label("Customer__c", "Customer"),
        fieldName: "customerName",
        sortable: true
      },
      {
        label: label("Origin__c", "Origin"),
        fieldName: "Origin__c",
        sortable: true
      },
      {
        label: label("Destination__c", "Destination"),
        fieldName: "Destination__c",
        sortable: true
      },
      {
        label: label("Status__c", "Status"),
        fieldName: "Status__c",
        sortable: true
      },
      {
        label: label("Priority__c", "Priority"),
        fieldName: "Priority__c",
        sortable: true
      },
      {
        label: label("Pickup_Date__c", "Pickup Date"),
        fieldName: "Pickup_Date__c",
        type: "date-local",
        sortable: true
      },
      {
        label: label("Vehicle__c", "Vehicle"),
        fieldName: "vehicleNumber",
        sortable: true
      },
      {
        label: label("Latest_Location__c", "Latest Location"),
        fieldName: "Latest_Location__c"
      },
      {
        type: "action",
        typeAttributes: { rowActions: [{ label: LABEL_VIEW, name: "view" }] }
      }
    ];
  }

  handleStatusChange(event) {
    this.isLoading = true;
    this.status = event.detail.value;
  }

  handleSearchChange(event) {
    const value = event.detail.value || "";
    clearTimeout(this._searchTimer);
    // eslint-disable-next-line @lwc/lwc/no-async-operation
    this._searchTimer = setTimeout(() => {
      if (value.trim() !== this.searchTerm) {
        this.isLoading = true;
        this.searchTerm = value.trim();
      }
    }, SEARCH_DELAY_MS);
  }

  handleRefresh() {
    this.isLoading = true;
    return refreshApex(this._wiredResult).finally(() => {
      this.isLoading = false;
    });
  }

  handleRowAction(event) {
    const { action, row } = event.detail;
    if (action.name === "view") {
      this[NavigationMixin.Navigate]({
        type: "standard__recordPage",
        attributes: {
          recordId: row.Id,
          objectApiName: "Shipment__c",
          actionName: "view"
        }
      });
    }
  }

  disconnectedCallback() {
    clearTimeout(this._searchTimer);
  }
}
