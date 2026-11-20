import { createElement } from "lwc";
import ConfirmationDialog from "c/confirmationDialog";

// LightningModal.close is the modal's result channel; the jest-mocks stub reports it as a "close" event.
const close = jest.fn();

function create(props) {
  const element = createElement("c-confirmation-dialog", {
    is: ConfirmationDialog
  });
  Object.assign(element, props);
  element.addEventListener("close", (event) => close(event.detail));
  document.body.appendChild(element);
  return element;
}

function buttons(element) {
  return {
    cancel: element.shadowRoot.querySelector("lightning-button.elogix-cancel"),
    confirm: element.shadowRoot.querySelector("lightning-button.elogix-confirm")
  };
}

describe("c-confirmation-dialog", () => {
  beforeEach(() => {
    close.mockClear();
  });

  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
  });

  it("shows the message with default button labels and no reason field", () => {
    const element = create({ message: "Release this allocation?" });
    expect(
      element.shadowRoot.querySelector(".elogix-message").textContent
    ).toBe("Release this allocation?");
    const { cancel, confirm } = buttons(element);
    expect(cancel.label).toBe("c.eLogix_UI_Cancel");
    expect(confirm.label).toBe("c.eLogix_UI_Confirm");
    expect(confirm.variant).toBe("brand");
    expect(element.shadowRoot.querySelector("lightning-textarea")).toBeNull();
  });

  it("uses custom labels and only the destructive variant besides brand", () => {
    const element = create({
      confirmLabel: "Cancel shipment",
      cancelLabel: "Keep",
      variant: "destructive"
    });
    expect(buttons(element).confirm.label).toBe("Cancel shipment");
    expect(buttons(element).cancel.label).toBe("Keep");
    expect(buttons(element).confirm.variant).toBe("destructive");

    const other = create({ variant: "success" });
    expect(buttons(other).confirm.variant).toBe("brand");
  });

  it("closes with confirmed false on cancel", () => {
    const element = create({ message: "Proceed?" });
    buttons(element).cancel.click();
    expect(close).toHaveBeenCalledWith({ confirmed: false });
  });

  it("closes with confirmed true and no reason when no reason is asked for", () => {
    const element = create({ message: "Proceed?" });
    buttons(element).confirm.click();
    expect(close).toHaveBeenCalledWith({ confirmed: true, reason: null });
  });

  it("requires a valid reason before confirming, and returns it trimmed", async () => {
    const element = create({
      reasonLabel: "Hold reason",
      reasonRequired: true,
      reasonMaxLength: 100
    });
    const textarea = element.shadowRoot.querySelector("lightning-textarea");
    expect(textarea.label).toBe("Hold reason");
    expect(textarea.required).toBe(true);
    expect(textarea.maxLength).toBe(100);

    textarea.reportValidity = jest.fn(() => false);
    buttons(element).confirm.click();
    expect(textarea.reportValidity).toHaveBeenCalled();
    expect(close).not.toHaveBeenCalled();

    textarea.dispatchEvent(
      new CustomEvent("change", {
        detail: { value: "  Awaiting customs papers  " }
      })
    );
    textarea.reportValidity = jest.fn(() => true);
    await Promise.resolve();
    buttons(element).confirm.click();
    expect(close).toHaveBeenCalledWith({
      confirmed: true,
      reason: "Awaiting customs papers"
    });
  });
});
