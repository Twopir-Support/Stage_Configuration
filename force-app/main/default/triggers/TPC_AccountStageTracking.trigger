/**
 * Stage tracking for Account.
 *
 * No logic here by design — the trigger routes context to the handler, which is
 * unit-testable without DML. Disable tracking for this object by unchecking
 * Is_Active__c on its Stage_Trigger_Control__mdt record; no deploy required.
 */
trigger TPC_AccountStageTracking on Account (after update) {

    TPC_StageTrackingTriggerHandler.handleAfterUpdate(
        Trigger.new,
        Trigger.oldMap,
        'Account'
    );
}
