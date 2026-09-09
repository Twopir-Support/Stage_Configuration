/**
 * Works out which tracking fields are missing and queues them for creation.
 */
public with sharing class TPC_StageFieldGeneratorService {

    /**
     * Ceiling on fields queued in one invocation, to bound heap and CPU while
     * building definitions. The queueable chains through them in callout-sized
     * batches, and any remainder is reported back to the caller.
     *
     * The previous implementation capped CONFIGURATION RECORDS at 200 with no
     * ORDER BY and no scheduled follow-up, so configuration 201 was never
     * reached. Capping fields instead converges: every run creates whatever is
     * missing from the earliest configurations, so the next run gets further.
     */
    @TestVisible
    private static Integer maxFieldsPerRun = 400;

    private static final Integer CONFIG_QUERY_LIMIT = 2000;

    public static TPC_StageConfigurationWrapper.GenerationSummary generateFields() {

        TPC_StageConfigurationWrapper.GenerationSummary summary =
            new TPC_StageConfigurationWrapper.GenerationSummary();

        if (!Schema.sObjectType.Stage_Configuration__c.isAccessible()) {
            throw new TPC_StageFieldGeneratorException(
                'You do not have access to stage configuration records.'
            );
        }

        List<Stage_Configuration__c> configs = [
            SELECT Id, Object_API_Name__c, Stage_Field_API__c, Stage_Value__c
            FROM Stage_Configuration__c
            WHERE Active__c = TRUE
              AND Auto_Create_Field__c = TRUE
              AND Stage_Value__c != NULL
            WITH USER_MODE
            ORDER BY CreatedDate ASC, Id ASC
            LIMIT :CONFIG_QUERY_LIMIT
        ];

        if (configs.isEmpty()) {
            return summary;
        }

        Map<String, Schema.SObjectType> globalDescribe = Schema.getGlobalDescribe();

        List<TPC_FieldDefinition> queued = new List<TPC_FieldDefinition>();

        // Guards two field names colliding within this run — the existing-field
        // check only sees what previous runs created.
        Set<String> claimed = new Set<String>();

        for (Stage_Configuration__c config : configs) {

            if (queued.size() >= maxFieldsPerRun) {
                summary.remaining++;
                continue;
            }

            try {

                List<TPC_FieldDefinition> missing = missingFieldsFor(
                    config,
                    globalDescribe,
                    claimed
                );

                if (missing == null) {
                    summary.skipped++;
                    continue;
                }

                queued.addAll(missing);

            } catch (Exception ex) {

                summary.skipped++;

                TPC_ErrorLogger.log(
                    'TPC_StageFieldGeneratorService',
                    'generateFields',
                    ex,
                    config.Id
                );
            }
        }

        summary.queued = queued.size();

        if (queued.isEmpty()) {
            return summary;
        }

        // Only one child job may be enqueued from inside a Queueable. Calling
        // this from an async context is a programming error rather than a
        // runtime condition, so it reports rather than silently dropping work.
        if (System.isQueueable()) {
            throw new TPC_StageFieldGeneratorException(
                'Field generation cannot be started from an asynchronous context.'
            );
        }

        System.enqueueJob(new TPC_StageFieldCreationQueueable(queued));

        return summary;
    }

    /**
     * The tracking fields this configuration needs that do not yet exist.
     * Returns null when the configuration cannot be acted on at all.
     */
    private static List<TPC_FieldDefinition> missingFieldsFor(
        Stage_Configuration__c config,
        Map<String, Schema.SObjectType> globalDescribe,
        Set<String> claimed
    ) {
        Schema.SObjectType objType = globalDescribe.get(config.Object_API_Name__c);

        if (objType == null) {
            return null;
        }

        Map<String, Schema.SObjectField> fieldMap =
            objType.getDescribe().fields.getMap();

        if (!fieldMap.containsKey(config.Stage_Field_API__c)) {
            return null;
        }

        String stageLabel = matchedPicklistLabel(
            fieldMap.get(config.Stage_Field_API__c),
            config.Stage_Value__c
        );

        if (stageLabel == null) {
            // The configured value is not an active entry on the picklist right
            // now — renamed, deactivated, or a typo. Skip rather than guess.
            return null;
        }

        if (!TPC_StageFieldNames.isUsableStage(stageLabel)) {
            return null;
        }

        List<TPC_FieldDefinition> missing = new List<TPC_FieldDefinition>();

        addIfMissing(missing, fieldMap, claimed, config.Object_API_Name__c, stageLabel,
            TPC_StageFieldNames.ENTERED_PREFIX, 'Date entered ', 'DateTime');

        addIfMissing(missing, fieldMap, claimed, config.Object_API_Name__c, stageLabel,
            TPC_StageFieldNames.EXITED_PREFIX, 'Date exited ', 'DateTime');

        addIfMissing(missing, fieldMap, claimed, config.Object_API_Name__c, stageLabel,
            TPC_StageFieldNames.LATEST_PREFIX, 'Latest time in ', 'Number');

        addIfMissing(missing, fieldMap, claimed, config.Object_API_Name__c, stageLabel,
            TPC_StageFieldNames.CUMULATIVE_PREFIX, 'Cumulative time in ', 'Number');

        return missing;
    }

    private static void addIfMissing(
        List<TPC_FieldDefinition> missing,
        Map<String, Schema.SObjectField> fieldMap,
        Set<String> claimed,
        String objectApiName,
        String stageLabel,
        String prefix,
        String labelPrefix,
        String fieldType
    ) {
        String fieldApiName = TPC_StageFieldNames.fieldName(prefix, stageLabel);

        if (String.isBlank(fieldApiName)) {
            return;
        }

        // Schema field map keys are always lowercase.
        if (fieldMap.containsKey(fieldApiName.toLowerCase())) {
            return;
        }

        String claimKey = (objectApiName + '.' + fieldApiName).toLowerCase();

        if (claimed.contains(claimKey)) {
            return;
        }

        claimed.add(claimKey);

        missing.add(
            new TPC_FieldDefinition(
                objectApiName,
                fieldApiName,
                buildLabel(labelPrefix, stageLabel),
                fieldType
            )
        );
    }

    /** Field labels are capped at 40 characters, as are API names. */
    @TestVisible
    private static String buildLabel(String labelPrefix, String stageLabel) {

        String label = labelPrefix + '"' + stageLabel + '"';

        if (label.length() <= 40) {
            return label;
        }

        return label.substring(0, 39) + '"';
    }

    /**
     * The active picklist entry matching the configured value, compared without
     * case sensitivity. Returns null when there is no active match.
     */
    private static String matchedPicklistLabel(
        Schema.SObjectField stageField,
        String configuredValue
    ) {
        if (String.isBlank(configuredValue)) {
            return null;
        }

        String target = configuredValue.trim().toLowerCase();

        for (Schema.PicklistEntry entry : stageField.getDescribe().getPicklistValues()) {

            if (entry.isActive() && entry.getLabel().toLowerCase() == target) {
                return entry.getLabel();
            }
        }

        return null;
    }

    public class TPC_StageFieldGeneratorException extends Exception {
    }
}
