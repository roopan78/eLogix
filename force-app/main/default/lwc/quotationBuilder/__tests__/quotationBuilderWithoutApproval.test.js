import { createElement } from "lwc";
import QuotationBuilder from "c/quotationBuilder";
import { getRecord } from "lightning/uiRecordApi";

// A user without eLogix_Approve_Quotation. Custom permission imports resolve once per module load,
// so this case has its own test file.
jest.mock(
  "@salesforce/customPermission/eLogix_Approve_Quotation",
  () => ({ __esModule: true, default: false }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/QuotationConsoleController.getLines",
  () => {
    const { createApexTestWireAdapter } = require("@salesforce/sfdx-lwc-jest");
    return { default: createApexTestWireAdapter(jest.fn()) };
  },
  { virtual: true }
);

// eslint-disable-next-line @lwc/lwc/no-async-operation
const flushPromises = () => new Promise((resolve) => setTimeout(resolve, 0));

describe("c-quotation-builder without the approval permission", () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
  });

  it("hides approve and reject on a pending quotation", async () => {
    const element = createElement("c-quotation-builder", {
      is: QuotationBuilder
    });
    element.recordId = "a0Q000000000001AAA";
    element.objectApiName = "Quotation__c";
    document.body.appendChild(element);
    getRecord.emit({
      fields: {
        Name: { value: "QT-0001" },
        Status__c: { value: "Pending Approval" }
      }
    });
    await flushPromises();

    expect(
      element.shadowRoot.querySelectorAll("lightning-button.elogix-action")
    ).toHaveLength(0);
    expect(
      element.shadowRoot.querySelector(".elogix-no-actions")
    ).not.toBeNull();
  });
});
