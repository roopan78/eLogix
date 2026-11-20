import { createElement } from "lwc";
import ReusableDataTable from "c/reusableDataTable";

const COLUMNS = [
  { label: "Shipment", fieldName: "Name", sortable: true },
  { label: "Weight", fieldName: "Weight__c", type: "number", sortable: true }
];
const RECORDS = [
  { Id: "a01", Name: "SHP-00002", Weight__c: 900 },
  { Id: "a02", Name: "SHP-00010", Weight__c: null },
  { Id: "a03", Name: "SHP-00001", Weight__c: 250 }
];

function create(props) {
  const element = createElement("c-reusable-data-table", {
    is: ReusableDataTable
  });
  Object.assign(element, { columns: COLUMNS }, props);
  document.body.appendChild(element);
  return element;
}

function query(element, selector) {
  return element.shadowRoot.querySelector(selector);
}

describe("c-reusable-data-table", () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
  });

  it("shows only the loading indicator while loading", () => {
    const element = create({
      isLoading: true,
      records: RECORDS,
      error: "ignored while loading"
    });
    expect(query(element, "c-loading-indicator")).not.toBeNull();
    expect(query(element, "lightning-datatable")).toBeNull();
    expect(query(element, ".elogix-error")).toBeNull();
  });

  it("shows the reduced error with a retry button that raises retry", () => {
    const element = create({
      error: { body: { message: "You do not have access." } },
      records: RECORDS
    });
    const alert = query(element, ".elogix-error");
    expect(alert.getAttribute("role")).toBe("alert");
    expect(alert.textContent).toContain("You do not have access.");
    expect(query(element, "lightning-datatable")).toBeNull();

    const handler = jest.fn();
    element.addEventListener("retry", handler);
    query(element, "lightning-button.elogix-retry").click();
    expect(handler).toHaveBeenCalledTimes(1);
  });

  it("shows the default or custom empty message when there are no records", async () => {
    const element = create({ records: [] });
    expect(query(element, ".elogix-empty").textContent).toBe(
      "c.eLogix_UI_No_Records"
    );

    element.emptyMessage = "No shipments match these filters.";
    await Promise.resolve();
    expect(query(element, ".elogix-empty").textContent).toBe(
      "No shipments match these filters."
    );
  });

  it("treats a missing records value as empty", () => {
    expect(
      query(create({ records: undefined }), ".elogix-empty")
    ).not.toBeNull();
  });

  it("renders the datatable with the given columns, key field and rows", () => {
    const element = create({
      records: RECORDS,
      keyField: "Id",
      tableLabel: "Shipments",
      hideCheckboxColumn: true
    });
    const table = query(element, "lightning-datatable");
    expect(table.columns).toEqual(COLUMNS);
    expect(table.keyField).toBe("Id");
    expect(table.hideCheckboxColumn).toBe(true);
    expect(table.data.map((row) => row.Id)).toEqual(["a01", "a02", "a03"]);
    expect(query(element, ".elogix-empty")).toBeNull();
  });

  it("sorts text naturally and numbers numerically, blanks last, without changing the input", async () => {
    const element = create({ records: RECORDS });
    const table = query(element, "lightning-datatable");

    table.dispatchEvent(
      new CustomEvent("sort", {
        detail: { fieldName: "Name", sortDirection: "asc" }
      })
    );
    await Promise.resolve();
    expect(table.data.map((row) => row.Name)).toEqual([
      "SHP-00001",
      "SHP-00002",
      "SHP-00010"
    ]);
    expect(table.sortedBy).toBe("Name");

    table.dispatchEvent(
      new CustomEvent("sort", {
        detail: { fieldName: "Weight__c", sortDirection: "desc" }
      })
    );
    await Promise.resolve();
    expect(table.data.map((row) => row.Id)).toEqual(["a01", "a03", "a02"]);
    expect(table.sortedDirection).toBe("desc");
    expect(RECORDS.map((row) => row.Id)).toEqual(["a01", "a02", "a03"]);
  });

  it("re-dispatches row actions and row selection", () => {
    const element = create({ records: RECORDS });
    const table = query(element, "lightning-datatable");
    const onAction = jest.fn();
    const onSelection = jest.fn();
    element.addEventListener("rowaction", onAction);
    element.addEventListener("rowselection", onSelection);

    table.dispatchEvent(
      new CustomEvent("rowaction", {
        detail: { action: { name: "view" }, row: RECORDS[0] }
      })
    );
    table.dispatchEvent(
      new CustomEvent("rowselection", {
        detail: { selectedRows: [RECORDS[2]] }
      })
    );

    expect(onAction.mock.calls[0][0].detail).toEqual({
      action: { name: "view" },
      row: RECORDS[0]
    });
    expect(onSelection.mock.calls[0][0].detail).toEqual({
      selectedRows: [RECORDS[2]]
    });
  });
});
