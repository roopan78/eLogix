/**
 * A business rule rejected the input. Services normally report these per record through
 * ServiceResult; throw this only when the whole operation must stop.
 */
public class ValidationException extends ELogixException {
}
