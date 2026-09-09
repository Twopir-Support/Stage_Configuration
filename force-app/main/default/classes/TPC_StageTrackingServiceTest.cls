/**
 * Behaviour of the tracking engine, exercised end to end through the packaged
 * trigger on Stage_Tracking_Demo__c.
 *
 * Three of these tests pin defects that produced wrong numbers rather than
 * errors, so they are named for the behaviour rather than the method.
 */
@IsTest
private class TPC_StageTrackingServiceTest {

    @TestSetup
    static void setup() {
        TPC_TestDataFactory.configureAllDemoStages();
    }

    private static Stage_Tracking_Demo__c reload(Id recordId) {
        return [
            SELECT Id, Stage__c, Review_Status__c,
                   Date_Entered_Draft__c, Date_Exited_Draft__c,
                   Latest_Time_Draft__c, Cumulative_Time_Draft__c,
                   Date_Entered_In_Review__c, Date_Exited_In_Review__c,
                   Latest_Time_In_Review__c, Cumulative_Time_In_Review__c,
                   Date_Entered_Approved__c, Date_Exited_Approved__c,
                   Latest_Time_Approved__c, Cumulative_Time_Approved__c,
                   Date_Entered_Awaiting_Countersignature_R__c,
                   Date_Exited_Awaiting_Countersignature_Re__c,
                   Latest_Time_Awaiting_Countersignature_Re__c,
                   Cumulative_Time_Awaiting_Countersignatur__c,
                   Date_Entered_Pending__c, Date_Exited_Pending__c,
                   Date_Entered_Complete__c, Date_Exited_Complete__c
            FROM Stage_Tracking_Demo__c
            WHERE Id = :recordId
        ];
    }

    // ------------------------------------------------------------ happy path

    @IsTest
    static void enteringStage_startsTheClockAndClearsCompletedVisitFigures() {

        Stage_Tracking_Demo__c record = TPC_TestDataFactory.demos(1, TPC_TestDataFactory.DRAFT)[0];
        insert record;

        Test.startTest();
        update new Stage_Tracking_Demo__c(
            Id = record.Id,
            Stage__c = TPC_TestDataFactory.IN_REVIEW
        );
        Test.stopTest();

        Stage_Tracking_Demo__c result = reload(record.Id);

        Assert.isNotNull(
            result.Date_Entered_In_Review__c,
            'Entering a stage should stamp the entry time'
        );
        Assert.isNull(
            result.Date_Exited_In_Review__c,
            'The record has not left the stage it just entered'
        );
        Assert.isNull(
            result.Latest_Time_In_Review__c,
            'There is no completed visit to measure yet'
        );
    }

    @IsTest
    static void leavingStage_banksTheElapsedHours() {

        Stage_Tracking_Demo__c record = TPC_TestDataFactory.demos(1, TPC_TestDataFactory.DRAFT)[0];
        insert record;

        update new Stage_Tracking_Demo__c(
            Id = record.Id,
            Date_Entered_Draft__c = System.now().addHours(-3)
        );

        Test.startTest();
        update new Stage_Tracking_Demo__c(
            Id = record.Id,
            Stage__c = TPC_TestDataFactory.IN_REVIEW
        );
        Test.stopTest();

        Stage_Tracking_Demo__c result = reload(record.Id);

        Assert.isNotNull(result.Date_Exited_Draft__c, 'Leaving a stage should stamp the exit');

        Assert.isTrue(
            result.Latest_Time_Draft__c >= 2.9 && result.Latest_Time_Draft__c <= 3.1,
            'Three hours in the stage should be measured as roughly 3, was ' +
                result.Latest_Time_Draft__c
        );

        Assert.areEqual(
            result.Latest_Time_Draft__c,
            result.Cumulative_Time_Draft__c,
            'On a first visit, cumulative equals the latest visit'
        );
    }

    // ------------------------------------- regression: cumulative time (H1)

