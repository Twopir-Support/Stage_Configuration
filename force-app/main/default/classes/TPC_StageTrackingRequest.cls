/**
 * One stage transition to be recorded.
 *
 * Kept as a named class rather than an inner type because it is the shape an
 * @InvocableMethod would take if per-object Flow configuration is added in a
 * later version. Members would need to be global at that point; they are public
 * now because nothing outside the package touches them.
 */
public inherited sharing class TPC_StageTrackingRequest {

    public Id recordId;
    public String objectApiName;
    public String stageFieldApiName;
    public String oldStage;
    public String newStage;

    public TPC_StageTrackingRequest() {
    }

    public TPC_StageTrackingRequest(
        Id recordId,
        String objectApiName,
        String stageFieldApiName,
        String oldStage,
        String newStage
    ) {
        this.recordId = recordId;
        this.objectApiName = objectApiName;
        this.stageFieldApiName = stageFieldApiName;
        this.oldStage = oldStage;
        this.newStage = newStage;
    }

    /**
     * Requests are de-duplicated on record AND stage field. Keying on record
     * alone silently discarded the second field's transition whenever an object
     * tracked more than one picklist.
     */
    public String dedupeKey() {
        return String.valueOf(this.recordId) + '|' +
            (this.stageFieldApiName == null ? '' : this.stageFieldApiName.toLowerCase());
    }
}
