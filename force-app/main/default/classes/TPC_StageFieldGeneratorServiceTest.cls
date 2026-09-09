/**
 * Which fields get queued, and the convergence behaviour of the per-run cap.
 *
 * Configuration points at Opportunity because its tracking fields do not exist,
 * which is what makes them "missing". The demo object ships with all of its
 * tracking fields already built, so it is the right fixture for the runtime
 * engine and the wrong one for the generator.
 */
@IsTest
private class TPC_StageFieldGeneratorServiceTest {

    /**
     * Held on the outer class: Apex inner classes cannot declare static members.
     */
    private static List<TPC_FieldDefinition> deployed = new List<TPC_FieldDefinition>();

    private class MockDeployer implements TPC_FieldDeployer {

        public List<TPC_FieldDeployResult> deploy(List<TPC_FieldDefinition> definitions) {

            deployed.addAll(definitions);

            List<TPC_FieldDeployResult> results = new List<TPC_FieldDeployResult>();

            for (TPC_FieldDefinition def : definitions) {
                results.add(new TPC_FieldDeployResult(def.fullName(), true, null));
            }

            return results;
        }
    }

    private class FailingDeployer implements TPC_FieldDeployer {

        public List<TPC_FieldDeployResult> deploy(List<TPC_FieldDefinition> definitions) {

            List<TPC_FieldDeployResult> results = new List<TPC_FieldDeployResult>();

            for (TPC_FieldDefinition def : definitions) {
                results.add(
                    new TPC_FieldDeployResult(def.fullName(), false, 'HTTP 400: refused')
                );
            }

            return results;
        }
    }

    /** An active picklist value on Opportunity.StageName, read from describe. */
    private static String anOpportunityStage() {

        for (Schema.PicklistEntry entry :
             Opportunity.StageName.getDescribe().getPicklistValues()) {

            if (entry.isActive()) {
                return entry.getLabel();
            }
        }

        return null;
    }

    @IsTest
    static void generateFields_queuesTheFourMissingFieldsForAConfiguredStage() {

        String stage = anOpportunityStage();

        insert TPC_TestDataFactory.config('Opportunity', 'StageName', stage);

        deployed.clear();
        TPC_StageFieldCreationQueueable.deployer = new MockDeployer();

        Test.startTest();
        TPC_StageConfigurationWrapper.GenerationSummary summary =
            TPC_StageFieldGeneratorService.generateFields();
        Test.stopTest();

        Assert.areEqual(4, summary.queued, 'A stage needs entered, exited, latest and cumulative');
        Assert.areEqual(0, summary.remaining, 'One configuration is well within the cap');
        Assert.areEqual(4, deployed.size(), 'The queueable should deploy what was queued');

        Set<String> names = new Set<String>();
        for (TPC_FieldDefinition def : deployed) {
            names.add(def.fieldApiName);
            Assert.areEqual('Opportunity', def.objectApiName, 'Fields belong to the configured object');
            Assert.isTrue(def.label.length() <= 40, 'Field labels are capped at 40 characters');
        }

        for (String expected : TPC_StageFieldNames.allFieldNames(stage)) {
            Assert.isTrue(
                names.contains(expected),
                'Expected the generator to queue ' + expected
            );
        }
    }

    @IsTest
    static void generateFields_skipsStagesThatAlreadyHaveTheirFields() {

        // Every stage on the demo object already has its tracking fields.
        TPC_TestDataFactory.configureAllDemoStages();

        deployed.clear();
        TPC_StageFieldCreationQueueable.deployer = new MockDeployer();

        Test.startTest();
        TPC_StageConfigurationWrapper.GenerationSummary summary =
            TPC_StageFieldGeneratorService.generateFields();
        Test.stopTest();

        Assert.areEqual(
            0,
            summary.queued,
            'Nothing should be queued when every field already exists'
        );
    }

    @IsTest
    static void generateFields_reportsWhatItCouldNotReachThisRun() {

        List<Stage_Configuration__c> configs = new List<Stage_Configuration__c>();

        for (Schema.PicklistEntry entry :
             Opportunity.StageName.getDescribe().getPicklistValues()) {

            if (entry.isActive() && configs.size() < 3) {
                configs.add(
                    TPC_TestDataFactory.config('Opportunity', 'StageName', entry.getLabel())
                );
            }
        }

        insert configs;

        // Room for one configuration's worth of fields only.
        TPC_StageFieldGeneratorService.maxFieldsPerRun = 4;

        deployed.clear();
        TPC_StageFieldCreationQueueable.deployer = new MockDeployer();

        Test.startTest();
        TPC_StageConfigurationWrapper.GenerationSummary summary =
            TPC_StageFieldGeneratorService.generateFields();
        Test.stopTest();

        Assert.areEqual(4, summary.queued, 'The cap should bound what one run queues');
        Assert.isTrue(
            summary.remaining >= 1,
            'Configurations beyond the cap must be reported rather than silently dropped'
        );
    }

    @IsTest
    static void generateFields_skipsAStageValueThatIsNoLongerOnThePicklist() {

        insert TPC_TestDataFactory.config('Opportunity', 'StageName', 'Not A Real Stage');

        deployed.clear();
        TPC_StageFieldCreationQueueable.deployer = new MockDeployer();

        Test.startTest();
        TPC_StageConfigurationWrapper.GenerationSummary summary =
            TPC_StageFieldGeneratorService.generateFields();
        Test.stopTest();

        Assert.areEqual(0, summary.queued, 'A value that is not on the picklist yields no fields');
        Assert.areEqual(1, summary.skipped, 'And it should be reported as skipped');
    }

    @IsTest
    static void generateFields_skipsAnUnknownObject() {

        insert TPC_TestDataFactory.config('Not_A_Real_Object__c', 'StageName', 'Anything');

        Test.startTest();
        TPC_StageConfigurationWrapper.GenerationSummary summary =
            TPC_StageFieldGeneratorService.generateFields();
        Test.stopTest();

        Assert.areEqual(0, summary.queued, 'An object that does not exist yields no fields');
    }

    @IsTest
    static void generateFields_withNoConfiguration_doesNothing() {

        Test.startTest();
        TPC_StageConfigurationWrapper.GenerationSummary summary =
            TPC_StageFieldGeneratorService.generateFields();
        Test.stopTest();

        Assert.areEqual(0, summary.queued, 'No configuration means no work');
    }

    @IsTest
    static void queueable_logsFieldsTheDeployerRefused() {

        insert TPC_TestDataFactory.config('Opportunity', 'StageName', anOpportunityStage());

        TPC_StageFieldCreationQueueable.deployer = new FailingDeployer();

        Test.startTest();
        TPC_StageFieldGeneratorService.generateFields();
        Test.stopTest();

        Assert.isNotNull(
            TPC_ErrorLogger.lastEvent,
            'A refused field should be reported rather than silently dropped'
        );
        Assert.areEqual(
            'TPC_StageFieldCreationQueueable',
            TPC_ErrorLogger.lastEvent.Class_Name__c,
            'The failure should be attributed to the queueable'
        );
    }

    @IsTest
    static void queueable_withNothingToDo_isHarmless() {

        Test.startTest();
        System.enqueueJob(new TPC_StageFieldCreationQueueable(null));
        Test.stopTest();

        Assert.isTrue(true, 'An empty queueable should complete without error');
    }
}
