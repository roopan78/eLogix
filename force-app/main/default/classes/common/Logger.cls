/**
 * Structured debug logging for eLogix.
 *
 * Every line carries the request correlation id and a context (usually Class.method), so one
 * transaction can be followed across classes in the debug log.
 *
 * Logging rules (CLAUDE.md rule 18): log record Ids, reason codes, counts and correlation ids
 * only. Never log field values, payloads, names, phone numbers or amounts. For exceptions, only
 * the type, eLogix reason code and stack trace are logged, because platform exception messages
 * can contain record data.
 *
 * Phase 2 writes to the debug log only (architecture decision D4); there is no persisted
 * application log object.
 */
public inherited sharing class Logger {
    private static final String PREFIX = '[eLogix]';

    public static void debug(String context, String message) {
        write(LoggingLevel.DEBUG, context, message);
    }

    public static void info(String context, String message) {
        write(LoggingLevel.INFO, context, message);
    }

    public static void warn(String context, String message) {
        write(LoggingLevel.WARN, context, message);
    }

    public static void error(String context, String message, Exception e) {
        String detail = message;
        if (e != null) {
            detail += ' | ' + e.getTypeName();
            if (e instanceof ELogixException) {
                detail += ' code=' + ((ELogixException) e).code;
            }
            detail += ' | ' + e.getStackTraceString();
        }
        write(LoggingLevel.ERROR, context, detail);
    }

    /** Identifier of the current request, shown to users in unexpected-error messages. */
    public static String correlationId() {
        return Request.getCurrent().getRequestId();
    }

    @TestVisible
    private static String format(String context, String message) {
        return PREFIX + '[' + correlationId() + '][' + context + '] ' + message;
    }

    private static void write(LoggingLevel level, String context, String message) {
        System.debug(level, format(context, message));
    }
}
