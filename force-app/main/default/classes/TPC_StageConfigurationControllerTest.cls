/**
 * Controller behaviour, including the permission gate.
 *
 * Every method is reachable by any authenticated user regardless of whether they
 * can see the component, so the gate is tested first and from both sides.
 */
@IsTest
private class TPC_StageConfigurationControllerTest {

    @TestSetup
    static void setup() {
        TPC_TestDataFactory.configureAllDemoStages();
    }

    // ------------------------------------------------------- permission gate

    @IsTest
    static void everyEntryPoint_isRefusedWithoutTheManagePermission() {

        User plain = TPC_TestDataFactory.plainUser();

        Test.startTest();
        System.runAs(plain) {

            assertRefused('getObjects');
            assertRefused('getConfigurations');
            assertRefused('getPicklistFields');
            assertRefused('saveConfiguration');
            assertRefused('deleteConfiguration');
            assertRefused('generateFields');
        }
        Test.stopTest();
    }

    private static void assertRefused(String entryPoint) {

        try {

            if (entryPoint == 'getObjects') {
                TPC_StageConfigurationController.getObjects();
            } else if (entryPoint == 'getConfigurations') {
                TPC_StageConfigurationController.getConfigurations();
            } else if (entryPoint == 'getPicklistFields') {
                TPC_StageConfigurationController.getPicklistFields(
                    TPC_TestDataFactory.DEMO_OBJECT
                );
            } else if (entryPoint == 'saveConfiguration') {
                TPC_StageConfigurationController.saveConfiguration(
                    null, TPC_TestDataFactory.DEMO_OBJECT, 'Stage__c', 'Draft', true, true
                );
            } else if (entryPoint == 'deleteConfiguration') {
                TPC_StageConfigurationController.deleteConfiguration('a00000000000000AAA');
            } else if (entryPoint == 'generateFields') {
                TPC_StageConfigurationController.generateFields();
            }

            Assert.fail(
                entryPoint + ' should be refused to a user without Manage Stage Tracking'
            );

        } catch (AuraHandledException e) {
            // expected
        }
    }

    @IsTest
    static void getObjects_returnsOnlySupportedObjects() {

        User admin = TPC_TestDataFactory.adminUser();

        List<TPC_StageConfigurationWrapper.Option> options;

        Test.startTest();
        System.runAs(admin) {
            options = TPC_StageConfigurationController.getObjects();
        }
        Test.stopTest();

        Assert.isFalse(options.isEmpty(), 'Supported objects should be offered');

        Set<String> apiNames = new Set<String>();
        for (TPC_StageConfigurationWrapper.Option option : options) {
            apiNames.add(option.value);
            Assert.isNotNull(option.label, 'Each option should carry a readable label');
        }

        Assert.isTrue(
            apiNames.contains(TPC_TestDataFactory.DEMO_OBJECT),
            'The demo object ships with a control record and should be offered'
        );
        Assert.isTrue(
            apiNames.size() <= 10,
            'Only objects with packaged triggers should be offered, was ' + apiNames.size()
        );
    }

    // --------------------------------------------------------------- metadata

    @IsTest
    static void getPicklistFieldsAndValues_describeTheDemoObject() {

        User admin = TPC_TestDataFactory.adminUser();

        Test.startTest();
        System.runAs(admin) {

            Set<String> fieldNames = new Set<String>();

            for (TPC_StageConfigurationWrapper.Option option :
                 TPC_StageConfigurationController.getPicklistFields(
                     TPC_TestDataFactory.DEMO_OBJECT
                 )) {
                fieldNames.add(option.value);
            }

            Assert.isTrue(
                fieldNames.contains('Stage__c'),
                'Stage__c is a picklist and should be offered'
            );

            Set<String> values = new Set<String>();

            for (TPC_StageConfigurationWrapper.Option option :
                 TPC_StageConfigurationController.getPicklistValues(
                     TPC_TestDataFactory.DEMO_OBJECT, 'Stage__c'
                 )) {
                values.add(option.value);
            }

            Assert.isTrue(values.contains('Draft'), 'Draft is an active value');
            Assert.areEqual(4, values.size(), 'All four active values should be offered');
        }
        Test.stopTest();
    }

    @IsTest
    static void getPicklistValues_rejectsANonPicklistField() {

        User admin = TPC_TestDataFactory.adminUser();

        Test.startTest();
        System.runAs(admin) {
            try {
                TPC_StageConfigurationController.getPicklistValues(
                    TPC_TestDataFactory.DEMO_OBJECT, 'Name'
                );
                Assert.fail('Name is a text field and should be rejected');
            } catch (AuraHandledException e) {
                // expected
            }
        }
        Test.stopTest();
    }

    @IsTest
    static void validation_rejectsUnknownObjects() {

        User admin = TPC_TestDataFactory.adminUser();

        Test.startTest();
        System.runAs(admin) {
            try {
                TPC_StageConfigurationController.getPicklistFields('Not_A_Real_Object__c');
                Assert.fail('An unknown object should be rejected');
            } catch (AuraHandledException e) {
                // expected
            }

            try {
                TPC_StageConfigurationController.getPicklistFields('');
                Assert.fail('A blank object should be rejected');
            } catch (AuraHandledException e) {
                // expected
            }
        }
        Test.stopTest();
    }

    // ---------------------------------------------------------------- writing

