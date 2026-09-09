/**
 * Stage tracking for Lead.
 *
 * No logic here by design — the trigger routes context to the handler, which is
 * unit-testable without DML. Disable tracking for this object by unchecking
 * Is_Active__c on its Stage_Trigger_Control__mdt record; no deploy required.
 */
trigger TPC_LeadStageTracking on Lead (after update) {

    TPC_StageTrackingTriggerHandler.handleAfterUpdate(
        Trigger.new,
        Trigger.oldMap,
        'Lead'
    );
}
