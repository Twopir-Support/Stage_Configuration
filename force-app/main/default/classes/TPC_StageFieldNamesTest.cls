/**
 * The writer and the reader of tracking fields both derive names from
 * TPC_StageFieldNames. These tests pin the behaviour they previously disagreed
 * on — truncation and trailing underscores — because a disagreement there
 * produces fields that are created and then never populated, with no error.
 */
@IsTest
private class TPC_StageFieldNamesTest {

    @IsTest
    static void sanitize_replacesNonAlphanumerics() {
        Assert.areEqual(
            'Closed_Won',
            TPC_StageFieldNames.sanitize('Closed Won'),
            'Spaces should become single underscores'
        );

        Assert.areEqual(
            'Proposal_Price_Quote',
            TPC_StageFieldNames.sanitize('Proposal/Price Quote'),
            'Runs of punctuation should collapse to one underscore'
        );
    }

    @IsTest
    static void sanitize_stripsLeadingAndTrailingUnderscores() {
        Assert.areEqual(
            'Review',
            TPC_StageFieldNames.sanitize('  - Review - '),
            'Leading and trailing underscores are invalid in an API name'
        );
    }

    @IsTest
    static void sanitize_handlesBlankInput() {
        Assert.areEqual('', TPC_StageFieldNames.sanitize(null), 'Null should sanitise to blank');
        Assert.areEqual('', TPC_StageFieldNames.sanitize('   '), 'Blank should sanitise to blank');
    }

    @IsTest
    static void fieldName_staysWithinTheFortyCharacterBudget() {

        String stage = 'Awaiting Countersignature Review';

        for (String prefix : TPC_StageFieldNames.ALL_PREFIXES) {

            String name = TPC_StageFieldNames.fieldName(prefix, stage);

            Assert.isTrue(
                name.endsWith('__c'),
                'Generated name should carry the custom field suffix: ' + name
            );

            Assert.isTrue(
                name.removeEnd('__c').length() <= 40,
                'Generated name exceeded the 40 character budget: ' + name
            );

            Assert.isFalse(
                name.removeEnd('__c').endsWith('_'),
                'Truncation must not leave a trailing underscore: ' + name
            );
        }
    }

    @IsTest
    static void fieldName_matchesThePackagedFixtureFields() {

        // These are the names actually deployed on Stage_Tracking_Demo__c. If the
        // algorithm drifts, the runtime service stops finding the fields the
        // generator created — the failure this class exists to prevent.
        Map<String, Schema.SObjectField> fieldMap =
            Stage_Tracking_Demo__c.SObjectType.getDescribe().fields.getMap();

        List<String> stages = new List<String>{
            'Draft', 'In Review', 'Approved', 'Awaiting Countersignature Review'
        };

        for (String stage : stages) {
            for (String name : TPC_StageFieldNames.allFieldNames(stage)) {

                Assert.isTrue(
                    fieldMap.containsKey(name.toLowerCase()),
                    'Computed name does not exist on the fixture object: ' + name
                );
            }
        }
    }

    @IsTest
    static void isUsableStage_rejectsNamesThatCannotBecomeApiNames() {

        Assert.isFalse(
            TPC_StageFieldNames.isUsableStage('123'),
            'A field API name cannot start with a digit'
        );

        Assert.isFalse(
            TPC_StageFieldNames.isUsableStage('!!!'),
            'A label of only punctuation sanitises to nothing'
        );

        Assert.isTrue(
            TPC_StageFieldNames.isUsableStage('Closed Won'),
            'An ordinary label should be usable'
        );
    }

    @IsTest
    static void allFieldNames_returnsOnePerTrackedMeasure() {
        Assert.areEqual(
            4,
            TPC_StageFieldNames.allFieldNames('Draft').size(),
            'Each stage has entered, exited, latest and cumulative fields'
        );
    }
}
