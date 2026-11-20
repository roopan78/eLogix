import { createElement } from "lwc";
import ShipmentTimeline from "c/shipmentTimeline";
import getTimeline from "@salesforce/apex/TrackingConsoleController.getTimeline";
import { refreshApex } from "@salesforce/apex";
import { getRecord } from "lightning/uiRecordApi";

jest.mock(
  "@salesforce/apex/TrackingConsoleController.getTimeline",
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

const SHIPMENT_ID = "a0B000000000001AAA";
const EVENTS = [
  {
    Id: "a0E000000000002AAA",
    Event_Type__c: "Location Update",
    Event_Timestamp__c: "2026-11-20T10:15:00.000Z",
    Location__c: "Krishnagiri",
    Source__c: "GPS Integration"
  },
  {
    Id: "a0E000000000001AAA",
    Event_Type__c: "Status Change",
    Event_Timestamp__c: "2026-11-20T09:00:00.000Z",
    From_Status__c: "Dispatched",
    To_Status__c: "In Transit",
    Remarks__c: "Left the Chennai hub.",
    Source__c: "Apex Service"
  }
];

// Lets pending promises and wire deliveries settle (test helper; the LWC timer rule targets components).
// eslint-disable-next-line @lwc/lwc/no-async-operation
const flushPromises = () => new Promise((resolve) => setTimeout(resolve, 0));

function create() {
  const element = createElement("c-shipment-timeline", {
    is: ShipmentTimeline
  });
  element.recordId = SHIPMENT_ID;
  document.body.appendChild(element);
  return element;
}

function shipment(status, trackedAt) {
  return {
    fields: {
      Status__c: { value: status },
      Latest_Tracking_Timestamp__c: { value: trackedAt }
    }
  };
}

describe("c-shipment-timeline", () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it("loads the shipment's history", async () => {
    const element = create();
    expect(
      element.shadowRoot.querySelector("c-loading-indicator")
    ).not.toBeNull();
    await flushPromises(); // the wire receives its config after a microtask
    expect(getTimeline.getLastConfig()).toEqual({ shipmentId: SHIPMENT_ID });
  });

  it("renders each event, with status badges for status changes", async () => {
    const element = create();
    getTimeline.emit(EVENTS);
    await flushPromises();

    const items = element.shadowRoot.querySelectorAll("li.elogix-event");
    expect(items).toHaveLength(2);
    expect(items[0].querySelector(".elogix-event-type").textContent).toBe(
      "Location Update"
    );
    expect(items[0].querySelector(".elogix-location").textContent).toBe(
      "Krishnagiri"
    );
    expect(items[0].querySelector(".elogix-transition")).toBeNull();

    const badges = items[1].querySelectorAll("c-status-badge");
    expect(Array.from(badges).map((badge) => badge.status)).toEqual([
      "Dispatched",
      "In Transit"
    ]);
    expect(items[1].querySelector("lightning-formatted-date-time").value).toBe(
      "2026-11-20T09:00:00.000Z"
    );
  });

  it("shows the empty state", async () => {
    const element = create();
    getTimeline.emit([]);
    await flushPromises();
    expect(element.shadowRoot.querySelector(".elogix-empty").textContent).toBe(
      "c.eLogix_UI_No_Tracking_Events"
    );
  });

  it("shows load errors", async () => {
    const element = create();
    getTimeline.error({ message: "Insufficient access" });
    await flushPromises();
    expect(element.shadowRoot.querySelector(".elogix-error")).not.toBeNull();
    expect(element.shadowRoot.querySelector("li")).toBeNull();
  });

  it("refreshes from the header button", async () => {
    const element = create();
    getTimeline.emit(EVENTS);
    await flushPromises();
    element.shadowRoot.querySelector("lightning-button-icon").click();
    await flushPromises();
    expect(refreshApex).toHaveBeenCalledTimes(1);
  });

  it("refreshes when the shipment's status or tracking time changes, not on first load", async () => {
    create();
    getTimeline.emit(EVENTS);
    getRecord.emit(shipment("In Transit", "2026-11-20T10:15:00.000Z"));
    await flushPromises();
    expect(refreshApex).not.toHaveBeenCalled();

    getRecord.emit(shipment("In Transit", "2026-11-20T10:15:00.000Z"));
    await flushPromises();
    expect(refreshApex).not.toHaveBeenCalled();

    getRecord.emit(shipment("Delayed", "2026-11-20T10:15:00.000Z"));
    await flushPromises();
    expect(refreshApex).toHaveBeenCalledTimes(1);
  });
});
