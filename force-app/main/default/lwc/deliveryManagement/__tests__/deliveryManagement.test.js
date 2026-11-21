import { createElement } from "lwc";
import DeliveryManagement from "c/deliveryManagement";
import { getRecord, notifyRecordUpdateAvailable } from "lightning/uiRecordApi";
import { getObjectInfo, getPicklistValues } from "lightning/uiObjectInfoApi";
import getDeliveryState from "@salesforce/apex/DeliveryConsoleController.getDeliveryState";
import startAttempt from "@salesforce/apex/DeliveryConsoleController.startAttempt";
import recordProof from "@salesforce/apex/DeliveryConsoleController.recordProof";
import confirmDelivery from "@salesforce/apex/DeliveryConsoleController.confirmDelivery";
import recordFailure from "@salesforce/apex/DeliveryConsoleController.recordFailure";
import verifyProof from "@salesforce/apex/DeliveryConsoleController.verifyProof";
import ConfirmationDialog from "c/confirmationDialog";

jest.mock(
  "@salesforce/apex/DeliveryConsoleController.getDeliveryState",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/DeliveryConsoleController.startAttempt",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/DeliveryConsoleController.recordProof",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/DeliveryConsoleController.confirmDelivery",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/DeliveryConsoleController.recordFailure",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/DeliveryConsoleController.verifyProof",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock("c/confirmationDialog", () => ({
  __esModule: true,
  default: { open: jest.fn() }
}));

const SHIPMENT_ID = "a0B000000000001AAA";
const OK = { isSuccess: true, errors: [], recordIds: ["a0P1"] };
const OPEN = {
  Id: "a0L1",
  Attempt_Number__c: 1,
  Delivery_Status__c: "Out for Delivery"
};
const PROOF = {
  Id: "a0P1",
  Delivery__c: "a0L1",
  Receiver_Name__c: "Ms Lakshmi"
};

// eslint-disable-next-line @lwc/lwc/no-async-operation
const flushPromises = () => new Promise((resolve) => setTimeout(resolve, 0));

async function create(status, state) {
  getDeliveryState.mockResolvedValue(state);
  const element = createElement("c-delivery-management", {
    is: DeliveryManagement
  });
  element.recordId = SHIPMENT_ID;
  document.body.appendChild(element);
  getRecord.emit({
    fields: { Name: { value: "SHP-00001" }, Status__c: { value: status } }
  });
  await flushPromises();
  return element;
}

function q(element, selector) {
  return element.shadowRoot.querySelector(selector);
}