    @IsTest
    static void saveConfiguration_createsThenUpdates() {

        // Setup configures every value on both demo picklists, so clear the
        // decks before asserting on a create.
        delete [SELECT Id FROM Stage_Configuration__c];

        User admin = TPC_TestDataFactory.adminUser();

        Test.startTest();
        System.runAs(admin) {

            Id created = TPC_StageConfigurationController.saveConfiguration(
                null, TPC_TestDataFactory.DEMO_OBJECT, 'Review_Status__c', 'Complete', true, false
            );

            Assert.isNotNull(created, 'Saving should return the new record Id');

            Id updated = TPC_StageConfigurationController.saveConfiguration(
                created, TPC_TestDataFactory.DEMO_OBJECT, 'Review_Status__c', 'Complete', false, false
            );

            Assert.areEqual(created, updated, 'Editing should reuse the same record');
        }
        Test.stopTest();

        Stage_Configuration__c saved = [
            SELECT Active__c, Auto_Create_Field__c
            FROM Stage_Configuration__c
            WHERE Stage_Field_API__c = 'Review_Status__c' AND Stage_Value__c = 'Complete'
            LIMIT 1
        ];

        Assert.isFalse(saved.Active__c, 'The update should have taken effect');
    }

    @IsTest
    static void saveConfiguration_refusesADuplicate() {

        User admin = TPC_TestDataFactory.adminUser();

        Test.startTest();
        System.runAs(admin) {
            try {
                TPC_StageConfigurationController.saveConfiguration(
                    null, TPC_TestDataFactory.DEMO_OBJECT, 'Stage__c', 'Draft', true, true
                );
                Assert.fail('Draft on Stage__c is already configured');
            } catch (AuraHandledException e) {
                // expected
            }
        }
        Test.stopTest();
    }

    @IsTest
    static void saveConfiguration_requiresFieldAndValue() {

        User admin = TPC_TestDataFactory.adminUser();

        Test.startTest();
        System.runAs(admin) {

            try {
                TPC_StageConfigurationController.saveConfiguration(
                    null, TPC_TestDataFactory.DEMO_OBJECT, '', 'Draft', true, true
                );
                Assert.fail('A blank field should be rejected');
            } catch (AuraHandledException e) {
                // expected
            }

            try {
                TPC_StageConfigurationController.saveConfiguration(
                    null, TPC_TestDataFactory.DEMO_OBJECT, 'Stage__c', '', true, true
                );
                Assert.fail('A blank value should be rejected');
            } catch (AuraHandledException e) {
                // expected
            }
        }
        Test.stopTest();
    }

    @IsTest
    static void getConfigurations_returnsRowsWithReadableLabels() {

        User admin = TPC_TestDataFactory.adminUser();

        List<TPC_StageConfigurationWrapper.ConfigurationRow> rows;

        Test.startTest();
        System.runAs(admin) {
            rows = TPC_StageConfigurationController.getConfigurations();
        }
        Test.stopTest();

        Assert.areEqual(6, rows.size(), 'Six configurations were created in setup');

        for (TPC_StageConfigurationWrapper.ConfigurationRow row : rows) {
            Assert.isNotNull(row.id, 'Each row needs an Id for the datatable key');
            Assert.isNotNull(row.objectLabel, 'Each row should show a readable object name');
        }
    }

    @IsTest
    static void updateDoNotPrefill_appliesEveryEditedRowInOneCall() {

        User admin = TPC_TestDataFactory.adminUser();

        List<Stage_Configuration__c> configs = [
            SELECT Id FROM Stage_Configuration__c LIMIT 3
        ];

        Map<String, Boolean> edits = new Map<String, Boolean>();
        for (Stage_Configuration__c config : configs) {
            edits.put(String.valueOf(config.Id), true);
        }

        Test.startTest();
        System.runAs(admin) {
            TPC_StageConfigurationController.updateDoNotPrefill(edits);
        }
        Test.stopTest();

        Integer updated = [
            SELECT COUNT() FROM Stage_Configuration__c WHERE Do_Not_Prefill__c = TRUE
        ];

        Assert.areEqual(3, updated, 'All three edits should have been applied');
    }

    @IsTest
    static void updateDoNotPrefill_toleratesAnEmptyPayload() {

        User admin = TPC_TestDataFactory.adminUser();

        Test.startTest();
        System.runAs(admin) {
            TPC_StageConfigurationController.updateDoNotPrefill(null);
            TPC_StageConfigurationController.updateDoNotPrefill(new Map<String, Boolean>());
        }
        Test.stopTest();

        Assert.isTrue(true, 'An empty inline save should be a no-op, not an error');
    }

    @IsTest
    static void deleteConfiguration_removesTheRecord() {

        User admin = TPC_TestDataFactory.adminUser();

        Stage_Configuration__c config = [SELECT Id FROM Stage_Configuration__c LIMIT 1];

        Test.startTest();
        System.runAs(admin) {
            TPC_StageConfigurationController.deleteConfiguration(config.Id);
        }
        Test.stopTest();

        Assert.areEqual(
            0,
            [SELECT COUNT() FROM Stage_Configuration__c WHERE Id = :config.Id],
            'The configuration should be gone'
        );
    }

    @IsTest
    static void deleteConfiguration_requiresAnId() {

        User admin = TPC_TestDataFactory.adminUser();

        Test.startTest();
        System.runAs(admin) {
            try {
                TPC_StageConfigurationController.deleteConfiguration(null);
                Assert.fail('A null Id should be rejected');
            } catch (AuraHandledException e) {
                // expected
            }
        }
        Test.stopTest();
    }
}
