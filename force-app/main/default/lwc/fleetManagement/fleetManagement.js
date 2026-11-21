import { LightningElement, wire } from "lwc";
import { NavigationMixin } from "lightning/navigation";
import { refreshApex } from "@salesforce/apex";
import { getObjectInfo } from "lightning/uiObjectInfoApi";
import VEHICLE_OBJECT from "@salesforce/schema/Vehicle__c";
import DRIVER_OBJECT from "@salesforce/schema/Driver__c";
import getFleetOverview from "@salesforce/apex/FleetConsoleController.getFleetOverview";
import LABEL_TITLE from "@salesforce/label/c.eLogix_UI_Fleet";
import LABEL_VEHICLES from "@salesforce/label/c.eLogix_UI_Vehicles";
import LABEL_DRIVERS from "@salesforce/label/c.eLogix_UI_Drivers";
import LABEL_NO_VEHICLES from "@salesforce/label/c.eLogix_UI_No_Vehicles";
import LABEL_NO_DRIVERS from "@salesforce/label/c.eLogix_UI_No_Drivers";
import LABEL_REFRESH from "@salesforce/label/c.eLogix_UI_Refresh";
import LABEL_VIEW from "@salesforce/label/c.eLogix_UI_View";

const VIEW_ACTION = {
  type: "action",
  typeAttributes: { rowActions: [{ label: LABEL_VIEW, name: "view" }] }
};

function fieldLabels(objectInfo) {
  return Object.fromEntries(
    Object.entries(objectInfo.fields).map(([name, field]) => [
      name,
      field.label
    ])
  );
}

/**
 * Fleet board: vehicles and drivers the user can see, with status, documents and whether each is
 * allocatable today (the indicative Is_Allocatable__c formulas). Read-only; allocation happens on the
 * shipment (vehicleAllocation). Reads through FleetConsoleController.getFleetOverview (user mode).
 */
export default class FleetManagement extends NavigationMixin(LightningElement) {
  labels = {
    title: LABEL_TITLE,
    vehicles: LABEL_VEHICLES,
    drivers: LABEL_DRIVERS,
    noVehicles: LABEL_NO_VEHICLES,
    noDrivers: LABEL_NO_DRIVERS,
    refresh: LABEL_REFRESH
  };

  vehicles = [];
  drivers = [];
  error;
  isLoading = true;
  _wired;

  vehicleLabels = {};
  driverLabels = {};

  @wire(getObjectInfo, { objectApiName: VEHICLE_OBJECT })
  wiredVehicleInfo({ data }) {
    if (data) {
      this.vehicleLabels = fieldLabels(data);
    }
  }

  @wire(getObjectInfo, { objectApiName: DRIVER_OBJECT })
  wiredDriverInfo({ data }) {
    if (data) {
      this.driverLabels = fieldLabels(data);
    }
  }

  /** Column headers are the fields' own (translated) labels. */
  get vehicleColumns() {
    const l = (field) => this.vehicleLabels[field] || field;
    return [
      {
        label: l("Vehicle_Number__c"),
        fieldName: "Vehicle_Number__c",
        sortable: true
      },
      {
        label: l("Vehicle_Type__c"),
        fieldName: "Vehicle_Type__c",
        sortable: true
      },
      {
        label: l("Capacity__c"),
        fieldName: "Capacity__c",
        type: "number",
        sortable: true
      },
      { label: l("Status__c"), fieldName: "Status__c", sortable: true },
      {
        label: l("Is_Allocatable__c"),
        fieldName: "Is_Allocatable__c",
        type: "boolean",
        sortable: true
      },
      {
        label: l("Registration_Expiry__c"),
        fieldName: "Registration_Expiry__c",
        type: "date-local",
        sortable: true
      },
      {
        label: l("Insurance_Expiry__c"),
        fieldName: "Insurance_Expiry__c",
        type: "date-local",
        sortable: true
      },
      {
        label: l("Business_Unit__c"),
        fieldName: "businessUnit",
        sortable: true
      },
      VIEW_ACTION
    ];
  }

  get driverColumns() {
    const l = (field) => this.driverLabels[field] || field;
    return [
      { label: l("Name"), fieldName: "Name", sortable: true },
      {
        label: l("License_Number__c"),
        fieldName: "License_Number__c",
        sortable: true
      },
      {
        label: l("License_Expiry__c"),
        fieldName: "License_Expiry__c",
        type: "date-local",
        sortable: true
      },
      { label: l("Status__c"), fieldName: "Status__c", sortable: true },
      {
        label: l("Is_Allocatable__c"),
        fieldName: "Is_Allocatable__c",
        type: "boolean",
        sortable: true
      },
      { label: l("Phone__c"), fieldName: "Phone__c", type: "phone" },
      {
        label: l("Business_Unit__c"),
        fieldName: "businessUnit",
        sortable: true
      },
      VIEW_ACTION
    ];
  }

  @wire(getFleetOverview)
  wiredOverview(result) {
    this._wired = result;
    if (result.data) {
      const withUnit = (row) => ({
        ...row,
        businessUnit: row.Business_Unit__r ? row.Business_Unit__r.Name : null
      });
      this.vehicles = (result.data.vehicles || []).map(withUnit);
      this.drivers = (result.data.drivers || []).map(withUnit);
      this.error = undefined;
      this.isLoading = false;
    } else if (result.error) {
      this.vehicles = [];
      this.drivers = [];
      this.error = result.error;
      this.isLoading = false;
    }
  }

  get vehicleTabLabel() {
    return `${this.labels.vehicles} (${this.vehicles.length})`;
  }

  get driverTabLabel() {
    return `${this.labels.drivers} (${this.drivers.length})`;
  }

  handleRefresh() {
    this.isLoading = true;
    return refreshApex(this._wired).finally(() => {
      this.isLoading = false;
    });
  }

  handleVehicleAction(event) {
    this.open(event.detail.row.Id, "Vehicle__c");
  }

  handleDriverAction(event) {
    this.open(event.detail.row.Id, "Driver__c");
  }

  open(recordId, objectApiName) {
    this[NavigationMixin.Navigate]({
      type: "standard__recordPage",
      attributes: { recordId, objectApiName, actionName: "view" }
    });
  }
}
