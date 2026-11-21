import { createElement } from "lwc";
import StatusBadge from "c/statusBadge";

function create(props) {
  const element = createElement("c-status-badge", { is: StatusBadge });
  Object.assign(element, props);
  document.body.appendChild(element);
  return element;
}

function badgeOf(element) {
  return element.shadowRoot.querySelector("span.slds-badge");
}

describe("c-status-badge", () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
  });

  it.each([
    ["Delivered", "success", "slds-theme_success"],
    ["On Hold", "warning", "slds-theme_warning"],
    ["Cancelled", "error", "slds-theme_error"],
    ["In Transit", "inverse", "slds-badge_inverse"],
    ["Draft", "lightest", "slds-badge_lightest"],
    ["Something New", "lightest", "slds-badge_lightest"]
  ])("shows %s with the %s theme", (status, variant, cssClass) => {
    const badge = badgeOf(create({ status }));
    expect(badge.textContent).toBe(status);
    expect(badge.title).toBe(status);
    expect(badge.dataset.variant).toBe(variant);
    expect(badge.classList).toContain(cssClass);
  });

  it("matches statuses case-insensitively and ignores surrounding spaces", () => {
    expect(badgeOf(create({ status: "  in transit " })).dataset.variant).toBe(
      "inverse"
    );
  });

  it("shows the label instead of the raw status", () => {
    const badge = badgeOf(
      create({ status: "Failed Delivery", label: "Livraison échouée" })
    );
    expect(badge.textContent).toBe("Livraison échouée");
    expect(badge.dataset.variant).toBe("error");
  });

  it("lets an explicit variant override the mapping, and ignores unknown variants", () => {
    expect(
      badgeOf(create({ status: "Draft", variant: "success" })).dataset.variant
    ).toBe("success");
    expect(
      badgeOf(create({ status: "Delivered", variant: "purple" })).dataset
        .variant
    ).toBe("success");
  });

  it("renders nothing without a status", () => {
    expect(badgeOf(create({}))).toBeNull();
  });

  it("updates when the status changes", async () => {
    const element = create({ status: "Dispatched" });
    element.status = "Delivered";
    await Promise.resolve();
    expect(badgeOf(element).dataset.variant).toBe("success");
  });
});
