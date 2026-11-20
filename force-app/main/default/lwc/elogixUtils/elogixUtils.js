/**
 * Shared helpers for eLogix LWCs: error reduction, toasts and ServiceResult handling.
 * A service module (no template). Business rules stay in Apex; these helpers only format results.
 */
import { ShowToastEvent } from "lightning/platformShowToastEvent";
import LABEL_UNEXPECTED_ERROR from "@salesforce/label/c.eLogix_UI_Unexpected_Error";
import LABEL_ERROR_TITLE from "@salesforce/label/c.eLogix_UI_Error_Title";
import LABEL_SUCCESS_TITLE from "@salesforce/label/c.eLogix_UI_Success_Title";

/**
 * Turns any LWC error shape into a list of user-facing messages:
 * AuraHandledException and UI API errors ({ body: { message | pageErrors | fieldErrors | output } }),
 * JavaScript errors, plain strings and arrays of these. Duplicates and blanks are dropped.
 */
export function reduceErrors(errors) {
  const list = Array.isArray(errors) ? errors : [errors];
  const messages = list
    .filter((error) => !!error)
    .flatMap((error) => {
      if (typeof error === "string") {
        return [error];
      }
      const body = error.body;
      if (Array.isArray(body)) {
        return body.map((entry) => entry && entry.message);
      }
      if (body) {
        const collected = [];
        const pageErrors =
          (body.output && body.output.errors) || body.pageErrors || [];
        pageErrors.forEach((entry) => collected.push(entry.message));
        const fieldErrors =
          (body.output && body.output.fieldErrors) || body.fieldErrors || {};
        Object.values(fieldErrors).forEach((entries) =>
          (entries || []).forEach((entry) => collected.push(entry.message))
        );
        if (body.message) {
          collected.push(body.message);
        }
        return collected;
      }
      if (error.message) {
        return [error.message];
      }
      if (error.statusText) {
        return [error.statusText];
      }
      return [];
    })
    .filter(
      (message) => typeof message === "string" && message.trim().length > 0
    );
  return [...new Set(messages)];
}

/** One message for display: the reduced messages joined, or the generic label when nothing is usable. */
export function errorMessage(error) {
  const messages = reduceErrors(error);
  return messages.length ? messages.join(" ") : LABEL_UNEXPECTED_ERROR;
}

/** The error messages of an Apex ServiceResult ({ isSuccess, errors: [{ code, message }], recordIds }). */
export function serviceResultMessages(result) {
  if (!result || !Array.isArray(result.errors)) {
    return [];
  }
  return [
    ...new Set(
      result.errors
        .map((error) => error && error.message)
        .filter((message) => !!message)
    )
  ];
}

/** Dispatches a toast from the given component. */
export function showToast(
  component,
  { title, message, variant = "info", mode = "dismissible" }
) {
  component.dispatchEvent(
    new ShowToastEvent({ title, message, variant, mode })
  );
}

export function showSuccess(component, message, title = LABEL_SUCCESS_TITLE) {
  showToast(component, { title, message, variant: "success" });
}

/** Shows any error shape as a sticky error toast. */
export function showError(component, error, title = LABEL_ERROR_TITLE) {
  showToast(component, {
    title,
    message: errorMessage(error),
    variant: "error",
    mode: "sticky"
  });
}

/**
 * Toasts the outcome of an Apex ServiceResult and returns true when it succeeded.
 * A failed result shows the service's own messages; a missing result counts as a failure.
 */
export function handleServiceResult(component, result, successMessage) {
  if (result && result.isSuccess) {
    if (successMessage) {
      showSuccess(component, successMessage);
    }
    return true;
  }
  const messages = serviceResultMessages(result);
  showError(component, messages.length ? messages : null);
  return false;
}

/** Fills {0}, {1}... placeholders of a Custom Label, like String.format in Apex. */
export function formatLabel(template, ...values) {
  return values.reduce(
    (text, value, index) =>
      text
        .split(`{${index}}`)
        .join(value === undefined || value === null ? "" : String(value)),
    template || ""
  );
}
