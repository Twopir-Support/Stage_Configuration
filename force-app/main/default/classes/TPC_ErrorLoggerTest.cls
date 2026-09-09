/** Error telemetry is built correctly and never masks the error it records. */
@IsTest
private class TPC_ErrorLoggerTest {

    @IsTest
    static void log_capturesExceptionDetail() {

        Test.startTest();
        try {
            throw new IllegalArgumentException('Something specific went wrong');
        } catch (Exception e) {
            TPC_ErrorLogger.log('TPC_SomeClass', 'someMethod', e, null);
        }
        Test.stopTest();

        Package_Error__e evt = TPC_ErrorLogger.lastEvent;

        Assert.isNotNull(evt, 'An event should have been built');
        Assert.areEqual('TPC_SomeClass', evt.Class_Name__c, 'Class name should be recorded');
        Assert.areEqual('someMethod', evt.Method_Name__c, 'Method name should be recorded');
        Assert.areEqual(
            'System.IllegalArgumentException',
            evt.Exception_Type__c,
            'Exception type should be recorded'
        );
        Assert.areEqual(
            'Something specific went wrong',
            evt.Error_Message__c,
            'The message should survive intact'
        );
        Assert.areEqual(
            UserInfo.getUserId(),
            evt.User_Id__c,
            'The acting user should be recorded'
        );
    }

    @IsTest
    static void log_truncatesOverlongValues() {

        String longMessage = 'x'.repeat(300);

        Test.startTest();
        TPC_ErrorLogger.log('C'.repeat(300), longMessage, longMessage, null);
        Test.stopTest();

        Package_Error__e evt = TPC_ErrorLogger.lastEvent;

        Assert.areEqual(
            255,
            evt.Class_Name__c.length(),
            'Text fields should be truncated to their storage limit'
        );
    }

    @IsTest
    static void log_toleratesNullException() {

        Test.startTest();
        TPC_ErrorLogger.log('TPC_SomeClass', 'someMethod', (Exception) null, null);
        Test.stopTest();

        Assert.isTrue(true, 'Logging a null exception should not throw');
    }

    @IsTest
    static void log_recordsTheRelatedRecordId() {

        Id fakeId = '001000000000000AAA';

        Test.startTest();
        TPC_ErrorLogger.log('TPC_SomeClass', 'someMethod', 'A handled problem', fakeId);
        Test.stopTest();

        Assert.areEqual(
            String.valueOf(fakeId),
            TPC_ErrorLogger.lastEvent.Record_Id__c,
            'The related record should be recorded so the error can be traced'
        );
    }
}
