/**
 * Durable error logging via a Platform Event.
 *
 * The previous implementation inserted a custom-object row. Because it was
 * called from catch blocks that then re-threw, the insert rolled back with the
 * transaction it was recording — so the failures most worth investigating left
 * no trace at all. The Package_Error__e event is configured to publish
 * immediately, which survives rollback.
 */
public inherited sharing class TPC_ErrorLogger {

    private static final Integer TEXT_LIMIT = 255;
    private static final Integer LONG_TEXT_LIMIT = 32768;

    /**
     * The most recent event built, so tests can assert on what was reported.
     * Platform events cannot be queried back inside a test transaction.
     */
    @TestVisible
    private static Package_Error__e lastEvent;

    public static void log(String className, String methodName, Exception e, Id recordId) {

        if (e == null) {
            return;
        }

        log(
            className,
            methodName,
            e.getTypeName(),
            e.getMessage(),
            e.getStackTraceString(),
            recordId
        );
    }

    public static void log(String className, String methodName, String message, Id recordId) {
        log(className, methodName, 'Handled', message, null, recordId);
    }

    private static void log(
        String className,
        String methodName,
        String exceptionType,
        String message,
        String stackTrace,
        Id recordId
    ) {
        try {

            Package_Error__e evt = new Package_Error__e(
                Class_Name__c = truncate(className, TEXT_LIMIT),
                Method_Name__c = truncate(methodName, TEXT_LIMIT),
                Exception_Type__c = truncate(exceptionType, TEXT_LIMIT),
                Error_Message__c = truncate(message, LONG_TEXT_LIMIT),
                Stack_Trace__c = truncate(stackTrace, LONG_TEXT_LIMIT),
                Record_Id__c = recordId == null ? null : String.valueOf(recordId),
                User_Id__c = UserInfo.getUserId()
            );

            lastEvent = evt;

            Database.SaveResult result = EventBus.publish(evt);

            if (result != null && !result.isSuccess()) {
                for (Database.Error err : result.getErrors()) {
                    System.debug(
                        LoggingLevel.ERROR,
                        'Stage tracking error event rejected: ' +
                        err.getStatusCode() + ' ' + err.getMessage()
                    );
                }
            }

        } catch (Exception loggingFailure) {

            // Logging must never mask the error it was called to record.
            System.debug(
                LoggingLevel.ERROR,
                'Stage tracking error logging failed: ' + loggingFailure.getMessage()
            );
        }
    }

    private static String truncate(String value, Integer maxLength) {

        if (String.isBlank(value)) {
            return value;
        }

        return value.length() <= maxLength ? value : value.substring(0, maxLength);
    }
}
