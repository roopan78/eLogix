/**
 * Centralized mapping of exceptions to user-safe messages.
 *
 * eLogix exceptions already carry a Custom Label message and are returned as they are. Any other
 * exception is logged and replaced by a generic message that includes the request correlation id,
 * so support can find the log without exposing internal details to the user.
 */
public inherited sharing class ExceptionHandler {
    public static String toUserMessage(Exception e, String context) {
        Logger.error(context, 'Operation failed.', e);
        if (e instanceof ELogixException) {
            return e.getMessage();
        }
        return String.format(Label.eLogix_Unexpected_Error, new List<Object>{ Logger.correlationId() });
    }
}
