# Stage Tracking

Measures how long a record spends in each value of a picklist. For every tracked
value the package maintains four fields on the object:

| Field | Meaning |
|---|---|
| `Date_Entered_<Stage>__c` | When the record most recently entered the value |
| `Date_Exited_<Stage>__c` | When it most recently left |
| `Latest_Time_<Stage>__c` | Hours spent on the most recent visit |
| `Cumulative_Time_<Stage>__c` | Hours spent across every visit |

Administrators choose what to track from the **Stage Tracking** tab. The package
creates the four fields on demand.

---

## Packaging model

Managed 2GP, private distribution. Not listed on AppExchange.

### Why triggers ship with the package

Tracking needs an `after update` trigger on each object. Salesforce does not
permit Apex to be created in a production org through any interface, so a
subscriber org cannot be given new triggers at runtime — an earlier design that
POSTed trigger bodies to the Tooling API worked in sandboxes and failed for
every real customer.

Triggers are therefore packaged, one per supported object:

- Opportunity
- Lead
- Case
- Account
- Contact
- Stage Tracking Demo (the shipped reference object)

**Adding an object is a package release.** Each has a
`Stage_Trigger_Control__mdt` record; unchecking `Is_Active__c` disables tracking
for that object with no deployment.

Field creation is different. Schema changes *are* permitted in production —
administrators create custom fields in Setup routinely — so tracking fields are
still created on demand, through the Tooling API's `CustomField` resource behind
`TPC_FieldDeployer`.

---

## Installing

1. **Install the package.**
2. **Point the Named Credential at the org.** Open
   `TPC_Stage_Tracking_Metadata` in Setup and set the URL to the org's own My
   Domain (`https://<your-domain>.my.salesforce.com`). It ships with a
   placeholder because the value differs in every org.
3. **Authenticate the External Credential.** Same name, principal
   `StageTrackingAdmin`. One-time, done by an administrator.
4. **Assign permission sets.**
   - `Stage Tracking Administrator` — anyone configuring tracking. Grants the
     tab, the configuration object, and the `Manage_Stage_Tracking` custom
     permission that every controller method checks.
   - `Stage Tracking Bypass` — data-load and integration users, so a bulk import
     does not rewrite stage history. Grants nothing else.
5. **Configure and generate.** Open the tab, add the values worth measuring, then
   press **Generate tracking fields**.

Field generation is a separate, explicit action rather than a side effect of
saving, because it writes schema to the org.

---

## Development

```bash
npm install                       # Jest for the LWC
sf org create scratch -f config/project-scratch-def.json -a stagetracking
sf project deploy start -o stagetracking
sf apex run test -o stagetracking -l RunLocalTests -w 20
npm test                          # LWC Jest suite
```

Everything in the Apex suite runs against `Stage_Tracking_Demo__c`, which ships
with a stage picklist and its tracking fields already built. That matters: the
previous suite bound to whatever Opportunity stages happened to have generated
fields in the org it ran in, so it could not pass in a clean org — and package
version creation always runs in a clean one.

The demo object also carries a deliberately long stage value, *Awaiting
Countersignature Review*, whose field names exceed the 40-character budget and
must be truncated. It exists to keep the generator and the runtime engine
agreeing on names.

### Layout

```
force-app/main/default/
├── classes/           TPC_*.cls
├── triggers/          one per supported object, no logic
├── lwc/               tpcStageConfiguration
├── objects/           Stage_Configuration__c, Stage_Trigger_Control__mdt,
│                      Package_Error__e, Stage_Tracking_Demo__c
├── customMetadata/    supported-object control records
├── permissionsets/    Administrator, Bypass
├── customPermissions/ Manage_Stage_Tracking, Bypass_Stage_Tracking
├── namedCredentials/  TPC_Stage_Tracking_Metadata
└── tabs/, flexipages/
```

### Naming

Apex classes carry the `TPC_` prefix and the LWC carries `tpc`. Objects, fields,
permission sets and custom permissions do not — the package namespace already
prefixes them, and adding `TPC_` on top produces `ns__TPC_Thing__c`.

One API version, `62.0`, set in `sfdx-project.json` and every `-meta.xml`.

---

## What changed from the original implementation

**Corrected**

- Cumulative time was cleared whenever a record re-entered a stage, so any record
  that moved backwards and forwards again reported only its most recent visit.
- The class that created fields and the class that read them sanitised names
  differently — they disagreed on truncation and on trailing underscores — so any
  stage label over roughly 24 characters produced fields that were created and
  then never populated, silently. Both now derive names from
  `TPC_StageFieldNames`.
- Transitions were keyed by record Id alone, so an object tracking two picklists
  lost one of them whenever both changed in the same save.
- Generation capped *configuration records* at 200 with no ordering and no
  scheduled follow-up, so configuration 201 was never reached. It now caps fields
  and reports what it could not get to, which converges across runs.
- One request per configuration record meant a field with eight tracked values
  produced eight identical requests per record.

**Secured**

- Every `@AuraEnabled` method now checks the `Manage_Stage_Tracking` custom
  permission. Previously any authenticated user could enumerate every object in
  the org, write configuration, delete it, or start a metadata deployment.
- Queries and DML declare their access mode: `WITH USER_MODE` / `as user` in the
  controller, `as system` with a comment in the tracking engine, where recording
  a transition should not depend on the acting user's access to the tracking
  fields.
- Callouts authenticate through a Named Credential. The previous implementation
  put `UserInfo.getSessionId()` in a SOAP header, which returns null in
  asynchronous Apex — the queueable returned early on every run while the UI
  reported success.

**Removed**

- `DynamicTriggerDeployer`, `ToolingApiService`, `RetryTriggerDeployment`,
  `StageTriggerControlMetadataService` and `StageTriggerControlDeployCallback` —
  all served runtime trigger creation, which cannot work in a subscriber
  production org.
- `StageTrackingMetadataService`, a ~6,000-line vendored copy of the
  FinancialForce apex-mdapi SOAP stub pinned to API 38.0, a retired version.
  Replaced by ~150 lines of Tooling REST. The BSD-3 dependency goes with it.

**Reworked**

- Error logging publishes `Package_Error__e` with `PublishImmediately`. The
  previous logger inserted a row from catch blocks that then re-threw, so the log
  rolled back with the transaction it was recording.
- The component uses `lwc:if`, shows its empty state correctly, saves inline
  edits in one call rather than one per row, handles every rejection, and no
  longer logs payloads to the browser console.

---

## Open items

- **Namespace.** `sfdx-project.json` carries an empty `namespace`. Register one on
  the Dev Hub and set it before the first package version.
- **Tooling API field creation in production.** Documented as available for
  schema, unlike Apex, but worth confirming in a real subscriber org during the
  first install rehearsal. `TPC_FieldDeployer` exists so a SOAP Metadata API
  implementation can replace it without touching the generator.
- **Uninstall.** Packaged triggers leave with the package. Generated tracking
  fields stay behind by design — they hold customer data — and should be called
  out in customer documentation.
