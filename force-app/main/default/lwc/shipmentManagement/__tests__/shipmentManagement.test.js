import { createElement } from "lwc";
import ShipmentManagement from "c/shipmentManagement";
import getShipments from "@salesforce/apex/ShipmentConsoleController.getShipments";
import { refreshApex } from "@salesforce/apex";
import { getObjectInfo, getPicklistValues } from "lightning/uiObjectInfoApi";
import { navigate } from "lightning/navigation";

jest.mock(
  "@salesforce/apex/ShipmentConsoleController.getShipments",
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

const SHIPMENTS = [
  {
    Id: "a0B000000000001AAA",
    Name: "SHP-00001",
    Customer__r: { Name: "Chennai Traders" },
    Origin__c: "Chennai",
    Destination__c: "Bangalore",
    Status__c: "In Transit",
    Vehicle__r: { Vehicle_Number__c: "TN01AB1234" }
  },
  {
    Id: "a0B000000000002AAA",
    Name: "SHP-00002",
    Origin__c: "Madurai",
    Destination__c: "Coimbatore",
    Status__c: "Confirmed"
  }
];

// Lets pending promises and wire deliveries settle (test helper; the LWC timer rule targets components).
// eslint-disable-next-line @lwc/lwc/no-async-operation
const flushPromises = () => new Promise((resolve) => setTimeout(resolve, 0));

function create() {
  const element = createElement("c-shipment-management", {
    is: ShipmentManagement
  });
  document.body.appendChild(element);
  return element;
}

function table(element) {
  return element.shadowRoot.querySelector("c-reusable-data-table");
}

describe("c-shipment-management", () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
    jest.useRealTimers();
  });

  it("loads with the table in its loading state and no filters", async () => {
    const element = create();
    await flushPromises(); // the wire receives its config after a microtask
    expect(table(element).isLoading).toBe(true);
    expect(getShipments.getLastConfig()).toEqual({
      status: "",
      searchTerm: "",
      maxRows: 200
    });
  });

  it("shows the shipments, flattened for the table", async () => {
    const element = create();
    getShipments.emit(SHIPMENTS);
    await flushPromises();

    const rows = table(element).records;
    expect(table(element).isLoading).toBe(false);
    expect(rows).toHaveLength(2);
    expect(rows[0]).toMatchObject({
      Name: "SHP-00001",
      customerName: "Chennai Traders",
      vehicleNumber: "TN01AB1234",
      recordUrl: "/lightning/r/Shipment__c/a0B000000000001AAA/view"
    });
    expect(rows[1].customerName).toBeNull();
    expect(table(element).emptyMessage).toBe("c.eLogix_UI_No_Shipments");
  });

  it("passes load errors to the table", async () => {
    const element = create();
    getShipments.error({ message: "No access" });
    await flushPromises();
    expect(table(element).error).toBeTruthy();
    expect(table(element).records).toEqual([]);
    expect(table(element).isLoading).toBe(false);
  });

  it("uses the object's field labels for the columns", async () => {
    const element = create();
    getObjectInfo.emit({
      defaultRecordTypeId: "012000000000000AAA",
      fields: {
        Name: { label: "Shipment Name" },
        Status__c: { label: "Shipment Status" }
      }
    });
    await flushPromises();
    const columns = table(element).columns;
    expect(columns[0].label).toBe("Shipment Name");
    expect(columns.find((c) => c.fieldName === "Status__c").label).toBe(
      "Shipment Status"
    );
  });

  it("filters by status from the picklist values", async () => {
    const element = create();
    getPicklistValues.emit({
      values: [{ label: "In Transit", value: "In Transit" }]
    });
    await flushPromises();
    const combobox = element.shadowRoot.querySelector(
      "lightning-combobox.elogix-status-filter"
    );
    expect(combobox.options).toEqual([
      { label: "c.eLogix_UI_All_Statuses", value: "" },
      { label: "In Transit", value: "In Transit" }
    ]);

    combobox.dispatchEvent(
      new CustomEvent("change", { detail: { value: "In Transit" } })
    );
    await flushPromises();
    expect(getShipments.getLastConfig().status).toBe("In Transit");
  });

  it("debounces the search and trims it", async () => {
    jest.useFakeTimers();
    const element = create();
    await Promise.resolve();
    const search = element.shadowRoot.querySelector(
      "lightning-input.elogix-search"
    );
    search.dispatchEvent(
      new CustomEvent("change", { detail: { value: " Chen" } })
    );
    search.dispatchEvent(
      new CustomEvent("change", { detail: { value: " Chennai " } })
    );
    jest.advanceTimersByTime(299);
    expect(getShipments.getLastConfig().searchTerm).toBe("");
    jest.advanceTimersByTime(1);
    await Promise.resolve();
    expect(getShipments.getLastConfig().searchTerm).toBe("Chennai");
  });

  it("refreshes from the header button and the table's retry", async () => {
    const element = create();
    element.shadowRoot.querySelector("lightning-button-icon").click();
    table(element).dispatchEvent(new CustomEvent("retry"));
    await flushPromises();
    expect(refreshApex).toHaveBeenCalledTimes(2);
  });

  it("opens the shipment from the View row action", () => {
    const element = create();
    table(element).dispatchEvent(
      new CustomEvent("rowaction", {
        detail: { action: { name: "view" }, row: { Id: "a0B000000000001AAA" } }
      })
    );
    expect(navigate).toHaveBeenCalledWith({
      type: "standard__recordPage",
      attributes: {
        recordId: "a0B000000000001AAA",
        objectApiName: "Shipment__c",
        actionName: "view"
      }
    });
  });
});
