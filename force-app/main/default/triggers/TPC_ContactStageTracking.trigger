/**
 * Stage tracking for Contact.
 *
 * No logic here by design — the trigger routes context to the handler, which is
 * unit-testable without DML. Disable tracking for this object by unchecking
 * Is_Active__c on its Stage_Trigger_Control__mdt record; no deploy required.
 */
trigger TPC_ContactStageTracking on Contact (after update) {

    TPC_StageTrackingTriggerHandler.handleAfterUpdate(
        Trigger.new,
        Trigger.oldMap,
        'Contact'
    );
}