    @IsTest
    static void reEnteringStage_preservesCumulativeTimeFromEarlierVisits() {

        Stage_Tracking_Demo__c record = TPC_TestDataFactory.demos(1, TPC_TestDataFactory.DRAFT)[0];
        insert record;

        update new Stage_Tracking_Demo__c(
            Id = record.Id,
            Date_Entered_Draft__c = System.now().addHours(-4)
        );

        Test.startTest();

        // Leave Draft — four hours are banked.
        update new Stage_Tracking_Demo__c(
            Id = record.Id,
            Stage__c = TPC_TestDataFactory.IN_REVIEW
        );

        Decimal bankedAfterFirstVisit = reload(record.Id).Cumulative_Time_Draft__c;

        // Come back to Draft.
        update new Stage_Tracking_Demo__c(
            Id = record.Id,
            Stage__c = TPC_TestDataFactory.DRAFT
        );

        Test.stopTest();

        Stage_Tracking_Demo__c result = reload(record.Id);

        Assert.isTrue(
            bankedAfterFirstVisit >= 3.9,
            'Precondition: the first visit should have banked about four hours, was ' +
                bankedAfterFirstVisit
        );

        Assert.isNotNull(
            result.Cumulative_Time_Draft__c,
            'Re-entering a stage must not erase the hours banked on earlier visits'
        );

        Assert.areEqual(
            bankedAfterFirstVisit,
            result.Cumulative_Time_Draft__c,
            'Cumulative time should carry across a re-entry untouched'
        );

        Assert.isNotNull(
            result.Date_Entered_Draft__c,
            'Re-entry should restart the clock for the new visit'
        );
        Assert.isNull(
            result.Date_Exited_Draft__c,
            'Re-entry should clear the previous exit stamp'
        );
    }

    // ------------------------------- regression: truncated field names (H2)

    @IsTest
    static void longStageName_populatesTheTruncatedField() {

        Stage_Tracking_Demo__c record =
            TPC_TestDataFactory.demos(1, TPC_TestDataFactory.APPROVED)[0];
        insert record;

        Test.startTest();
        update new Stage_Tracking_Demo__c(
            Id = record.Id,
            Stage__c = TPC_TestDataFactory.LONG_STAGE
        );
        Test.stopTest();

        Stage_Tracking_Demo__c result = reload(record.Id);

        Assert.isNotNull(
            result.Date_Entered_Awaiting_Countersignature_R__c,
            'A stage whose name exceeds the field-name budget must still be tracked ' +
            'in the truncated field the generator creates'
        );
        Assert.isNotNull(
            result.Date_Exited_Approved__c,
            'Leaving the previous stage should still be recorded'
        );
    }

    // --------------------------- regression: two tracked fields at once (H3)

    @IsTest
    static void twoTrackedFieldsChangingTogether_areBothRecorded() {

        Stage_Tracking_Demo__c record = TPC_TestDataFactory.demos(1, TPC_TestDataFactory.DRAFT)[0];
        insert record;

        Test.startTest();
        update new Stage_Tracking_Demo__c(
            Id = record.Id,
            Stage__c = TPC_TestDataFactory.IN_REVIEW,
            Review_Status__c = TPC_TestDataFactory.COMPLETE
        );
        Test.stopTest();

        Stage_Tracking_Demo__c result = reload(record.Id);

        Assert.isNotNull(
            result.Date_Entered_In_Review__c,
            'The Stage picklist transition should be recorded'
        );
        Assert.isNotNull(
            result.Date_Entered_Complete__c,
            'The Review Status transition should be recorded in the same save'
        );
        Assert.isNotNull(
            result.Date_Exited_Draft__c,
            'Leaving the old Stage value should be recorded'
        );
        Assert.isNotNull(
            result.Date_Exited_Pending__c,
            'Leaving the old Review Status value should be recorded'
        );
    }

    // ---------------------------------------------------------- skipped stages

    @IsTest
    static void skippingForward_stampsTheSkippedStageAsZeroLength() {

        Stage_Tracking_Demo__c record = TPC_TestDataFactory.demos(1, TPC_TestDataFactory.DRAFT)[0];
        insert record;

        Test.startTest();
        update new Stage_Tracking_Demo__c(
            Id = record.Id,
            Stage__c = TPC_TestDataFactory.APPROVED
        );
        Test.stopTest();

        Stage_Tracking_Demo__c result = reload(record.Id);

        Assert.isNotNull(
            result.Date_Entered_In_Review__c,
            'A stage passed straight through should still be stamped'
        );
        Assert.isNotNull(
            result.Date_Exited_In_Review__c,
            'A skipped stage is entered and exited at the same moment'
        );
        Assert.isTrue(
            result.Latest_Time_In_Review__c == 0,
            'A skipped stage lasted no time, was ' + result.Latest_Time_In_Review__c
        );
    }

