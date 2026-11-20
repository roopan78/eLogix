import { createElement } from "lwc";
import LoadingIndicator from "c/loadingIndicator";

function create(props) {
  const element = createElement("c-loading-indicator", {
    is: LoadingIndicator
  });
  Object.assign(element, props);
  document.body.appendChild(element);
  return element;
}

describe("c-loading-indicator", () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
  });

  it("renders a brand spinner with the default accessible label", () => {
    const element = create({});
    const spinner = element.shadowRoot.querySelector("lightning-spinner");
    expect(spinner.alternativeText).toBe("c.eLogix_UI_Loading");
    expect(spinner.size).toBe("medium");
    expect(spinner.variant).toBe("brand");
    expect(
      element.shadowRoot.querySelector('[aria-busy="true"]')
    ).not.toBeNull();
    expect(element.shadowRoot.querySelector("p")).toBeNull();
  });

  it("uses the given text, size, variant and message", () => {
    const element = create({
      alternativeText: "Loading shipments",
      size: "small",
      variant: "base",
      message: "Fetching the latest positions"
    });
    const spinner = element.shadowRoot.querySelector("lightning-spinner");
    expect(spinner.alternativeText).toBe("Loading shipments");
    expect(spinner.size).toBe("small");
    expect(spinner.variant).toBe("base");
    const message = element.shadowRoot.querySelector("p");
    expect(message.textContent).toBe("Fetching the latest positions");
    expect(message.getAttribute("aria-live")).toBe("polite");
  });
});
