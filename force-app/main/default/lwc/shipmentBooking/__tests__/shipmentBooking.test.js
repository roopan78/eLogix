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
const UNIT_ID = "a01000000000001AAA";
const REQUEST_ID = "a0C000000000001AAA";

/** Lets wire deliveries and re-renders settle. */
async function flush() {
  for (let i = 0; i < 5; i++) {
    // eslint-disable-next-line no-await-in-loop
    await Promise.resolve();
  }
}

function create(props = {}) {
  const element = createElement("c-shipment-booking", { is: ShipmentBooking });
  Object.assign(element, props);
  document.body.appendChild(element);
  return element;
}

function q(element, selector) {
  return element.shadowRoot.querySelector(selector);
}

function bookingForm(element) {
  return q(element, "lightning-record-edit-form.elogix-booking");
}

function field(root, name) {
  return Array.from(root.querySelectorAll("lightning-input-field")).find(
    (input) => input.fieldName === name
  );
}

/** The standard lookup reports its value as a one-element array of Ids. */
async function chooseInLookup(element, name, id) {
  field(bookingForm(element), name).dispatchEvent(
    new CustomEvent("change", { detail: { value: [id] } })
  );
  await flush();
}

/** Clicks a submit button, then raises the form's submit event as the base component would. */
function submitWith(element, buttonClass, fields) {
  q(element, `lightning-button.${buttonClass}`).click();
  const event = new CustomEvent("submit", {
    detail: { fields },
    cancelable: true
  });
  bookingForm(element).dispatchEvent(event);
  return event;
}

describe("c-shipment-booking", () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it("renders the request form with the standard Customer and Business Unit lookups", () => {
    const element = create();
    const form = bookingForm(element);
    expect(form.objectApiName).toBe("Shipment_Request__c");
    [
      "Customer__c",
      "Business_Unit__c",
      "Origin__c",
      "Destination__c",
      "Requested_Pickup_Date__c",
      "Total_Weight__c"
    ].forEach((name) => expect(field(form, name)).toBeTruthy());
    expect(field(form, "Customer__c").required).toBe(true);
    expect(field(form, "Business_Unit__c").required).toBe(true);
    expect(field(form, "Status__c")).toBeUndefined();
    expect(field(form, "Customer__c").value).toBeNull();
    expect(q(element, ".elogix-create-modal")).toBeNull();
  });

  it("pre-fills the customer on an Account page only", () => {
    expect(
      field(
        bookingForm(create({ recordId: ACCOUNT_ID, objectApiName: "Account" })),
        "Customer__c"
      ).value
    ).toBe(ACCOUNT_ID);
    expect(
      field(
        bookingForm(create({ recordId: ACCOUNT_ID, objectApiName: "Contact" })),
        "Customer__c"
      ).value
    ).toBeNull();
  });

  it("offers no custom create links; the lookups are the standard fields", () => {
    const element = create();
    expect(element.shadowRoot.querySelectorAll("lightning-button").length).toBe(
      2
    );
    expect(q(element, ".elogix-create-modal")).toBeNull();
  });

  it("keeps a chosen lookup value while other fields are edited", async () => {
    const element = create();
    await chooseInLookup(element, "Business_Unit__c", UNIT_ID);
    field(bookingForm(element), "Origin__c").value = "Chennai";
    await flush();
    expect(field(bookingForm(element), "Business_Unit__c").value).toBe(UNIT_ID);
  });

  it("submits the request as Submitted, keeping the entered fields", () => {
    const element = create();
    bookingForm(element).submit = jest.fn();
    const event = submitWith(element, "elogix-submit", {
      Origin__c: "Chennai",
      Customer__c: ACCOUNT_ID
    });
    expect(event.defaultPrevented).toBe(true);
    expect(bookingForm(element).submit).toHaveBeenCalledWith({
      Origin__c: "Chennai",
      Customer__c: ACCOUNT_ID,
      Status__c: "Submitted"
    });
  });

  it("saves a draft as Draft", () => {
    const element = create();
    bookingForm(element).submit = jest.fn();
    submitWith(element, "elogix-save-draft", { Origin__c: "Madurai" });
    expect(bookingForm(element).submit).toHaveBeenCalledWith({
      Origin__c: "Madurai",
      Status__c: "Draft"
    });
  });

  it("on success toasts, raises requestcreated and opens the new request", async () => {
    const element = create();
    bookingForm(element).submit = jest.fn();
    const toast = jest.fn();
    const created = jest.fn();
    element.addEventListener("lightning__showtoast", toast);
    element.addEventListener("requestcreated", created);

    submitWith(element, "elogix-submit", {});
    bookingForm(element).dispatchEvent(
      new CustomEvent("success", { detail: { id: REQUEST_ID } })
    );
    await flush();

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

  it("with stay-on-page clears the form instead of navigating", async () => {
    const element = create({ stayOnPage: true });
    await chooseInLookup(element, "Business_Unit__c", UNIT_ID);
    bookingForm(element).submit = jest.fn();
    const resets = Array.from(
      bookingForm(element).querySelectorAll("lightning-input-field")
    ).map((input) => {
      input.reset = jest.fn();
      return input.reset;
    });

    submitWith(element, "elogix-save-draft", {});
    bookingForm(element).dispatchEvent(
      new CustomEvent("success", { detail: { id: REQUEST_ID } })
    );
    await flush();

    expect(navigate).not.toHaveBeenCalled();
    resets.forEach((reset) => expect(reset).toHaveBeenCalled());
    expect(field(bookingForm(element), "Business_Unit__c").value).toBeNull();
  });

  it("disables the buttons while saving and re-enables them on error", async () => {
    const element = create();
    bookingForm(element).submit = jest.fn();
    submitWith(element, "elogix-submit", {});
    await flush();
    const submit = q(element, "lightning-button.elogix-submit");
    expect(submit.disabled).toBe(true);

    bookingForm(element).dispatchEvent(
      new CustomEvent("error", { detail: {} })
    );
    await flush();
    expect(submit.disabled).toBe(false);
    expect(navigate).not.toHaveBeenCalled();
  });
});
