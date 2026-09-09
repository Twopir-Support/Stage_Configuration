/**
 * Creates queued tracking fields, chaining until the backlog is clear.
 *
 * The Tooling API creates one field per request, so each execution handles as
 * many fields as the callout limit safely allows and chains the remainder.
 */
public with sharing class TPC_StageFieldCreationQueueable
    implements Queueable, Database.AllowsCallouts {

    private final List<TPC_FieldDefinition> pending;

    /** Swappable so tests can run the chain without callouts. */
    @TestVisible
    private static TPC_FieldDeployer deployer = new TPC_ToolingFieldDeployer();

    public TPC_StageFieldCreationQueueable(List<TPC_FieldDefinition> pending) {
        this.pending = pending == null ? new List<TPC_FieldDefinition>() : pending;
    }

    public void execute(QueueableContext context) {

        if (pending.isEmpty()) {
            return;
        }

        Integer batchSize = Math.min(
            pending.size(),
            TPC_ToolingFieldDeployer.MAX_FIELDS_PER_TRANSACTION
        );

        List<TPC_FieldDefinition> batch = new List<TPC_FieldDefinition>();

        for (Integer i = 0; i < batchSize; i++) {
            batch.add(pending[i]);
        }

        try {

            for (TPC_FieldDeployResult result : deployer.deploy(batch)) {

                if (result == null || result.success == true) {
                    continue;
                }

                TPC_ErrorLogger.log(
                    'TPC_StageFieldCreationQueueable',
                    'execute',
                    'Field ' + result.fullName + ' was not created. ' + result.message,
                    null
                );
            }

        } catch (Exception ex) {

            TPC_ErrorLogger.log('TPC_StageFieldCreationQueueable', 'execute', ex, null);
        }

        if (pending.size() <= batchSize) {
            return;
        }

        List<TPC_FieldDefinition> remaining = new List<TPC_FieldDefinition>();

        for (Integer i = batchSize; i < pending.size(); i++) {
            remaining.add(pending[i]);
        }

        // Test contexts allow a single chained job; chaining again would throw
        // and mask whatever the test was actually asserting.
        if (Test.isRunningTest()) {
            return;
        }

        System.enqueueJob(new TPC_StageFieldCreationQueueable(remaining));
    }
}
