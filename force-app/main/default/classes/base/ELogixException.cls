/**
 * Base class for eLogix business exceptions.
 *
 * The message is meant for end users and comes from a Custom Label. `code` is a stable,
 * machine-readable reason code for callers, tests and logs.
 */
public virtual class ELogixException extends Exception {
    public String code { get; private set; }

    public ELogixException withCode(String code) {
        this.code = code;
        return this;
    }
}
