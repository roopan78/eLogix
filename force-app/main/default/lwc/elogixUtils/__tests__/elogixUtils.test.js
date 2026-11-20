import {
  reduceErrors,
  errorMessage,
  serviceResultMessages,
  showSuccess,
  showError,
  handleServiceResult
} from "c/elogixUtils";

function fakeComponent() {
  return { dispatchEvent: jest.fn() };
}

function toastOf(component) {
  return component.dispatchEvent.mock.calls[0][0].detail;
}

describe("c/elogixUtils", () => {
  describe("reduceErrors", () => {
    it("handles AuraHandledException, UI API, JavaScript and string errors, without duplicates", () => {
      const errors = [
        { body: { message: "Access denied." } },
        {
          body: {
            pageErrors: [{ message: "Page problem." }],
            fieldErrors: { Status__c: [{ message: "Bad status." }] }
          }
        },
        {
          body: {
            output: {
              errors: [{ message: "Output problem." }],
              fieldErrors: { Name: [{ message: "Bad name." }] }
            }
          }
        },
        { body: [{ message: "Array body." }] },
        new Error("Script failure."),
        "Plain text.",
        { statusText: "Server Error" },
        { body: { message: "Access denied." } },
        null,
        { body: { message: "   " } }
      ];
      expect(reduceErrors(errors)).toEqual([
        "Access denied.",
        "Page problem.",
        "Bad status.",
        "Output problem.",
        "Bad name.",
        "Array body.",
        "Script failure.",
        "Plain text.",
        "Server Error"
      ]);
    });

    it("accepts a single error", () => {
      expect(reduceErrors({ body: { message: "One." } })).toEqual(["One."]);
      expect(reduceErrors(undefined)).toEqual([]);
    });
  });

  it("errorMessage joins the messages or falls back to the generic label", () => {
    expect(errorMessage(["A.", "B."])).toBe("A. B.");
    expect(errorMessage({})).toBe("c.eLogix_UI_Unexpected_Error");
  });

  it("serviceResultMessages reads the per-record errors of a ServiceResult", () => {
    const result = {
      isSuccess: false,
      errors: [
        { code: "X", message: "First." },
        { code: "Y", message: "First." },
        { code: "Z", message: "Second." }
      ]
    };
    expect(serviceResultMessages(result)).toEqual(["First.", "Second."]);
    expect(serviceResultMessages(null)).toEqual([]);
  });

  it("showSuccess and showError dispatch toasts", () => {
    const ok = fakeComponent();
    showSuccess(ok, "Saved.");
    expect(toastOf(ok)).toMatchObject({
      title: "c.eLogix_UI_Success_Title",
      message: "Saved.",
      variant: "success"
    });

    const failed = fakeComponent();
    showError(failed, { body: { message: "Nope." } });
    expect(toastOf(failed)).toMatchObject({
      title: "c.eLogix_UI_Error_Title",
      message: "Nope.",
      variant: "error",
      mode: "sticky"
    });
  });

  describe("handleServiceResult", () => {
    it("toasts success and returns true", () => {
      const component = fakeComponent();
      expect(
        handleServiceResult(
          component,
          { isSuccess: true, errors: [], recordIds: ["a01"] },
          "Allocated."
        )
      ).toBe(true);
      expect(toastOf(component)).toMatchObject({
        message: "Allocated.",
        variant: "success"
      });
    });

    it("returns true silently without a success message", () => {
      const component = fakeComponent();
      expect(
        handleServiceResult(component, { isSuccess: true, errors: [] })
      ).toBe(true);
      expect(component.dispatchEvent).not.toHaveBeenCalled();
    });

    it("toasts the service messages on failure and returns false", () => {
      const component = fakeComponent();
      const result = {
        isSuccess: false,
        errors: [{ code: "RECORD_LOCKED", message: "Try again." }]
      };
      expect(handleServiceResult(component, result, "Saved.")).toBe(false);
      expect(toastOf(component)).toMatchObject({
        message: "Try again.",
        variant: "error"
      });
    });

    it("treats a missing result as a failure with the generic message", () => {
      const component = fakeComponent();
      expect(handleServiceResult(component, undefined)).toBe(false);
      expect(toastOf(component).message).toBe("c.eLogix_UI_Unexpected_Error");
    });
  });
});
