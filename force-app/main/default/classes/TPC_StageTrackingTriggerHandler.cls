/**
 * Entry point for the packaged stage-tracking triggers.
 *
 * One trigger per supported object, each doing nothing but calling handle().
 * Objects are fixed at package build time: subscriber orgs cannot be given new
 * Apex triggers, because Salesforce does not permit Apex to be created in a
 * production org through any interface. Adding an object is a package release.
 */
public inherited sharing class TPC_StageTrackingTriggerHandler {

    private static final String BYPASS_PERMISSION = 'Bypass_Stage_Tracking';

    public static void handleAfterUpdate(
        List<SObject> newRecords,
        Map<Id, SObject> oldMap,
        String objectApiName
    ) {
        if (newRecords == null || newRecords.isEmpty() ||
            oldMap == null || oldMap.isEmpty() ||
            String.isBlank(objectApiName)) {
            return;
        }

        try {

            if (isBypassed() || !isEnabled(objectApiName)) {
                return;
            }

            Set<String> stageFields = trackedStageFields(objectApiName);

            if (stageFields.isEmpty()) {
                return;
            }

            Schema.SObjectType objType = Schema.getGlobalDescribe().get(objectApiName);

            if (objType == null) {
                return;
            }

            Map<String, Schema.SObjectField> fieldMap =
                objType.getDescribe().fields.getMap();

            List<TPC_StageTrackingRequest> requests =
                new List<TPC_StageTrackingRequest>();

            for (String stageField : stageFields) {

                // A configured field may have been deleted or renamed in the
                // subscriber org since the configuration was saved.
                if (!fieldMap.containsKey(stageField)) {
                    continue;
                }

                for (SObject newRecord : newRecords) {

                    Id recordId = (Id) newRecord.get('Id');
                    SObject oldRecord = oldMap.get(recordId);

                    if (oldRecord == null) {
                        continue;
                    }

                    String oldStage = (String) oldRecord.get(stageField);
                    String newStage = (String) newRecord.get(stageField);

                    // The field-change check is also the recursion guard. The
                    // tracking service updates these same records, which
                    // re-enters this trigger; on that pass the stage field is
                    // unchanged, so no work is queued and the chain stops.
                    // A static Boolean guard is deliberately not used — it would
                    // silently skip records 201+ of a bulk load.
                    if (oldStage == newStage) {
                        continue;
                    }

                    requests.add(
                        new TPC_StageTrackingRequest(
                            recordId,
                            objectApiName,
                            stageField,
                            oldStage,
                            newStage
                        )
                    );
                }
            }

            if (!requests.isEmpty()) {
                TPC_StageTrackingService.recordTransitions(requests);
            }

        } catch (Exception ex) {

            TPC_ErrorLogger.log(
                'TPC_StageTrackingTriggerHandler',
                'handleAfterUpdate[' + objectApiName + ']',
                ex,
                null
            );

            throw ex;
        }
    }

    /**
     * The distinct picklist fields configured for this object.
     *
     * There is one configuration record per tracked stage VALUE, so an object
     * with eight tracked stages yields eight rows naming the same field. Reducing
     * to distinct fields here is what stops the handler emitting eight identical
     * requests per record.
     */
    private static Set<String> trackedStageFields(String objectApiName) {

        Set<String> stageFields = new Set<String>();

        for (Stage_Configuration__c cfg : [
            SELECT Stage_Field_API__c
            FROM Stage_Configuration__c
            WHERE Object_API_Name__c = :objectApiName
              AND Active__c = TRUE
              AND Stage_Field_API__c != NULL
            WITH SYSTEM_MODE
        ]) {
            stageFields.add(cfg.Stage_Field_API__c);
        }

        return stageFields;
    }

    /**
     * Per-object kill switch, held in Custom Metadata so an admin can disable
     * tracking for one object without a deploy.
     *
     * A missing control record means enabled. The package ships a record for
     * every supported object, so absence indicates the record was removed rather
     * than an intent to disable — and an admin who wants tracking off unchecks
     * Is_Active__c, which is the documented route.
     */
    @TestVisible
    private static Boolean isEnabled(String objectApiName) {

        for (Stage_Trigger_Control__mdt control : Stage_Trigger_Control__mdt.getAll().values()) {

            if (objectApiName.equalsIgnoreCase(control.Object_API_Name__c)) {
                return control.Is_Active__c;
            }
        }

        return true;
    }

    /**
     * Per-user bypass for data loads and migrations, granted through a Permission
     * Set. Scoped to a user rather than the whole org, and auditable in the
     * security model.
     */
    @TestVisible
    private static Boolean isBypassed() {
        return FeatureManagement.checkPermission(BYPASS_PERMISSION);
    }
}
