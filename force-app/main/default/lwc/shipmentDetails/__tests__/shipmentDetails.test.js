import { createElement } from "lwc";
import ShipmentDetails from "c/shipmentDetails";
import { getRecord, notifyRecordUpdateAvailable } from "lightning/uiRecordApi";
import getStatusOptions from "@salesforce/apex/ShipmentConsoleController.getStatusOptions";
import changeStatus from "@salesforce/apex/ShipmentConsoleController.changeStatus";
import ConfirmationDialog from "c/confirmationDialog";

jest.mock(
  "@salesforce/apex/ShipmentConsoleController.getStatusOptions",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/ShipmentConsoleController.changeStatus",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock("c/confirmationDialog", () => ({
  __esModule: true,
  default: { open: jest.fn() }
}));

const SHIPMENT_ID = "a0B000000000001AAA";
const OPTIONS = [
  {
    value: "Ready for Dispatch",
    label: "Ready for Dispatch",
    validatedOnSave: true,
    note: "Allocate a vehicle and driver first.",
    byOverride: false
  },
  {
    value: "On Hold",
    label: "On Hold",
    validatedOnSave: false,
    byOverride: false
  },
  { value: "Draft", label: "Draft", validatedOnSave: false, byOverride: true }
];

// Lets pending promises and wire deliveries settle (test helper; the LWC timer rule targets components).
// eslint-disable-next-line @lwc/lwc/no-async-operation
const flushPromises = () => new Promise((resolve) => setTimeout(resolve, 0));

function record(status) {
  return {
    fields: { Name: { value: "SHP-00001" }, Status__c: { value: status } }
  };
}

async function create(options = OPTIONS) {
  getStatusOptions.mockResolvedValue(options);
  const element = createElement("c-shipment-details", { is: ShipmentDetails });
  element.recordId = SHIPMENT_ID;
  document.body.appendChild(element);
  getRecord.emit(record("Confirmed"));
  await flushPromises();
  return element;
}

function query(element, selector) {
  return element.shadowRoot.querySelector(selector);
}

async function select(element, value) {
  query(element, "lightning-combobox.elogix-status-select").dispatchEvent(
    new CustomEvent("change", { detail: { value } })
  );
  await flushPromises();
}

describe("c-shipment-details", () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it("shows the record fields through a record view form and the status badge", async () => {
    const element = await create();
    const viewForm = query(element, "lightning-record-view-form");
    expect(viewForm.recordId).toBe(SHIPMENT_ID);
    expect(viewForm.objectApiName).toBe("Shipment__c");
    expect(query(element, "c-status-badge").status).toBe("Confirmed");
  });

  it("offers the policy's options, marking save-time checks and overrides", async () => {
    const element = await create();
    expect(getStatusOptions).toHaveBeenCalledWith({ shipmentId: SHIPMENT_ID });
    const labels = query(
      element,
      "lightning-combobox.elogix-status-select"
    ).options.map((option) => option.label);
    expect(labels).toEqual([
      "Ready for Dispatch (c.eLogix_UI_Checked_On_Save)",
      "On Hold",
      "Draft (c.eLogix_UI_Override)"
    ]);
    expect(
      query(element, "lightning-button.elogix-change-status").disabled
    ).toBe(true);
  });

  it("explains a save-time check when that option is selected", async () => {
    const element = await create();
    await select(element, "Ready for Dispatch");
    expect(query(element, ".elogix-selected-note")).not.toBeNull();
    await select(element, "On Hold");
    expect(query(element, ".elogix-selected-note")).toBeNull();
    expect(
      query(element, "lightning-button.elogix-change-status").disabled
    ).toBe(false);
  });

  it("says when no change is available, and shows option load errors", async () => {
    const empty = await create([]);
    expect(query(empty, ".elogix-no-options").textContent).toBe(
      "c.eLogix_UI_No_Status_Options"
    );

    getStatusOptions.mockRejectedValue({
      body: { message: "Shipment not found." }
    });
    const element = createElement("c-shipment-details", {
      is: ShipmentDetails
    });
    element.recordId = SHIPMENT_ID;
    document.body.appendChild(element);
    getRecord.emit(record("Confirmed"));
    await flushPromises();
    expect(query(element, ".elogix-options-error").textContent).toBe(
      "Shipment not found."
    );
  });

  it("asks for the hold reason, then changes the status through the controller", async () => {
    const element = await create();
    ConfirmationDialog.open.mockResolvedValue({
      confirmed: true,
      reason: "Awaiting customs papers."
    });
    changeStatus.mockResolvedValue({
      isSuccess: true,
      errors: [],
      recordIds: [SHIPMENT_ID]
    });
    const toast = jest.fn();
    const changed = jest.fn();
    element.addEventListener("lightning__showtoast", toast);
    element.addEventListener("statuschange", changed);

    await select(element, "On Hold");
    query(element, "lightning-button.elogix-change-status").click();
    await flushPromises();

    expect(ConfirmationDialog.open).toHaveBeenCalledWith(
      expect.objectContaining({
        reasonLabel: "c.eLogix_UI_Hold_Reason",
        reasonRequired: true,
        variant: "brand"
      })
    );
    expect(changeStatus).toHaveBeenCalledWith({
      shipmentId: SHIPMENT_ID,
      targetStatus: "On Hold",
      reason: "Awaiting customs papers."
    });
    expect(toast.mock.calls[0][0].detail.variant).toBe("success");
    expect(notifyRecordUpdateAvailable).toHaveBeenCalledWith([
      { recordId: SHIPMENT_ID }
    ]);
    expect(changed.mock.calls[0][0].detail).toEqual({
      recordId: SHIPMENT_ID,
      status: "On Hold"
    });
  });

  it("does nothing when the dialog is cancelled", async () => {
    const element = await create();
    ConfirmationDialog.open.mockResolvedValue({ confirmed: false });
    await select(element, "Ready for Dispatch");
    query(element, "lightning-button.elogix-change-status").click();
    await flushPromises();
    expect(ConfirmationDialog.open).toHaveBeenCalledWith(
      expect.objectContaining({ reasonRequired: false })
    );
    expect(changeStatus).not.toHaveBeenCalled();
  });

  it("shows the service's rejection and leaves the record alone", async () => {
    const element = await create();
    ConfirmationDialog.open.mockResolvedValue({
      confirmed: true,
      reason: null
    });
    changeStatus.mockResolvedValue({
      isSuccess: false,
      errors: [
        {
          code: "FIELD_CUSTOM_VALIDATION_EXCEPTION",
          message: "Allocate first."
        }
      ]
    });
    const toast = jest.fn();
    element.addEventListener("lightning__showtoast", toast);

    await select(element, "Ready for Dispatch");
    query(element, "lightning-button.elogix-change-status").click();
    await flushPromises();

    expect(toast.mock.calls[0][0].detail).toMatchObject({
      message: "Allocate first.",
      variant: "error"
    });
    expect(notifyRecordUpdateAvailable).not.toHaveBeenCalled();
  });

  it("reloads the options when the status changes in Lightning Data Service", async () => {
    await create();
    expect(getStatusOptions).toHaveBeenCalledTimes(1);
    getRecord.emit(record("Confirmed"));
    await flushPromises();
    expect(getStatusOptions).toHaveBeenCalledTimes(1);
    getRecord.emit(record("On Hold"));
    await flushPromises();
    expect(getStatusOptions).toHaveBeenCalledTimes(2);
  });
});
