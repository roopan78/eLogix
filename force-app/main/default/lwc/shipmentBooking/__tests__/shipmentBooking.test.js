import { createElement } from "lwc";
import ShipmentBooking from "c/shipmentBooking";
import { navigate } from "lightning/navigation";

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

const ACCOUNT_ID = "001000000000001AAA";
const REQUEST_ID = "a0C000000000001AAA";

function create(props = {}) {
  const element = createElement("c-shipment-booking", { is: ShipmentBooking });
  Object.assign(element, props);
  document.body.appendChild(element);
  return element;
}

function form(element) {
  return element.shadowRoot.querySelector("lightning-record-edit-form");
}

function field(element, name) {
  return Array.from(
    element.shadowRoot.querySelectorAll("lightning-input-field")
  ).find((input) => input.fieldName === name);
}

/** Clicks a submit button, then raises the form's submit event as the base component would. */
function submitWith(element, buttonClass, fields) {
  element.shadowRoot.querySelector(`lightning-button.${buttonClass}`).click();
  const event = new CustomEvent("submit", {
    detail: { fields },
    cancelable: true
  });
  form(element).dispatchEvent(event);
  return event;
}

describe("c-shipment-booking", () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it("renders the request form with the booking fields", () => {
    const element = create();
    expect(form(element).objectApiName).toBe("Shipment_Request__c");
    [
      "Customer__c",
      "Business_Unit__c",
      "Origin__c",
      "Destination__c",
      "Requested_Pickup_Date__c",
      "Total_Weight__c"
    ].forEach((name) => expect(field(element, name)).toBeTruthy());
    expect(field(element, "Status__c")).toBeUndefined();
    expect(field(element, "Customer__c").value).toBeNull();
  });

  it("pre-fills the customer on an Account page only", () => {
    expect(
      field(
        create({ recordId: ACCOUNT_ID, objectApiName: "Account" }),
        "Customer__c"
      ).value
    ).toBe(ACCOUNT_ID);
    expect(
      field(
        create({ recordId: ACCOUNT_ID, objectApiName: "Contact" }),
        "Customer__c"
      ).value
    ).toBeNull();
  });

  it("submits the request as Submitted, keeping the entered fields", () => {
    const element = create();
    form(element).submit = jest.fn();
    const event = submitWith(element, "elogix-submit", {
      Origin__c: "Chennai"
    });
    expect(event.defaultPrevented).toBe(true);
    expect(form(element).submit).toHaveBeenCalledWith({
      Origin__c: "Chennai",
      Status__c: "Submitted"
    });
  });

  it("saves a draft as Draft", () => {
    const element = create();
    form(element).submit = jest.fn();
    submitWith(element, "elogix-save-draft", { Origin__c: "Madurai" });
    expect(form(element).submit).toHaveBeenCalledWith({
      Origin__c: "Madurai",
      Status__c: "Draft"
    });
  });

  it("on success toasts, raises requestcreated and opens the new request", async () => {
    const element = create();
    form(element).submit = jest.fn();
    const toast = jest.fn();
    const created = jest.fn();
    element.addEventListener("lightning__showtoast", toast);
    element.addEventListener("requestcreated", created);

    submitWith(element, "elogix-submit", {});
    form(element).dispatchEvent(
      new CustomEvent("success", { detail: { id: REQUEST_ID } })
    );
    await Promise.resolve();

    expect(toast.mock.calls[0][0].detail).toMatchObject({
      message: "c.eLogix_UI_Request_Submitted",
      variant: "success"
    });
    expect(created.mock.calls[0][0].detail).toEqual({ recordId: REQUEST_ID });
    expect(navigate).toHaveBeenCalledWith({
      type: "standard__recordPage",
      attributes: {
        recordId: REQUEST_ID,
        objectApiName: "Shipment_Request__c",
        actionName: "view"
      }
    });
  });

  it("with stay-on-page clears the form instead of navigating", () => {
    const element = create({ stayOnPage: true });
    form(element).submit = jest.fn();
    const resets = Array.from(
      element.shadowRoot.querySelectorAll("lightning-input-field")
    ).map((input) => {
      input.reset = jest.fn();
      return input.reset;
    });

    submitWith(element, "elogix-save-draft", {});
    form(element).dispatchEvent(
      new CustomEvent("success", { detail: { id: REQUEST_ID } })
    );

    expect(navigate).not.toHaveBeenCalled();
    resets.forEach((reset) => expect(reset).toHaveBeenCalled());
  });

  it("disables the buttons while saving and re-enables them on error", async () => {
    const element = create();
    form(element).submit = jest.fn();
    submitWith(element, "elogix-submit", {});
    await Promise.resolve();
    const submit = element.shadowRoot.querySelector(
      "lightning-button.elogix-submit"
    );
    expect(submit.disabled).toBe(true);

    form(element).dispatchEvent(new CustomEvent("error", { detail: {} }));
    await Promise.resolve();
    expect(submit.disabled).toBe(false);
    expect(navigate).not.toHaveBeenCalled();
  });
});
