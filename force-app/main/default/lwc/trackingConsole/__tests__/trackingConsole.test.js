import { createElement } from "lwc";
import TrackingConsole from "c/trackingConsole";
import getActiveShipments from "@salesforce/apex/TrackingConsoleController.getActiveShipments";
import recordEvent from "@salesforce/apex/TrackingConsoleController.recordEvent";
import { getPicklistValues } from "lightning/uiObjectInfoApi";
import { notifyRecordUpdateAvailable } from "lightning/uiRecordApi";
import { refreshApex } from "@salesforce/apex";

jest.mock(
  "@salesforce/apex/TrackingConsoleController.getActiveShipments",
  () => {
    const { createApexTestWireAdapter } = require("@salesforce/sfdx-lwc-jest");
    return { default: createApexTestWireAdapter(jest.fn()) };
  },
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/TrackingConsoleController.getTimeline",
  () => {
    const { createApexTestWireAdapter } = require("@salesforce/sfdx-lwc-jest");
    return { default: createApexTestWireAdapter(jest.fn()) };
  },
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/TrackingConsoleController.recordEvent",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex",
  () => ({ refreshApex: jest.fn(() => Promise.resolve()) }),
  { virtual: true }
);

const SHIPMENTS = [
  {
    Id: "a0B000000000001AAA",
    Name: "SHP-00001",
    Status__c: "In Transit",
    Vehicle__r: { Vehicle_Number__c: "TN01AB1234" },
    Driver__r: { Name: "Ravi Kumar" }
  }
];

// eslint-disable-next-line @lwc/lwc/no-async-operation
const flushPromises = () => new Promise((resolve) => setTimeout(resolve, 0));

async function createWithSelection() {
  const element = createElement("c-tracking-console", { is: TrackingConsole });
  document.body.appendChild(element);
  getActiveShipments.emit(SHIPMENTS);
  getPicklistValues.emit({
    values: [{ label: "Hub Arrival", value: "Hub Arrival" }]
  });
  await flushPromises();
  element.shadowRoot.querySelector("c-reusable-data-table").dispatchEvent(
    new CustomEvent("rowselection", {
      detail: { selectedRows: [SHIPMENTS[0]] }
    })
  );
  await flushPromises();
  return element;
}

function q(element, selector) {
  return element.shadowRoot.querySelector(selector);
}

function field(element, name) {
  return q(element, `[data-field="${name}"]`);
}

async function setField(element, name, value) {
  field(element, name).dispatchEvent(
    new CustomEvent("change", { detail: { value } })
  );
  await flushPromises();
}

describe("c-tracking-console", () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it("lists the shipments on the road and asks to select one", async () => {
    const element = createElement("c-tracking-console", {
      is: TrackingConsole
    });
    document.body.appendChild(element);
    getActiveShipments.emit(SHIPMENTS);
    await flushPromises();
    const table = q(element, "c-reusable-data-table");
    expect(table.records[0]).toMatchObject({
      vehicleNumber: "TN01AB1234",
      driverName: "Ravi Kumar"
    });
    expect(q(element, ".elogix-select-hint")).not.toBeNull();
    expect(q(element, "c-shipment-timeline")).toBeNull();
  });

  it("shows the selected shipment's timeline and the event form", async () => {
    const element = await createWithSelection();
    expect(q(element, "c-shipment-timeline").recordId).toBe(
      "a0B000000000001AAA"
    );
    expect(field(element, "eventType").options).toEqual([
      { label: "Hub Arrival", value: "Hub Arrival" }
    ]);
    expect(q(element, "lightning-button.elogix-save").disabled).toBe(true);
  });

  it("records a manual event through the controller and refreshes", async () => {
    recordEvent.mockResolvedValue({
      isSuccess: true,
      errors: [],
      recordIds: ["a0E1"]
    });
    const element = await createWithSelection();
    const toast = jest.fn();
    element.addEventListener("lightning__showtoast", toast);
    await setField(element, "eventType", "Hub Arrival");
    await setField(element, "location", "Hosur hub");
    element.shadowRoot
      .querySelectorAll(".elogix-event-field")
      .forEach((input) => {
        input.reportValidity = jest.fn(() => true);
      });
    q(element, "lightning-button.elogix-save").click();
    await flushPromises();

    expect(recordEvent).toHaveBeenCalledWith({
      request: {
        shipmentId: "a0B000000000001AAA",
        eventType: "Hub Arrival",
        location: "Hosur hub",
        remarks: null,
        eventTimestamp: null
      }
    });
    expect(toast.mock.calls[0][0].detail.variant).toBe("success");
    expect(notifyRecordUpdateAvailable).toHaveBeenCalledWith([
      { recordId: "a0B000000000001AAA" }
    ]);
    expect(refreshApex).toHaveBeenCalled();
    expect(field(element, "location").value).toBeUndefined();
  });

  it("does not submit an invalid form, and shows the service's refusal", async () => {
    recordEvent.mockResolvedValue({
      isSuccess: false,
      errors: [
        { code: "STATUS_EVENT_NOT_ALLOWED", message: "Use a status change." }
      ]
    });
    const element = await createWithSelection();
    await setField(element, "eventType", "Hub Arrival");
    const inputs = element.shadowRoot.querySelectorAll(".elogix-event-field");
    inputs.forEach((input) => {
      input.reportValidity = jest.fn(() => false);
    });
    q(element, "lightning-button.elogix-save").click();
    await flushPromises();
    expect(recordEvent).not.toHaveBeenCalled();

    inputs.forEach((input) => {
      input.reportValidity = jest.fn(() => true);
    });
    const toast = jest.fn();
    element.addEventListener("lightning__showtoast", toast);
    q(element, "lightning-button.elogix-save").click();
    await flushPromises();
    expect(toast.mock.calls[0][0].detail).toMatchObject({
      variant: "error",
      message: "Use a status change."
    });
    expect(notifyRecordUpdateAvailable).not.toHaveBeenCalled();
  });
});
