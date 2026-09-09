/**
 * Callout handling, including the failure cases.
 *
 * A suite that only mocks a 200 response has not tested the error handling, so
 * refusal, an already-existing field, and a transport failure are all covered.
 */
@IsTest
private class TPC_ToolingFieldDeployerTest {

    private class StatusMock implements HttpCalloutMock {

        private final Integer status;
        private final String body;

        StatusMock(Integer status, String body) {
            this.status = status;
            this.body = body;
        }

        public HttpResponse respond(HttpRequest request) {

            Assert.isTrue(
                request.getEndpoint().startsWith('callout:TPC_Stage_Tracking_Metadata'),
                'Callouts must go through the Named Credential, not a raw URL'
            );
            Assert.areEqual('POST', request.getMethod(), 'Field creation is a POST');

            HttpResponse response = new HttpResponse();
            response.setStatusCode(status);
            response.setBody(body);
            return response;
        }
    }

    private class ThrowingMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest request) {
            throw new CalloutException('Read timed out');
        }
    }

    private static List<TPC_FieldDefinition> oneField() {
        return new List<TPC_FieldDefinition>{
            new TPC_FieldDefinition(
                'Opportunity', 'Date_Entered_Draft__c', 'Date entered Draft', 'DateTime'
            )
        };
    }

    @IsTest
    static void deploy_reportsSuccessOnCreated() {

        Test.setMock(HttpCalloutMock.class, new StatusMock(201, '{"id":"00N000000000000"}'));

        Test.startTest();
        List<TPC_FieldDeployResult> results = new TPC_ToolingFieldDeployer().deploy(oneField());
        Test.stopTest();

        Assert.areEqual(1, results.size(), 'One field in, one result out');
        Assert.isTrue(results[0].success, 'A 201 means the field was created');
        Assert.areEqual(
            'Opportunity.Date_Entered_Draft__c',
            results[0].fullName,
            'The result should name the field it refers to'
        );
    }

    @IsTest
    static void deploy_treatsAnExistingFieldAsSuccess() {

        Test.setMock(
            HttpCalloutMock.class,
            new StatusMock(400, '[{"errorCode":"DUPLICATE_DEVELOPER_NAME","message":"exists"}]')
        );

        Test.startTest();
        List<TPC_FieldDeployResult> results = new TPC_ToolingFieldDeployer().deploy(oneField());
        Test.stopTest();

        Assert.isTrue(
            results[0].success,
            'A field that already exists is the desired end state, not a failure'
        );
    }

    @IsTest
    static void deploy_reportsARefusal() {

        Test.setMock(
            HttpCalloutMock.class,
            new StatusMock(400, '[{"errorCode":"INVALID_FIELD","message":"bad type"}]')
        );

        Test.startTest();
        List<TPC_FieldDeployResult> results = new TPC_ToolingFieldDeployer().deploy(oneField());
        Test.stopTest();

        Assert.isFalse(results[0].success, 'A genuine 400 is a failure');
        Assert.isTrue(
            results[0].message.contains('INVALID_FIELD'),
            'The reason should be carried back for logging, was ' + results[0].message
        );
    }

    @IsTest
    static void deploy_reportsATransportFailure() {

        Test.setMock(HttpCalloutMock.class, new ThrowingMock());

        Test.startTest();
        List<TPC_FieldDeployResult> results = new TPC_ToolingFieldDeployer().deploy(oneField());
        Test.stopTest();

        Assert.isFalse(results[0].success, 'A timeout is a failure');
        Assert.isTrue(
            results[0].message.contains('CalloutException'),
            'The exception type should be carried back, was ' + results[0].message
        );
    }

    @IsTest
    static void deploy_withNothingToDo_makesNoCallouts() {

        Test.startTest();
        List<TPC_FieldDeployResult> empty =
            new TPC_ToolingFieldDeployer().deploy(new List<TPC_FieldDefinition>());
        List<TPC_FieldDeployResult> nothing = new TPC_ToolingFieldDeployer().deploy(null);
        Test.stopTest();

        Assert.isTrue(empty.isEmpty(), 'No definitions, no results');
        Assert.isTrue(nothing.isEmpty(), 'Null definitions, no results');
        Assert.areEqual(0, Limits.getCallouts(), 'And no callouts should have been made');
    }

    @IsTest
    static void buildBody_describesANumberFieldWithPrecisionAndScale() {

        TPC_FieldDefinition def = new TPC_FieldDefinition(
            'Opportunity', 'Cumulative_Time_Draft__c', 'Cumulative time in Draft', 'Number'
        );

        String body = new TPC_ToolingFieldDeployer().buildBody(def);

        Map<String, Object> parsed = (Map<String, Object>) JSON.deserializeUntyped(body);
        Map<String, Object> metadata = (Map<String, Object>) parsed.get('Metadata');

        Assert.areEqual(
            'Opportunity.Cumulative_Time_Draft__c',
            parsed.get('FullName'),
            'The full name locates the field on its object'
        );
        Assert.areEqual('Number', metadata.get('type'), 'Durations are numbers');
        Assert.areEqual(18, metadata.get('precision'), 'Precision should be sent');
        Assert.areEqual(2, metadata.get('scale'), 'Scale should be sent');
    }

    @IsTest
    static void buildBody_omitsPrecisionForDateTimeFields() {

        TPC_FieldDefinition def = new TPC_FieldDefinition(
            'Opportunity', 'Date_Entered_Draft__c', 'Date entered Draft', 'DateTime'
        );

        Map<String, Object> parsed = (Map<String, Object>) JSON.deserializeUntyped(
            new TPC_ToolingFieldDeployer().buildBody(def)
        );
        Map<String, Object> metadata = (Map<String, Object>) parsed.get('Metadata');

        Assert.isFalse(
            metadata.containsKey('precision'),
            'A date/time field has no precision'
        );
    }
}
