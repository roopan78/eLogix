@IsTest
private class LoggerTest {
    @IsTest
    static void linesCarryCorrelationIdAndContext() {
        String line = Logger.format('LoggerTest.context', 'message');
        Assert.isTrue(String.isNotBlank(Logger.correlationId()));
        Assert.areEqual('[eLogix][' + Logger.correlationId() + '][LoggerTest.context] message', line);
    }

    @IsTest
    static void everyLevelLogsWithoutThrowing() {
        Logger.debug('LoggerTest', 'debug');
        Logger.info('LoggerTest', 'info');
        Logger.warn('LoggerTest', 'warn');
        Logger.error('LoggerTest', 'error without exception', null);
        Logger.error('LoggerTest', 'error with eLogix exception', new ConfigurationException('Missing.').withCode('CODE'));
        Logger.error('LoggerTest', 'error with platform exception', new DmlException('Platform.'));
        Assert.isTrue(true, 'Logging must never throw.');
    }
}
