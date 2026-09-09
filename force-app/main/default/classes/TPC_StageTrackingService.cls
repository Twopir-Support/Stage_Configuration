/**
 * Writes stage-duration tracking fields when a configured picklist changes.
 *
 * For each tracked stage value the package maintains four fields, named by
 * TPC_StageFieldNames:
 *
 *   Date_Entered_<Stage>__c     when the record most recently entered the stage
 *   Date_Exited_<Stage>__c      when it most recently left
 *   Latest_Time_<Stage>__c      hours spent on the most recent visit
 *   Cumulative_Time_<Stage>__c  hours spent across every visit
 *
 * Access mode: this class runs in system mode deliberately. A user who moves a
 * record from one stage to the next has, by definition, edit access to the
 * record — but they will usually have no edit access to the tracking fields
 * themselves, which are maintained by the package rather than by people. The
 * transition is a fact about the record and is recorded either way. The DML
 * below says 'as system' rather than relying on the default so that the choice
 * is greppable.
 */
public inherited sharing class TPC_StageTrackingService {

    public static void recordTransitions(List<TPC_StageTrackingRequest> requests) {

        if (requests == null || requests.isEmpty()) {
            return;
        }

        // De-duplicate on record AND stage field. Keying on record alone
        // discarded the second transition whenever an object tracked more than
        // one picklist field and both changed in the same save.
        Map<String, TPC_StageTrackingRequest> uniqueRequests =
            new Map<String, TPC_StageTrackingRequest>();

        for (TPC_StageTrackingRequest req : requests) {

            if (req == null || req.recordId == null ||
                String.isBlank(req.objectApiName) ||
                String.isBlank(req.stageFieldApiName)) {
                continue;
            }

            uniqueRequests.put(req.dedupeKey(), req);
        }

        if (uniqueRequests.isEmpty()) {
            return;
        }

        Map<String, List<TPC_StageTrackingRequest>> requestsByObject =
            new Map<String, List<TPC_StageTrackingRequest>>();

        for (TPC_StageTrackingRequest req : uniqueRequests.values()) {

            if (!requestsByObject.containsKey(req.objectApiName)) {
                requestsByObject.put(
                    req.objectApiName,
                    new List<TPC_StageTrackingRequest>()
                );
            }

            requestsByObject.get(req.objectApiName).add(req);
        }

        // getGlobalDescribe() is among the most expensive calls in Apex. It is
        // resolved once here rather than once per object per invocation.
        Map<String, Schema.SObjectType> globalDescribe = Schema.getGlobalDescribe();

        for (String objectApi : requestsByObject.keySet()) {

            try {

                processObject(
                    objectApi,
                    requestsByObject.get(objectApi),
                    globalDescribe
                );

            } catch (Exception ex) {

                TPC_ErrorLogger.log(
                    'TPC_StageTrackingService',
                    'recordTransitions[' + objectApi + ']',
                    ex,
                    null
                );

                throw ex;
            }
        }
    }

    private static void processObject(
        String objectApi,
        List<TPC_StageTrackingRequest> requests,
        Map<String, Schema.SObjectType> globalDescribe
    ) {
        Schema.SObjectType objType = globalDescribe.get(objectApi);

        if (objType == null) {
            return;
        }

        Map<String, Schema.SObjectField> fieldMap =
            objType.getDescribe().fields.getMap();

        Set<String> stageFieldApiNames = new Set<String>();

        for (TPC_StageTrackingRequest req : requests) {
            stageFieldApiNames.add(req.stageFieldApiName);
        }

        Map<String, Map<String, Boolean>> prefillByFieldAndValue =
            loadPrefillConfig(objectApi, stageFieldApiNames);

        Map<String, List<String>> stageOrderByField =
            buildStageOrders(fieldMap, stageFieldApiNames);

        // Fields to query: every tracking field for every configured stage on
        // this object, plus the old and new stage of each request. Prefilling a
        // skipped stage reads its existing cumulative value before writing, so
        // configured stages must be queried even when no request mentions them.
        Set<String> fieldsToQuery = new Set<String>{ 'Id' };

        for (Map<String, Boolean> byValue : prefillByFieldAndValue.values()) {
            for (String stageValue : byValue.keySet()) {
                addTrackingFields(fieldsToQuery, fieldMap, stageValue);
            }
        }

        Map<Id, List<TPC_StageTrackingRequest>> requestsByRecord =
            new Map<Id, List<TPC_StageTrackingRequest>>();

        for (TPC_StageTrackingRequest req : requests) {

            addTrackingFields(fieldsToQuery, fieldMap, req.oldStage);
            addTrackingFields(fieldsToQuery, fieldMap, req.newStage);

            if (!requestsByRecord.containsKey(req.recordId)) {
                requestsByRecord.put(
                    req.recordId,
                    new List<TPC_StageTrackingRequest>()
                );
            }

            requestsByRecord.get(req.recordId).add(req);
        }

        if (fieldsToQuery.size() <= 1) {
            return;             // no tracking fields exist yet on this object
        }

        Set<Id> recordIds = requestsByRecord.keySet();

        // Field names are allow-listed against the describe above and the object
        // name comes from packaged configuration that was itself validated
        // against getGlobalDescribe(), so there is no injection surface here.
        String soql =
            'SELECT ' + String.join(new List<String>(fieldsToQuery), ',') +
            ' FROM ' + objectApi +
            ' WHERE Id IN :recordIds';

        List<SObject> records = Database.query(soql);

        List<SObject> toUpdate = new List<SObject>();
        Datetime now = System.now();

        for (SObject record : records) {

            List<TPC_StageTrackingRequest> recordRequests =
                requestsByRecord.get((Id) record.get('Id'));

            if (recordRequests == null || recordRequests.isEmpty()) {
                continue;
            }

            for (TPC_StageTrackingRequest req : recordRequests) {

                List<String> skipped = skippedStages(
                    stageOrderByField.get(req.stageFieldApiName),
                    req.oldStage,
                    req.newStage
                );

                for (String skippedStage : skipped) {

                    if (shouldTrack(prefillByFieldAndValue, req.stageFieldApiName, skippedStage)) {
                        stampSkippedStage(record, fieldMap, skippedStage, now);
                    }
                }

                if (shouldTrack(prefillByFieldAndValue, req.stageFieldApiName, req.oldStage)) {
                    closeStage(record, fieldMap, req.oldStage, now);
                }

                if (shouldTrack(prefillByFieldAndValue, req.stageFieldApiName, req.newStage)) {
                    openStage(record, fieldMap, req.newStage, now);
                }
            }

            toUpdate.add(record);
        }

        if (!toUpdate.isEmpty()) {
            // System mode is deliberate — see the class header.
            update as system toUpdate;
        }
    }

    // ---------------------------------------------------------------- config

    /**
     * Active configuration for this object, as
     * stageField (lowercased) -> stageValue -> whether to track it.
     *
     * Do_Not_Prefill__c is a checkbox, so it is never null in practice; a null
     * is treated as false (track the stage), which matches the field's default
     * and the behaviour an admin gets by leaving it alone.
     */
    private static Map<String, Map<String, Boolean>> loadPrefillConfig(
        String objectApi,
        Set<String> stageFieldApiNames
    ) {
        Map<String, Map<String, Boolean>> result =
            new Map<String, Map<String, Boolean>>();

        if (stageFieldApiNames.isEmpty()) {
            return result;
        }

        for (Stage_Configuration__c cfg : [
            SELECT Stage_Field_API__c, Stage_Value__c, Do_Not_Prefill__c
            FROM Stage_Configuration__c
            WHERE Object_API_Name__c = :objectApi
              AND Stage_Field_API__c IN :stageFieldApiNames
              AND Active__c = TRUE
            WITH SYSTEM_MODE
        ]) {

            if (String.isBlank(cfg.Stage_Field_API__c) || String.isBlank(cfg.Stage_Value__c)) {
                continue;
            }

            String key = cfg.Stage_Field_API__c.toLowerCase();

            if (!result.containsKey(key)) {
                result.put(key, new Map<String, Boolean>());
            }

            Boolean doNotPrefill = cfg.Do_Not_Prefill__c == true;

            result.get(key).put(cfg.Stage_Value__c, !doNotPrefill);
        }

        return result;
    }

    /** A stage with no active configuration is tracked. */
    private static Boolean shouldTrack(
        Map<String, Map<String, Boolean>> config,
        String stageField,
        String stageValue
    ) {
        if (String.isBlank(stageField) || String.isBlank(stageValue)) {
            return false;
        }

        Map<String, Boolean> byValue = config.get(stageField.toLowerCase());

        if (byValue == null || !byValue.containsKey(stageValue)) {
            return true;
        }

        return byValue.get(stageValue) == true;
    }

    // ----------------------------------------------------------- stage order

    private static Map<String, List<String>> buildStageOrders(
        Map<String, Schema.SObjectField> fieldMap,
        Set<String> stageFieldApiNames
    ) {
        Map<String, List<String>> orders = new Map<String, List<String>>();

        for (String stageField : stageFieldApiNames) {

            List<String> order = new List<String>();

            if (String.isNotBlank(stageField) && fieldMap.containsKey(stageField)) {

                for (Schema.PicklistEntry entry :
                     fieldMap.get(stageField).getDescribe().getPicklistValues()) {

                    if (entry.isActive()) {
                        order.add(entry.getValue());
                    }
                }
            }

            orders.put(stageField, order);
        }

        return orders;
    }

    /**
     * Stages jumped over by a forward move. Picklist display order is taken as
     * business stage order — the same assumption the Setup UI's own "stage
     * sequence" affordances make. A backward move is never treated as a skip.
     */
    private static List<String> skippedStages(
        List<String> stageOrder,
        String oldStage,
        String newStage
    ) {
        List<String> skipped = new List<String>();

        if (stageOrder == null || stageOrder.isEmpty() ||
            String.isBlank(oldStage) || String.isBlank(newStage)) {
            return skipped;
        }

        Integer oldIndex = stageOrder.indexOf(oldStage);
        Integer newIndex = stageOrder.indexOf(newStage);

        if (oldIndex == -1 || newIndex == -1 || newIndex - oldIndex <= 1) {
            return skipped;
        }

        for (Integer i = oldIndex + 1; i < newIndex; i++) {
            skipped.add(stageOrder[i]);
        }

        return skipped;
    }

    // ---------------------------------------------------------------- fields

    private static void addTrackingFields(
        Set<String> fields,
        Map<String, Schema.SObjectField> fieldMap,
        String stageValue
    ) {
        if (String.isBlank(stageValue)) {
            return;
        }

        for (String name : TPC_StageFieldNames.allFieldNames(stageValue)) {

            if (fieldMap.containsKey(name)) {
                fields.add(name);
            }
        }
    }

    /**
     * A stage the record passed straight through. Entered and exited are stamped
     * with the same instant so the visit reads as zero-length, and cumulative is
     * left alone.
     */
    private static void stampSkippedStage(
        SObject record,
        Map<String, Schema.SObjectField> fieldMap,
        String stageValue,
        Datetime now
    ) {
        put(record, fieldMap, TPC_StageFieldNames.enteredField(stageValue), now);
        put(record, fieldMap, TPC_StageFieldNames.exitedField(stageValue), now);
        put(record, fieldMap, TPC_StageFieldNames.latestField(stageValue), 0);
    }

    /** Leaving a stage: stamp the exit, bank the elapsed hours. */
    private static void closeStage(
        SObject record,
        Map<String, Schema.SObjectField> fieldMap,
        String stageValue,
        Datetime now
    ) {
        String enteredField = TPC_StageFieldNames.enteredField(stageValue);

        if (String.isBlank(enteredField) || !fieldMap.containsKey(enteredField)) {
            return;
        }

        Datetime enteredAt = (Datetime) record.get(enteredField);

        if (enteredAt == null) {
            return;             // never recorded entering, so nothing to measure
        }

        Decimal hours = (
            Decimal.valueOf(now.getTime() - enteredAt.getTime()) / 3600000
        ).setScale(2);

        put(record, fieldMap, TPC_StageFieldNames.exitedField(stageValue), now);
        put(record, fieldMap, TPC_StageFieldNames.latestField(stageValue), hours);

        String cumulativeField = TPC_StageFieldNames.cumulativeField(stageValue);

        if (fieldMap.containsKey(cumulativeField)) {

            Decimal cumulative = toDecimal(record.get(cumulativeField));

            record.put(cumulativeField, (cumulative + hours).setScale(2));
        }
    }

    /**
     * Entering a stage: start the clock and clear the figures that describe a
     * completed visit.
     *
     * Cumulative time is deliberately NOT cleared. It is the running total
     * across every visit, so clearing it on entry erased the hours banked on
     * earlier passes — any record that moved backwards and forwards again
     * reported only its most recent visit.
     */
    private static void openStage(
        SObject record,
        Map<String, Schema.SObjectField> fieldMap,
        String stageValue,
        Datetime now
    ) {
        put(record, fieldMap, TPC_StageFieldNames.enteredField(stageValue), now);
        put(record, fieldMap, TPC_StageFieldNames.exitedField(stageValue), null);
        put(record, fieldMap, TPC_StageFieldNames.latestField(stageValue), null);
    }

    private static void put(
        SObject record,
        Map<String, Schema.SObjectField> fieldMap,
        String fieldName,
        Object value
    ) {
        if (String.isNotBlank(fieldName) && fieldMap.containsKey(fieldName)) {
            record.put(fieldName, value);
        }
    }

    private static Decimal toDecimal(Object value) {

        if (value == null) {
            return 0;
        }

        if (value instanceof Decimal) {
            return (Decimal) value;
        }

        return Decimal.valueOf(String.valueOf(value));
    }
}
