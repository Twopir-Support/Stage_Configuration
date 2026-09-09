/** Routing, the kill switch, the bypass permission, and configuration reuse. */
@IsTest
private class TPC_StageTrackingTriggerHandlerTest {

    @TestSetup
    static void setup() {
        TPC_TestDataFactory.configureAllDemoStages();
    }

    @IsTest
    static void isEnabled_reflectsTheShippedControlRecords() {

        Assert.isTrue(
            TPC_StageTrackingTriggerHandler.isEnabled('Opportunity'),
            'Opportunity ships with an active control record'
        );

        Assert.isTrue(
            TPC_StageTrackingTriggerHandler.isEnabled('Stage_Tracking_Demo__c'),
            'The demo object ships with an active control record'
        );

        Assert.isTrue(
            TPC_StageTrackingTriggerHandler.isEnabled('Nonexistent__c'),
            'An object with no control record defaults to enabled'
        );
    }

    @IsTest
    static void isBypassed_isFalseForAUserWithoutTheBypassPermission() {

        User plain = TPC_TestDataFactory.plainUser();

        System.runAs(plain) {
            Assert.isFalse(
                TPC_StageTrackingTriggerHandler.isBypassed(),
                'A user without the bypass permission should not be bypassed'
            );
        }
    }

    @IsTest
    static void bypassPermission_suppressesTracking() {

        User loader = TPC_TestDataFactory.standardUser(
            'byp',
            new List<String>{
                TPC_TestDataFactory.ADMIN_PERM_SET,
                TPC_TestDataFactory.BYPASS_PERM_SET
            }
        );

        Stage_Tracking_Demo__c record;

        System.runAs(loader) {

            record = TPC_TestDataFactory.demos(1, TPC_TestDataFactory.DRAFT)[0];
            insert record;

            Test.startTest();
            update new Stage_Tracking_Demo__c(
                Id = record.Id,
                Stage__c = TPC_TestDataFactory.IN_REVIEW
            );
            Test.stopTest();
        }

        Stage_Tracking_Demo__c result = [
            SELECT Date_Entered_In_Review__c
            FROM Stage_Tracking_Demo__c
            WHERE Id = :record.Id
        ];

        Assert.isNull(
            result.Date_Entered_In_Review__c,
            'A user holding Bypass Stage Tracking should not generate stage history'
        );
    }

    @IsTest
    static void unchangedStageField_doesNoWork() {

        Stage_Tracking_Demo__c record = TPC_TestDataFactory.demos(1, TPC_TestDataFactory.DRAFT)[0];
        insert record;

        Test.startTest();
        update new Stage_Tracking_Demo__c(Id = record.Id, Name = 'Renamed');
        Test.stopTest();

        Stage_Tracking_Demo__c result = [
            SELECT Date_Entered_Draft__c, Date_Exited_Draft__c
            FROM Stage_Tracking_Demo__c
            WHERE Id = :record.Id
        ];

        Assert.isNull(
            result.Date_Exited_Draft__c,
            'Editing an unrelated field should not touch stage history'
        );
    }

    @IsTest
    static void manyConfigurationsForOneField_produceOneRequestPerRecord() {

        // Four configurations name Stage__c — one per tracked value. The handler
        // must reduce them to a single request per record rather than emitting
        // one per configuration.
        Integer stageConfigs = [
            SELECT COUNT()
            FROM Stage_Configuration__c
            WHERE Stage_Field_API__c = :TPC_TestDataFactory.STAGE_FIELD
        ];

        Assert.areEqual(4, stageConfigs, 'Precondition: four values configured on Stage__c');

        Stage_Tracking_Demo__c record = TPC_TestDataFactory.demos(1, TPC_TestDataFactory.DRAFT)[0];
        insert record;

        Test.startTest();
        update new Stage_Tracking_Demo__c(
            Id = record.Id,
            Stage__c = TPC_TestDataFactory.IN_REVIEW
        );
        Integer dmlAfter = Limits.getDmlStatements();
        Test.stopTest();

        Assert.isTrue(
            dmlAfter <= 3,
            'One transition should not fan out into a DML per configuration record, was ' +
                dmlAfter
        );
    }

    @IsTest
    static void handleAfterUpdate_ignoresEmptyInput() {

        Test.startTest();
        TPC_StageTrackingTriggerHandler.handleAfterUpdate(null, null, 'Account');
        TPC_StageTrackingTriggerHandler.handleAfterUpdate(
            new List<SObject>(),
            new Map<Id, SObject>(),
            'Account'
        );
        TPC_StageTrackingTriggerHandler.handleAfterUpdate(
            new List<SObject>{ new Account() },
            new Map<Id, SObject>(),
            ''
        );
        Integer dmlUsed = Limits.getDmlStatements();
        Test.stopTest();

        Assert.areEqual(0, dmlUsed, 'Empty input should write nothing');
    }
}