    @IsTest
    static void movingBackwards_doesNotStampInterveningStages() {

        Stage_Tracking_Demo__c record =
            TPC_TestDataFactory.demos(1, TPC_TestDataFactory.APPROVED)[0];
        insert record;

        Test.startTest();
        update new Stage_Tracking_Demo__c(
            Id = record.Id,
            Stage__c = TPC_TestDataFactory.DRAFT
        );
        Test.stopTest();

        Stage_Tracking_Demo__c result = reload(record.Id);

        Assert.isNull(
            result.Date_Entered_In_Review__c,
            'Moving backwards is not a skip — the intervening stage was not visited'
        );
    }

    // ------------------------------------------------------------ do not prefill

    @IsTest
    static void doNotPrefill_leavesTheStageUntouched() {

        Stage_Configuration__c inReview = [
            SELECT Id
            FROM Stage_Configuration__c
            WHERE Stage_Value__c = :TPC_TestDataFactory.IN_REVIEW
              AND Stage_Field_API__c = :TPC_TestDataFactory.STAGE_FIELD
            LIMIT 1
        ];
        inReview.Do_Not_Prefill__c = true;
        update inReview;

        Stage_Tracking_Demo__c record = TPC_TestDataFactory.demos(1, TPC_TestDataFactory.DRAFT)[0];
        insert record;

        Test.startTest();
        update new Stage_Tracking_Demo__c(
            Id = record.Id,
            Stage__c = TPC_TestDataFactory.IN_REVIEW
        );
        Test.stopTest();

        Stage_Tracking_Demo__c result = reload(record.Id);

        Assert.isNull(
            result.Date_Entered_In_Review__c,
            'A stage marked Do Not Prefill should not be stamped'
        );
        Assert.isNotNull(
            result.Date_Exited_Draft__c,
            'Other stages should be unaffected by that setting'
        );
    }

    // -------------------------------------------------------------------- bulk

    @IsTest
    static void bulkUpdate_ofTwoHundredRecords_tracksEveryOne() {

        List<Stage_Tracking_Demo__c> records =
            TPC_TestDataFactory.demos(200, TPC_TestDataFactory.DRAFT);
        insert records;

        List<Stage_Tracking_Demo__c> updates = new List<Stage_Tracking_Demo__c>();

        for (Stage_Tracking_Demo__c record : records) {
            updates.add(
                new Stage_Tracking_Demo__c(
                    Id = record.Id,
                    Stage__c = TPC_TestDataFactory.IN_REVIEW
                )
            );
        }

        Test.startTest();
        update updates;
        Test.stopTest();

        Integer tracked = [
            SELECT COUNT()
            FROM Stage_Tracking_Demo__c
            WHERE Date_Entered_In_Review__c != NULL
        ];

        Assert.areEqual(
            200,
            tracked,
            'Every record in a full trigger batch should be tracked'
        );
    }

    // ------------------------------------------------------------ null safety

    @IsTest
    static void recordTransitions_ignoresEmptyAndMalformedInput() {

        Test.startTest();
        TPC_StageTrackingService.recordTransitions(null);
        TPC_StageTrackingService.recordTransitions(new List<TPC_StageTrackingRequest>());
        TPC_StageTrackingService.recordTransitions(
            new List<TPC_StageTrackingRequest>{
                new TPC_StageTrackingRequest(),
                new TPC_StageTrackingRequest(null, null, null, null, null)
            }
        );
        // Read inside the block: after stopTest the counters revert to the
        // outer context and would report zero regardless.
        Integer dmlUsed = Limits.getDmlStatements();
        Integer soqlUsed = Limits.getQueries();
        Test.stopTest();

        Assert.areEqual(
            0,
            dmlUsed,
            'Nothing actionable was supplied, so nothing should have been written'
        );
        Assert.areEqual(
            0,
            soqlUsed,
            'Nothing actionable was supplied, so nothing should have been queried'
        );
    }

    @IsTest
    static void dedupeKey_distinguishesStageFieldsOnTheSameRecord() {

        Id recordId = '001000000000000AAA';

        TPC_StageTrackingRequest first =
            new TPC_StageTrackingRequest(recordId, 'Account', 'Type', 'A', 'B');
        TPC_StageTrackingRequest second =
            new TPC_StageTrackingRequest(recordId, 'Account', 'Rating', 'A', 'B');

        Assert.areNotEqual(
            first.dedupeKey(),
            second.dedupeKey(),
            'Two tracked fields on one record must not collapse into a single request'
        );
    }
}
