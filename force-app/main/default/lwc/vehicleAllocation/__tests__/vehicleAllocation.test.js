import { createElement } from "lwc";
import VehicleAllocation from "c/vehicleAllocation";
import { getRecord, notifyRecordUpdateAvailable } from "lightning/uiRecordApi";
import getAllocationContext from "@salesforce/apex/FleetConsoleController.getAllocationContext";
import allocate from "@salesforce/apex/FleetConsoleController.allocate";
import release from "@salesforce/apex/FleetConsoleController.release";
import correctDispatchedAllocation from "@salesforce/apex/FleetConsoleController.correctDispatchedAllocation";
import ConfirmationDialog from "c/confirmationDialog";

jest.mock(
  "@salesforce/apex/FleetConsoleController.getAllocationContext",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/FleetConsoleController.allocate",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/FleetConsoleController.reallocate",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/FleetConsoleController.release",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/FleetConsoleController.correctDispatchedAllocation",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock("c/confirmationDialog", () => ({
  __esModule: true,
  default: { open: jest.fn() }
}));

const SHIPMENT_ID = "a0B000000000001AAA";
const OK = { isSuccess: true, errors: [], recordIds: ["a0V1"] };
const CANDIDATES = {
  vehicles: [
    {
      Id: "a0X1",
      Vehicle_Number__c: "TN01AB1234",
      Vehicle_Type__c: "LCV",
      Capacity__c: 1000
    }
  ],
  drivers: [{ Id: "a0D1", Name: "Ravi Kumar", License_Number__c: "TN-DL-1" }]
};

// eslint-disable-next-line @lwc/lwc/no-async-operation
const flushPromises = () => new Promise((resolve) => setTimeout(resolve, 0));

function context(overrides = {}) {
  return {
    shipment: { Id: SHIPMENT_ID, Name: "SHP-00001" },
    canAllocate: true,
    canCorrect: false,
    ...CANDIDATES,
    ...overrides
  };
}

async function create(ctx, status = "Confirmed") {
  getAllocationContext.mockResolvedValue(ctx);
  const element = createElement("c-vehicle-allocation", {
    is: VehicleAllocation
  });
  element.recordId = SHIPMENT_ID;
  document.body.appendChild(element);
  getRecord.emit({ fields: { Status__c: { value: status } } });
  await flushPromises();
  return element;
}

function q(element, selector) {
  return element.shadowRoot.querySelector(selector);
}

async function choose(element) {
  q(element, "lightning-combobox.elogix-vehicle").dispatchEvent(
    new CustomEvent("change", { detail: { value: "a0X1" } })
  );
  q(element, "lightning-combobox.elogix-driver").dispatchEvent(
    new CustomEvent("change", { detail: { value: "a0D1" } })
  );
  await flushPromises();
}

describe("c-vehicle-allocation", () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it("offers the suggested vehicles and drivers and allocates through the controller", async () => {
    allocate.mockResolvedValue(OK);
    const element = await create(context());
    expect(getAllocationContext).toHaveBeenCalledWith({
      shipmentId: SHIPMENT_ID
    });
    expect(q(element, ".elogix-not-allocated")).not.toBeNull();
    expect(
      q(element, "lightning-combobox.elogix-vehicle").options[0].value
    ).toBe("a0X1");
    expect(q(element, "lightning-button.elogix-allocate").disabled).toBe(true);

    await choose(element);
    expect(q(element, "lightning-button.elogix-allocate").disabled).toBe(false);
    q(element, "lightning-button.elogix-allocate").click();
    await flushPromises();

    expect(allocate).toHaveBeenCalledWith({
      request: {
        shipmentId: SHIPMENT_ID,
        vehicleId: "a0X1",
        driverId: "a0D1",
        remarks: null
      }
    });
    expect(notifyRecordUpdateAvailable).toHaveBeenCalledWith([
      { recordId: SHIPMENT_ID }
    ]);
    expect(getAllocationContext).toHaveBeenCalledTimes(2);
  });

  it("shows a planned assignment with reallocate and a confirmed release", async () => {
    ConfirmationDialog.open.mockResolvedValue({ confirmed: true });
    release.mockResolvedValue(OK);
    const element = await create(
      context({
        openAssignment: {
          Id: "a0V1",
          Status__c: "Planned",
          Vehicle__r: { Vehicle_Number__c: "TN01AB1234" },
          Driver__r: { Name: "Ravi Kumar" }
        }
      })
    );
    expect(q(element, ".elogix-assignment").textContent).toContain(
      "TN01AB1234"
    );
    expect(q(element, "lightning-button.elogix-reallocate")).not.toBeNull();
    expect(q(element, "lightning-button.elogix-allocate")).toBeNull();

    q(element, "lightning-button.elogix-release").click();
    await flushPromises();
    expect(release).toHaveBeenCalledWith({ assignmentId: "a0V1" });
  });

  it("is read-only for users without the allocate permission", async () => {
    const element = await create(context({ canAllocate: false }));
    expect(q(element, ".elogix-no-permission")).not.toBeNull();
    expect(q(element, "lightning-combobox")).toBeNull();
    expect(q(element, "lightning-button")).toBeNull();
  });

  it("offers the controlled correction only for an On Hold shipment and the permission", async () => {
    ConfirmationDialog.open.mockResolvedValue({
      confirmed: true,
      reason: "Truck broke down."
    });
    correctDispatchedAllocation.mockResolvedValue(OK);
    const active = {
      Id: "a0V1",
      Status__c: "Active",
      Vehicle__r: { Vehicle_Number__c: "TN01AB1234" },
      Driver__r: { Name: "Ravi Kumar" }
    };
    const inTransit = await create(
      context({ canCorrect: true, openAssignment: active }),
      "In Transit"
    );
    expect(q(inTransit, "lightning-button.elogix-correct")).toBeNull();

    const element = await create(
      context({ canCorrect: true, openAssignment: active }),
      "On Hold"
    );
    await choose(element);
    q(element, "lightning-button.elogix-correct").click();
    await flushPromises();
    expect(ConfirmationDialog.open).toHaveBeenCalledWith(
      expect.objectContaining({ reasonRequired: true })
    );
    expect(correctDispatchedAllocation).toHaveBeenCalledWith({
      request: expect.objectContaining({
        shipmentId: SHIPMENT_ID,
        correctionReason: "Truck broke down."
      })
    });
  });

  it("explains when nothing fits, and shows load errors", async () => {
    const empty = await create(context({ vehicles: [] }));
    expect(q(empty, ".elogix-no-candidates")).not.toBeNull();

    getAllocationContext.mockRejectedValue({ body: { message: "Not found." } });
    const element = createElement("c-vehicle-allocation", {
      is: VehicleAllocation
    });
    element.recordId = SHIPMENT_ID;
    document.body.appendChild(element);
    getRecord.emit({ fields: { Status__c: { value: "Confirmed" } } });
    await flushPromises();
    expect(q(element, ".elogix-error").textContent).toContain("Not found.");
  });

  it("shows a refused allocation and keeps the form", async () => {
    allocate.mockResolvedValue({
      isSuccess: false,
      errors: [{ code: "CAPACITY_INSUFFICIENT", message: "Too heavy." }]
    });
    const element = await create(context());
    const toast = jest.fn();
    element.addEventListener("lightning__showtoast", toast);
    await choose(element);
    q(element, "lightning-button.elogix-allocate").click();
    await flushPromises();
    expect(toast.mock.calls[0][0].detail).toMatchObject({
      variant: "error",
      message: "Too heavy."
    });
    expect(notifyRecordUpdateAvailable).not.toHaveBeenCalled();
  });
});
