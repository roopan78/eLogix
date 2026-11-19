@IsTest
private class ExceptionHandlerTest {
    @IsTest
    static void eLogixExceptionsKeepTheirLabelMessage() {
        ELogixException e = new ConfigurationException(Label.eLogix_Access_Denied).withCode('X');
        Assert.areEqual(Label.eLogix_Access_Denied, ExceptionHandler.toUserMessage(e, 'ExceptionHandlerTest'));
    }

    @IsTest
    static void otherExceptionsBecomeAGenericMessageWithReference() {
        String message;
        try {
            Integer zero = 0;
            Integer result = 1 / zero;
        } catch (Exception e) {
            message = ExceptionHandler.toUserMessage(e, 'ExceptionHandlerTest');
        }
        Assert.areEqual(String.format(Label.eLogix_Unexpected_Error, new List<Object>{ Logger.correlationId() }), message);
        Assert.isFalse(message.contains('Divide'), 'Internal details are not shown to users.');
    }

    @IsTest
    static void exceptionSubtypesCarryCodes() {
        Assert.areEqual('V', new ValidationException('Invalid.').withCode('V').code);
        Assert.areEqual('A', new AuthorizationException('Denied.').withCode('A').code);
        Assert.isNull(new ELogixException('No code.').code);
    }
}
