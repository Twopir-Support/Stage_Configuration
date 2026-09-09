/**
 * Shared test data.
 *
 * Everything is built on Stage_Tracking_Demo__c, which ships with the package
 * complete with its tracking fields. The previous suite bound to whatever
 * Opportunity stages happened to have generated fields in the org it ran in, so
 * it could not pass in a clean org — and package version creation always runs in
 * a clean org.
 */
@IsTest
public class TPC_TestDataFactory {

    public static final String DEMO_OBJECT = 'Stage_Tracking_Demo__c';
    public static final String STAGE_FIELD = 'Stage__c';
    public static final String REVIEW_FIELD = 'Review_Status__c';

    public static final String DRAFT = 'Draft';
    public static final String IN_REVIEW = 'In Review';
    public static final String APPROVED = 'Approved';
    public static final String LONG_STAGE = 'Awaiting Countersignature Review';
    public static final String PENDING = 'Pending';
    public static final String COMPLETE = 'Complete';

    public static final String ADMIN_PERM_SET = 'Stage_Tracking_Administrator';
    public static final String BYPASS_PERM_SET = 'Stage_Tracking_Bypass';

    private static Integer userCounter = 0;

    /** Active configuration for every stage on both demo picklists. */
    public static void configureAllDemoStages() {

        List<Stage_Configuration__c> configs = new List<Stage_Configuration__c>();

        for (String stage : new List<String>{ DRAFT, IN_REVIEW, APPROVED, LONG_STAGE }) {
            configs.add(config(DEMO_OBJECT, STAGE_FIELD, stage));
        }

        for (String stage : new List<String>{ PENDING, COMPLETE }) {
            configs.add(config(DEMO_OBJECT, REVIEW_FIELD, stage));
        }

        insert configs;
    }

    public static Stage_Configuration__c config(
        String objectApi,
        String fieldApi,
        String stageValue
    ) {
        return new Stage_Configuration__c(
            Object_API_Name__c = objectApi,
            Stage_Field_API__c = fieldApi,
            Stage_Value__c = stageValue,
            Active__c = true,
            Auto_Create_Field__c = true,
            Do_Not_Prefill__c = false
        );
    }

    public static List<Stage_Tracking_Demo__c> demos(Integer count, String stage) {

        List<Stage_Tracking_Demo__c> records = new List<Stage_Tracking_Demo__c>();

        for (Integer i = 0; i < count; i++) {
            records.add(
                new Stage_Tracking_Demo__c(
                    Name = 'Demo ' + i,
                    Stage__c = stage,
                    Review_Status__c = PENDING
                )
            );
        }

        return records;
    }

    /**
     * A standard user with the named permission sets.
     *
     * The profile is looked up by UserType rather than by name — profile names
     * are renamed and cloned per org, so a hard-coded 'Standard User' is a
     * portability hazard in a package that runs in orgs we have never seen.
     */
    public static User standardUser(String alias, List<String> permissionSetNames) {

        Profile p = [
            SELECT Id
            FROM Profile
            WHERE UserType = 'Standard'
            ORDER BY Name
            LIMIT 1
        ];

        userCounter++;

        String unique = alias + Datetime.now().getTime() + userCounter;

        User u = new User(
            Alias = alias.left(8),
            Email = unique + '@example.invalid',
            EmailEncodingKey = 'UTF-8',
            LastName = 'Tester',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            ProfileId = p.Id,
            TimeZoneSidKey = 'GMT',
            Username = unique + '@stagetracking.test.invalid'
        );

        // User and PermissionSetAssignment are setup objects; creating them in
        // the same transaction as other DML raises MIXED_DML_OPERATION.
        System.runAs(new User(Id = UserInfo.getUserId())) {

            insert u;

            if (permissionSetNames != null && !permissionSetNames.isEmpty()) {

                List<PermissionSet> sets = [
                    SELECT Id
                    FROM PermissionSet
                    WHERE Name IN :permissionSetNames
                ];

                List<PermissionSetAssignment> assignments =
                    new List<PermissionSetAssignment>();

                for (PermissionSet ps : sets) {
                    assignments.add(
                        new PermissionSetAssignment(
                            AssigneeId = u.Id,
                            PermissionSetId = ps.Id
                        )
                    );
                }

                if (!assignments.isEmpty()) {
                    insert assignments;
                }
            }
        }

        return u;
    }

    public static User adminUser() {
        return standardUser('sta', new List<String>{ ADMIN_PERM_SET });
    }

    public static User plainUser() {
        return standardUser('stp', new List<String>());
    }
}
