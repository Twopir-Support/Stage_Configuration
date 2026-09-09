/**
 * Creates custom fields through the Tooling API's CustomField resource.
 *
 * Authenticates through a Named Credential pointing at the org itself. The
 * previous implementation put UserInfo.getSessionId() in a SOAP session header,
 * which returns null in asynchronous Apex — so the Queueable that called it
 * returned early on every single run while the UI still reported success.
 *
 * Note on production orgs: Salesforce bars the creation of Apex through any
 * interface in production, which is why this package ships static triggers. That
 * restriction is specific to code. Schema changes are permitted in production —
 * administrators create custom fields in Setup routinely — so field creation
 * through the API is available where trigger creation is not.
 */
public with sharing class TPC_ToolingFieldDeployer implements TPC_FieldDeployer {

    private static final String NAMED_CREDENTIAL = 'callout:TPC_Stage_Tracking_Metadata';
    private static final String API_VERSION = 'v62.0';
    private static final Integer TIMEOUT_MS = 20000;

    /**
     * The Tooling API creates one field per request. Apex allows 100 callouts per
     * transaction; the cap leaves headroom for anything else in the same context.
     */
    public static final Integer MAX_FIELDS_PER_TRANSACTION = 90;

    public List<TPC_FieldDeployResult> deploy(List<TPC_FieldDefinition> definitions) {

        List<TPC_FieldDeployResult> results = new List<TPC_FieldDeployResult>();

        if (definitions == null || definitions.isEmpty()) {
            return results;
        }

        Integer processed = 0;

        for (TPC_FieldDefinition def : definitions) {

            if (processed >= MAX_FIELDS_PER_TRANSACTION) {
                break;
            }

            processed++;
            results.add(createField(def));
        }

        return results;
    }

    private TPC_FieldDeployResult createField(TPC_FieldDefinition def) {

        try {

            HttpRequest req = new HttpRequest();

            req.setEndpoint(
                NAMED_CREDENTIAL + '/services/data/' + API_VERSION +
                '/tooling/sobjects/CustomField'
            );
            req.setMethod('POST');
            req.setHeader('Content-Type', 'application/json');
            req.setTimeout(TIMEOUT_MS);
            req.setBody(buildBody(def));

            HttpResponse res = new Http().send(req);

            Integer status = res.getStatusCode();

            if (status == 201 || status == 200) {
                return new TPC_FieldDeployResult(def.fullName(), true, null);
            }

            // A field that already exists is not a failure — it is the desired
            // end state, reached by an earlier run or by an administrator.
            String body = res.getBody();

            if (status == 400 && body != null && body.contains('DUPLICATE_DEVELOPER_NAME')) {
                return new TPC_FieldDeployResult(def.fullName(), true, 'Already existed');
            }

            return new TPC_FieldDeployResult(
                def.fullName(),
                false,
                'HTTP ' + status + ': ' + body
            );

        } catch (Exception ex) {

            return new TPC_FieldDeployResult(
                def.fullName(),
                false,
                ex.getTypeName() + ': ' + ex.getMessage()
            );
        }
    }

    @TestVisible
    private String buildBody(TPC_FieldDefinition def) {

        Map<String, Object> metadata = new Map<String, Object>{
            'label' => def.label,
            'type' => def.fieldType,
            'required' => false
        };

        if (def.precision != null) {
            metadata.put('precision', def.precision);
        }

        if (def.scale != null) {
            metadata.put('scale', def.scale);
        }

        return JSON.serialize(
            new Map<String, Object>{
                'FullName' => def.fullName(),
                'Metadata' => metadata
            }
        );
    }
}
