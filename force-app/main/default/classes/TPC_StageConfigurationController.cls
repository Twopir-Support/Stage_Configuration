/**
 * Server side of the Stage Tracking setup component.
 *
 * Every method is an authenticated endpoint reachable by any user of the org,
 * whether or not they can see the component, so each one checks the
 * Manage_Stage_Tracking custom permission before doing anything. The previous
 * version had no such check: any user could enumerate every object in the org,
 * write configuration, delete it, or start a metadata deployment.
 */
public with sharing class TPC_StageConfigurationController {

    private static final String MANAGE_PERMISSION = 'Manage_Stage_Tracking';

    // ------------------------------------------------------------- metadata

    /**
     * The objects this package can track.
     *
     * Fixed at build time and read from Stage_Trigger_Control__mdt, because
     * tracking requires a packaged Apex trigger and subscriber orgs cannot be
     * given new Apex. Offering the admin every queryable object in the org — as
     * the previous version did — invited configuration that could never fire.
     */
    @AuraEnabled(cacheable=true)
    public static List<TPC_StageConfigurationWrapper.Option> getObjects() {

        requireManagePermission();

        List<TPC_StageConfigurationWrapper.Option> options =
            new List<TPC_StageConfigurationWrapper.Option>();

        try {

            Map<String, Schema.SObjectType> globalDescribe = Schema.getGlobalDescribe();

            Map<String, String> labelsByApiName = new Map<String, String>();

            for (Stage_Trigger_Control__mdt control : Stage_Trigger_Control__mdt.getAll().values()) {

                String apiName = control.Object_API_Name__c;

                if (String.isBlank(apiName) || !globalDescribe.containsKey(apiName)) {
                    continue;
                }

                Schema.DescribeSObjectResult describe = globalDescribe.get(apiName).getDescribe();

                if (!describe.isQueryable() || !describe.isUpdateable()) {
                    continue;
                }

                labelsByApiName.put(apiName, describe.getLabel());
            }

            // Sort on a composite key so two objects sharing a label keep stable,
            // distinct entries — and so the map is never mutated mid-iteration.
            List<String> sortKeys = new List<String>();
            Map<String, String> apiNameBySortKey = new Map<String, String>();

            for (String apiName : labelsByApiName.keySet()) {

                String sortKey = labelsByApiName.get(apiName) + '\u0000' + apiName;

                sortKeys.add(sortKey);
                apiNameBySortKey.put(sortKey, apiName);
            }

            sortKeys.sort();

            for (String sortKey : sortKeys) {

                String apiName = apiNameBySortKey.get(sortKey);

                options.add(
                    new TPC_StageConfigurationWrapper.Option(
                        labelsByApiName.get(apiName),
                        apiName
                    )
                );
            }

            return options;

        } catch (Exception e) {

            TPC_ErrorLogger.log('TPC_StageConfigurationController', 'getObjects', e, null);

            throw new AuraHandledException('Unable to load the list of objects.');
        }
    }

    @AuraEnabled(cacheable=true)
    public static List<TPC_StageConfigurationWrapper.Option> getPicklistFields(String objectApi) {

        requireManagePermission();

        Schema.SObjectType objType = validatedObjectType(objectApi);

        List<TPC_StageConfigurationWrapper.Option> options =
            new List<TPC_StageConfigurationWrapper.Option>();

        try {

            Map<String, Schema.SObjectField> fields = objType.getDescribe().fields.getMap();

            for (String apiName : fields.keySet()) {

                Schema.DescribeFieldResult describe = fields.get(apiName).getDescribe();

                if (describe.getType() != Schema.DisplayType.Picklist) {
                    continue;
                }

                if (!describe.isAccessible()) {
                    continue;
                }

                options.add(
                    new TPC_StageConfigurationWrapper.Option(
                        describe.getLabel(),
                        describe.getName()
                    )
                );
            }

            return options;

        } catch (Exception e) {

            TPC_ErrorLogger.log(
                'TPC_StageConfigurationController', 'getPicklistFields', e, null
            );

            throw new AuraHandledException('Unable to load picklist fields.');
        }
    }

    @AuraEnabled(cacheable=true)
    public static List<TPC_StageConfigurationWrapper.Option> getPicklistValues(
        String objectApi,
        String fieldApi
    ) {
        requireManagePermission();

        Schema.SObjectType objType = validatedObjectType(objectApi);

        Map<String, Schema.SObjectField> fields = objType.getDescribe().fields.getMap();

        if (String.isBlank(fieldApi) || !fields.containsKey(fieldApi)) {
            throw new AuraHandledException('That field does not exist on the selected object.');
        }

        Schema.DescribeFieldResult fieldDescribe = fields.get(fieldApi).getDescribe();

        if (fieldDescribe.getType() != Schema.DisplayType.Picklist) {
            throw new AuraHandledException('That field is not a picklist.');
        }

        try {

            List<TPC_StageConfigurationWrapper.Option> options =
                new List<TPC_StageConfigurationWrapper.Option>();

            for (Schema.PicklistEntry entry : fieldDescribe.getPicklistValues()) {

                if (entry.isActive()) {
                    options.add(
                        new TPC_StageConfigurationWrapper.Option(
                            entry.getLabel(),
                            entry.getValue()
                        )
                    );
                }
            }

            return options;

        } catch (Exception e) {

            TPC_ErrorLogger.log(
                'TPC_StageConfigurationController', 'getPicklistValues', e, null
            );

            throw new AuraHandledException('Unable to load picklist values.');
        }
    }

    // -------------------------------------------------------- configuration

    @AuraEnabled(cacheable=true)
    public static List<TPC_StageConfigurationWrapper.ConfigurationRow> getConfigurations() {

        requireManagePermission();

        try {

            Map<String, Schema.SObjectType> globalDescribe = Schema.getGlobalDescribe();

            List<TPC_StageConfigurationWrapper.ConfigurationRow> rows =
                new List<TPC_StageConfigurationWrapper.ConfigurationRow>();

            for (Stage_Configuration__c c : [
                SELECT Id, Object_API_Name__c, Stage_Field_API__c, Stage_Value__c,
                       Active__c, Auto_Create_Field__c, Do_Not_Prefill__c
                FROM Stage_Configuration__c
                WITH USER_MODE
                ORDER BY Object_API_Name__c, Stage_Field_API__c, Stage_Value__c
            ]) {

                TPC_StageConfigurationWrapper.ConfigurationRow row =
                    new TPC_StageConfigurationWrapper.ConfigurationRow();

                row.id = c.Id;
                row.objectApiName = c.Object_API_Name__c;
                row.stageFieldApiName = c.Stage_Field_API__c;
                row.stageValue = c.Stage_Value__c;
                row.active = c.Active__c;
                row.autoCreateField = c.Auto_Create_Field__c;
                row.doNotPrefill = c.Do_Not_Prefill__c;

                row.objectLabel = globalDescribe.containsKey(c.Object_API_Name__c)
                    ? globalDescribe.get(c.Object_API_Name__c).getDescribe().getLabel()
                    : c.Object_API_Name__c;

                rows.add(row);
            }

            return rows;

        } catch (Exception e) {

            TPC_ErrorLogger.log(
                'TPC_StageConfigurationController', 'getConfigurations', e, null
            );

            throw new AuraHandledException('Unable to load configurations.');
        }
    }

    @AuraEnabled
    public static Id saveConfiguration(
        Id recordId,
        String objectApi,
        String fieldApi,
        String stageValue,
        Boolean active,
        Boolean autoCreate
    ) {
        requireManagePermission();

        if (recordId == null && !Schema.sObjectType.Stage_Configuration__c.isCreateable()) {
            throw new AuraHandledException('You do not have permission to create configurations.');
        }

        if (recordId != null && !Schema.sObjectType.Stage_Configuration__c.isUpdateable()) {
            throw new AuraHandledException('You do not have permission to edit configurations.');
        }

        validatedObjectType(objectApi);

        if (String.isBlank(fieldApi)) {
            throw new AuraHandledException('Select a picklist field.');
        }

        if (String.isBlank(stageValue)) {
            throw new AuraHandledException('Select a picklist value.');
        }

        try {

            List<Stage_Configuration__c> duplicates = [
                SELECT Id
                FROM Stage_Configuration__c
                WHERE Object_API_Name__c = :objectApi
                  AND Stage_Field_API__c = :fieldApi
                  AND Stage_Value__c = :stageValue
                  AND Id != :recordId
                WITH USER_MODE
                LIMIT 1
            ];

            if (!duplicates.isEmpty()) {
                throw new AuraHandledException(
                    'That object, field and value is already configured.'
                );
            }

            Stage_Configuration__c config;

            if (recordId == null) {
                config = new Stage_Configuration__c();
            } else {
                config = [
                    SELECT Id
                    FROM Stage_Configuration__c
                    WHERE Id = :recordId
                    WITH USER_MODE
                    LIMIT 1
                ];
            }

            config.Object_API_Name__c = objectApi;
            config.Stage_Field_API__c = fieldApi;
            config.Stage_Value__c = stageValue;
            config.Active__c = active == true;
            config.Auto_Create_Field__c = autoCreate == true;

            upsert as user config;

            return config.Id;

        } catch (AuraHandledException e) {

            throw e;

        } catch (Exception e) {

            TPC_ErrorLogger.log(
                'TPC_StageConfigurationController', 'saveConfiguration', e, recordId
            );

            throw new AuraHandledException('Unable to save the configuration.');
        }
    }

    @AuraEnabled
    public static void deleteConfiguration(Id recordId) {

        requireManagePermission();

        if (recordId == null) {
            throw new AuraHandledException('Configuration Id is required.');
        }

        if (!Schema.sObjectType.Stage_Configuration__c.isDeletable()) {
            throw new AuraHandledException('You do not have permission to delete configurations.');
        }

        try {

            List<Stage_Configuration__c> toDelete = [
                SELECT Id
                FROM Stage_Configuration__c
                WHERE Id = :recordId
                WITH USER_MODE
                LIMIT 1
            ];

            if (!toDelete.isEmpty()) {
                delete as user toDelete;
            }

        } catch (Exception e) {

            TPC_ErrorLogger.log(
                'TPC_StageConfigurationController', 'deleteConfiguration', e, recordId
            );

            throw new AuraHandledException('Unable to delete the configuration.');
        }
    }

    /**
     * Applies inline "Do Not Prefill" edits in one call.
     *
     * Takes the whole set of edited rows rather than one record at a time — the
     * component previously issued one Apex round trip per edited row, which
     * scaled with how much the admin changed before saving.
     */
    @AuraEnabled
    public static void updateDoNotPrefill(Map<String, Boolean> valuesByRecordId) {

        requireManagePermission();

        if (valuesByRecordId == null || valuesByRecordId.isEmpty()) {
            return;
        }

        if (!Schema.sObjectType.Stage_Configuration__c.isUpdateable()) {
            throw new AuraHandledException('You do not have permission to edit configurations.');
        }

        try {

            List<Stage_Configuration__c> updates = new List<Stage_Configuration__c>();

            for (String recordId : valuesByRecordId.keySet()) {

                if (String.isBlank(recordId)) {
                    continue;
                }

                updates.add(
                    new Stage_Configuration__c(
                        Id = (Id) recordId,
                        Do_Not_Prefill__c = valuesByRecordId.get(recordId) == true
                    )
                );
            }

            if (!updates.isEmpty()) {
                update as user updates;
            }

        } catch (Exception e) {

            TPC_ErrorLogger.log(
                'TPC_StageConfigurationController', 'updateDoNotPrefill', e, null
            );

            throw new AuraHandledException('Unable to update the configurations.');
        }
    }

    @AuraEnabled
    public static TPC_StageConfigurationWrapper.GenerationSummary generateFields() {

        requireManagePermission();

        try {

            return TPC_StageFieldGeneratorService.generateFields();

        } catch (TPC_StageFieldGeneratorService.TPC_StageFieldGeneratorException e) {

            throw new AuraHandledException(e.getMessage());

        } catch (Exception e) {

            TPC_ErrorLogger.log(
                'TPC_StageConfigurationController', 'generateFields', e, null
            );

            throw new AuraHandledException('Unable to generate tracking fields.');
        }
    }

    // ------------------------------------------------------------ internals

    private static void requireManagePermission() {

        if (!FeatureManagement.checkPermission(MANAGE_PERMISSION)) {
            throw new AuraHandledException(
                'You need the Stage Tracking Administrator permission set to manage stage tracking.'
            );
        }
    }

    private static Schema.SObjectType validatedObjectType(String objectApi) {

        if (String.isBlank(objectApi)) {
            throw new AuraHandledException('Select an object.');
        }

        Schema.SObjectType objType = Schema.getGlobalDescribe().get(objectApi);

        if (objType == null) {
            throw new AuraHandledException('That object does not exist in this org.');
        }

        return objType;
    }
}
