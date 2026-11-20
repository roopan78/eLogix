import { createElement } from "lwc";
import FleetManagement from "c/fleetManagement";
import getFleetOverview from "@salesforce/apex/FleetConsoleController.getFleetOverview";
import { getObjectInfo } from "lightning/uiObjectInfoApi";
import { refreshApex } from "@salesforce/apex";
import { navigate } from "lightning/navigation";

jest.mock(
  "@salesforce/apex/FleetConsoleController.getFleetOverview",
  () => {
    const { createApexTestWireAdapter } = require("@salesforce/sfdx-lwc-jest");
    return { default: createApexTestWireAdapter(jest.fn()) };
  },
  { virtual: true }
);
jest.mock(
  "@salesforce/apex",
  () => ({ refreshApex: jest.fn(() => Promise.resolve()) }),
  { virtual: true }
);
jest.mock("lightning/navigation", () => {
  const Navigate = Symbol("Navigate");
  const mockNavigate = jest.fn();
  const NavigationMixin = (Base) =>
    class extends Base {
      [Navigate](pageReference) {
        mockNavigate(pageReference);
      }
    };
  NavigationMixin.Navigate = Navigate;
  return { NavigationMixin, navigate: mockNavigate };
});

const OVERVIEW = {
  vehicles: [
    {
      Id: "a0X1",
      Vehicle_Number__c: "TN01AB1234",
      Status__c: "Available",
      Business_Unit__r: { Name: "South" }
    },
    {
      Id: "a0X2",
      Vehicle_Number__c: "TN02CD5678",
      Status__c: "Under Maintenance"
    }
  ],
  drivers: [{ Id: "a0D1", Name: "Ravi Kumar", Status__c: "Available" }]
};

// eslint-disable-next-line @lwc/lwc/no-async-operation
const flushPromises = () => new Promise((resolve) => setTimeout(resolve, 0));

function create() {
  const element = createElement("c-fleet-management", { is: FleetManagement });
  document.body.appendChild(element);
  return element;
}

const vehicles = (element) =>
  element.shadowRoot.querySelector("c-reusable-data-table.elogix-vehicles");
const drivers = (element) =>
  element.shadowRoot.querySelector("c-reusable-data-table.elogix-drivers");

describe("c-fleet-management", () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it("starts loading, then shows vehicles and drivers with counts", async () => {
    const element = create();
    expect(vehicles(element).isLoading).toBe(true);
    getFleetOverview.emit(OVERVIEW);
    await flushPromises();

    expect(vehicles(element).isLoading).toBe(false);
    expect(vehicles(element).records).toHaveLength(2);
    expect(vehicles(element).records[0].businessUnit).toBe("South");
    expect(vehicles(element).records[1].businessUnit).toBeNull();
    expect(drivers(element).records).toHaveLength(1);
    const tabs = element.shadowRoot.querySelectorAll("lightning-tab");
    expect(tabs[0].label).toBe("c.eLogix_UI_Vehicles (2)");
    expect(tabs[1].label).toBe("c.eLogix_UI_Drivers (1)");
  });

  it("uses the objects' field labels for the columns", async () => {
    const element = create();
    getObjectInfo.emit({ fields: { Status__c: { label: "Fleet Status" } } });
    await flushPromises();
    expect(
      vehicles(element).columns.find((c) => c.fieldName === "Status__c").label
    ).toBe("Fleet Status");
  });

  it("passes load errors to both tables", async () => {
    const element = create();
    getFleetOverview.error({ message: "No access" });
    await flushPromises();
    expect(vehicles(element).error).toBeTruthy();
    expect(drivers(element).error).toBeTruthy();
  });

  it("opens vehicles and drivers, and refreshes", async () => {
    const element = create();
    getFleetOverview.emit(OVERVIEW);
    await flushPromises();
    vehicles(element).dispatchEvent(
      new CustomEvent("rowaction", {
        detail: { action: { name: "view" }, row: { Id: "a0X1" } }
      })
    );
    drivers(element).dispatchEvent(
      new CustomEvent("rowaction", {
        detail: { action: { name: "view" }, row: { Id: "a0D1" } }
      })
    );
    expect(
      navigate.mock.calls.map((call) => call[0].attributes.objectApiName)
    ).toEqual(["Vehicle__c", "Driver__c"]);

    element.shadowRoot.querySelector("lightning-button-icon").click();
    await flushPromises();
    expect(refreshApex).toHaveBeenCalledTimes(1);
  });
});
