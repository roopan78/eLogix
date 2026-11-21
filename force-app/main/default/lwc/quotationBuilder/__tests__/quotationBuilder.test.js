import { createElement } from "lwc";
import QuotationBuilder from "c/quotationBuilder";
import {
  getRecord,
  updateRecord,
  notifyRecordUpdateAvailable
} from "lightning/uiRecordApi";
import { getObjectInfo } from "lightning/uiObjectInfoApi";
import { refreshApex } from "@salesforce/apex";
import { navigate } from "lightning/navigation";
import getLines from "@salesforce/apex/QuotationConsoleController.getLines";
import createFromRequest from "@salesforce/apex/QuotationConsoleController.createFromRequest";
import recalculate from "@salesforce/apex/QuotationConsoleController.recalculate";
import reject from "@salesforce/apex/QuotationConsoleController.reject";
import convertToShipment from "@salesforce/apex/QuotationConsoleController.convertToShipment";
import ConfirmationDialog from "c/confirmationDialog";

jest.mock(
  "@salesforce/apex/QuotationConsoleController.getLines",
  () => {
    const { createApexTestWireAdapter } = require("@salesforce/sfdx-lwc-jest");
    return { default: createApexTestWireAdapter(jest.fn()) };
  },
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/QuotationConsoleController.createFromRequest",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/QuotationConsoleController.recalculate",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/QuotationConsoleController.submitForApproval",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/QuotationConsoleController.approve",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/QuotationConsoleController.reject",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/QuotationConsoleController.convertToShipment",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/customPermission/eLogix_Approve_Quotation",
  () => ({ __esModule: true, default: true }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex",
  () => ({ refreshApex: jest.fn(() => Promise.resolve()) }),
  { virtual: true }
);
jest.mock("c/confirmationDialog", () => ({
  __esModule: true,
  default: { open: jest.fn() }
}));
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

const QUOTATION_ID = "a0Q000000000001AAA";
const OK = { isSuccess: true, errors: [], recordIds: [QUOTATION_ID] };

// eslint-disable-next-line @lwc/lwc/no-async-operation
const flushPromises = () => new Promise((resolve) => setTimeout(resolve, 0));

async function create(status, props = {}) {
  const element = createElement("c-quotation-builder", {
    is: QuotationBuilder
  });
  Object.assign(
    element,
    { recordId: QUOTATION_ID, objectApiName: "Quotation__c" },
    props
  );
  document.body.appendChild(element);
  if (status) {
    getRecord.emit({
      fields: { Name: { value: "QT-0001" }, Status__c: { value: status } }
    });
  }
  await flushPromises();
  return element;
}

function actionNames(element) {
  return Array.from(
    element.shadowRoot.querySelectorAll("lightning-button.elogix-action")
  ).map((button) => button.dataset.name);
}

function click(element, name) {
  element.shadowRoot
    .querySelector(`lightning-button.elogix-action[data-name="${name}"]`)
    .click();
}

describe("c-quotation-builder", () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it("shows the breakdown, the charge lines and the field labels", async () => {
    const element = await create("Draft");
    getLines.emit([
      { Id: "a0R1", Charge_Type__c: "Base Freight", Amount__c: 5000 }
    ]);
    getObjectInfo.emit({ fields: { Amount__c: { label: "Line Amount" } } });
    await flushPromises();

    expect(
      element.shadowRoot.querySelector("lightning-record-view-form").recordId
    ).toBe(QUOTATION_ID);
    const table = element.shadowRoot.querySelector("c-reusable-data-table");
    expect(table.records).toHaveLength(1);
    expect(table.columns.find((c) => c.fieldName === "Amount__c").label).toBe(
      "Line Amount"
    );
    expect(element.shadowRoot.querySelector("c-status-badge").status).toBe(
      "Draft"
    );
  });

  it.each([
    ["Draft", ["recalculate", "submit"]],
    ["Pending Approval", ["approve", "reject"]],
    ["Approved", ["markSent"]],
    ["Sent", ["accept"]],
    ["Accepted", ["convert"]]
  ])("offers the %s actions", async (status, expected) => {
    expect(actionNames(await create(status))).toEqual(expected);
  });

  it("recalculates through the controller and refreshes the record and lines", async () => {
    recalculate.mockResolvedValue(OK);
    const element = await create("Draft");
    const toast = jest.fn();
    element.addEventListener("lightning__showtoast", toast);
    click(element, "recalculate");
    await flushPromises();

    expect(recalculate).toHaveBeenCalledWith({ quotationId: QUOTATION_ID });
    expect(toast.mock.calls[0][0].detail.variant).toBe("success");
    expect(notifyRecordUpdateAvailable).toHaveBeenCalledWith([
      { recordId: QUOTATION_ID }
    ]);
    expect(refreshApex).toHaveBeenCalled();
  });

  it("asks for a rejection reason before rejecting", async () => {
    ConfirmationDialog.open.mockResolvedValue({
      confirmed: true,
      reason: "Discount too deep."
    });
    reject.mockResolvedValue(OK);
    const element = await create("Pending Approval");
    click(element, "reject");
    await flushPromises();

    expect(ConfirmationDialog.open).toHaveBeenCalledWith(
      expect.objectContaining({ reasonRequired: true, variant: "destructive" })
    );
    expect(reject).toHaveBeenCalledWith({
      quotationId: QUOTATION_ID,
      reason: "Discount too deep."
    });
  });

  it("marks an approved quotation as sent through Lightning Data Service", async () => {
    const element = await create("Approved");
    click(element, "markSent");
    await flushPromises();
    expect(updateRecord).toHaveBeenCalledWith({
      fields: { Id: QUOTATION_ID, Status__c: "Sent" }
    });
  });

  it("converts an accepted quotation and opens the new shipment", async () => {
    ConfirmationDialog.open.mockResolvedValue({ confirmed: true });
    convertToShipment.mockResolvedValue({
      isSuccess: true,
      errors: [],
      recordIds: ["a0B000000000009AAA"]
    });
    const element = await create("Accepted");
    click(element, "convert");
    await flushPromises();

    expect(convertToShipment).toHaveBeenCalledWith({
      quotationId: QUOTATION_ID
    });
    expect(navigate).toHaveBeenCalledWith({
      type: "standard__recordPage",
      attributes: {
        recordId: "a0B000000000009AAA",
        objectApiName: "Shipment__c",
        actionName: "view"
      }
    });
  });

  it("shows a refused conversion without navigating", async () => {
    ConfirmationDialog.open.mockResolvedValue({ confirmed: true });
    convertToShipment.mockResolvedValue({
      isSuccess: false,
      errors: [{ code: "QUOTATION_NOT_CONVERTIBLE", message: "Not accepted." }]
    });
    const element = await create("Accepted");
    const toast = jest.fn();
    element.addEventListener("lightning__showtoast", toast);
    click(element, "convert");
    await flushPromises();
    expect(toast.mock.calls[0][0].detail).toMatchObject({
      variant: "error",
      message: "Not accepted."
    });
    expect(navigate).not.toHaveBeenCalled();
  });

  it("creates a quotation from a shipment request page and opens it", async () => {
    createFromRequest.mockResolvedValue(OK);
    const element = await create(null, {
      recordId: "a0C000000000001AAA",
      objectApiName: "Shipment_Request__c"
    });
    expect(
      element.shadowRoot.querySelector("lightning-record-view-form")
    ).toBeNull();
    element.shadowRoot.querySelector("lightning-button.elogix-create").click();
    await flushPromises();

    expect(createFromRequest).toHaveBeenCalledWith({
      shipmentRequestId: "a0C000000000001AAA"
    });
    expect(navigate.mock.calls[0][0].attributes).toMatchObject({
      recordId: QUOTATION_ID,
      objectApiName: "Quotation__c"
    });
  });
});