describe("c-delivery-management", () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it("starts an attempt for an In Transit shipment and reloads", async () => {
    startAttempt.mockResolvedValue(OK);
    const element = await create("In Transit", { attempts: [], proofs: [] });
    expect(getDeliveryState).toHaveBeenCalledWith({ shipmentId: SHIPMENT_ID });
    expect(q(element, "c-reusable-data-table").records).toEqual([]);
    q(element, "lightning-button.elogix-start").click();
    await flushPromises();
    expect(startAttempt).toHaveBeenCalledWith({ shipmentId: SHIPMENT_ID });
    expect(notifyRecordUpdateAvailable).toHaveBeenCalledWith([
      { recordId: SHIPMENT_ID }
    ]);
    expect(getDeliveryState).toHaveBeenCalledTimes(2);
  });

  it("offers no start before dispatch", async () => {
    const element = await create("Confirmed", { attempts: [], proofs: [] });
    expect(q(element, "lightning-button.elogix-start")).toBeNull();
  });

  it("records the proof of delivery for the open attempt", async () => {
    recordProof.mockResolvedValue(OK);
    const element = await create("Out for Delivery", {
      attempts: [OPEN],
      proofs: []
    });
    expect(q(element, "lightning-button.elogix-start")).toBeNull();
    q(element, "lightning-button.elogix-show-proof").click();
    await flushPromises();

    q(element, '[data-field="receiverName"]').dispatchEvent(
      new CustomEvent("change", { detail: { value: "Ms Lakshmi" } })
    );
    element.shadowRoot
      .querySelectorAll(".elogix-proof-field")
      .forEach((input) => {
        input.reportValidity = jest.fn(() => true);
      });
    await flushPromises();
    q(element, "lightning-button.elogix-save-proof").click();
    await flushPromises();

    expect(recordProof).toHaveBeenCalledWith({
      request: expect.objectContaining({
        shipmentId: SHIPMENT_ID,
        receiverName: "Ms Lakshmi",
        hasException: false
      })
    });
    expect(q(element, ".elogix-proof-form")).toBeNull();
  });

  it("uploads evidence to the proof and confirms the delivery", async () => {
    ConfirmationDialog.open.mockResolvedValue({ confirmed: true });
    confirmDelivery.mockResolvedValue(OK);
    const element = await create("Out for Delivery", {
      attempts: [OPEN],
      proofs: [PROOF]
    });
    expect(q(element, "lightning-file-upload").recordId).toBe("a0P1");
    q(element, "lightning-button.elogix-confirm").click();
    await flushPromises();
    expect(confirmDelivery).toHaveBeenCalledWith({ shipmentId: SHIPMENT_ID });
  });

  it("records a failed attempt with its reason", async () => {
    recordFailure.mockResolvedValue(OK);
    const element = await create("Out for Delivery", {
      attempts: [OPEN],
      proofs: []
    });
    getPicklistValues.emit({
      values: [
        { label: "Consignee Unavailable", value: "Consignee Unavailable" }
      ]
    });
    q(element, "lightning-button.elogix-show-failure").click();
    await flushPromises();
    expect(q(element, '[data-field="reason"]').options).toHaveLength(1);

    q(element, '[data-field="reason"]').dispatchEvent(
      new CustomEvent("change", { detail: { value: "Consignee Unavailable" } })
    );
    element.shadowRoot
      .querySelectorAll(".elogix-failure-field")
      .forEach((input) => {
        input.reportValidity = jest.fn(() => true);
      });
    await flushPromises();
    q(element, "lightning-button.elogix-save-failure").click();
    await flushPromises();
    expect(recordFailure).toHaveBeenCalledWith({
      request: {
        shipmentId: SHIPMENT_ID,
        reason: "Consignee Unavailable",
        notes: null
      }
    });
  });

  it("lets a verifier verify a delivered proof, and nobody else", async () => {
    verifyProof.mockResolvedValue(OK);
    const delivered = {
      attempts: [{ ...OPEN, Delivery_Status__c: "Delivered" }],
      proofs: [PROOF]
    };
    const element = await create("Delivered", delivered);
    expect(q(element, "lightning-button.elogix-verify")).toBeNull();

    getObjectInfo.emit({ fields: { Verified_By__c: { updateable: true } } });
    await flushPromises();
    q(element, "lightning-button.elogix-verify").click();
    await flushPromises();
    expect(verifyProof).toHaveBeenCalledWith({ proofId: "a0P1" });
  });

  it("shows the service's refusal and load errors", async () => {
    startAttempt.mockResolvedValue({
      isSuccess: false,
      errors: [{ code: "ATTEMPT_LIMIT", message: "Too many attempts." }]
    });
    const element = await create("Failed Delivery", {
      attempts: [],
      proofs: []
    });
    const toast = jest.fn();
    element.addEventListener("lightning__showtoast", toast);
    q(element, "lightning-button.elogix-start").click();
    await flushPromises();
    expect(toast.mock.calls[0][0].detail).toMatchObject({
      variant: "error",
      message: "Too many attempts."
    });

    getDeliveryState.mockRejectedValue({ body: { message: "No access." } });
    const failing = createElement("c-delivery-management", {
      is: DeliveryManagement
    });
    failing.recordId = SHIPMENT_ID;
    document.body.appendChild(failing);
    getRecord.emit({
      fields: {
        Name: { value: "SHP-00002" },
        Status__c: { value: "Dispatched" }
      }
    });
    await flushPromises();
    expect(q(failing, ".elogix-error").textContent).toContain("No access.");
  });
});
