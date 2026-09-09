/** One custom field the package intends to create in the subscriber org. */
public inherited sharing class TPC_FieldDefinition {

    public String objectApiName;
    public String fieldApiName;      // includes the '__c' suffix
    public String label;
    public String fieldType;         // 'DateTime' or 'Number'
    public Integer precision;
    public Integer scale;

    public TPC_FieldDefinition(
        String objectApiName,
        String fieldApiName,
        String label,
        String fieldType
    ) {
        this.objectApiName = objectApiName;
        this.fieldApiName = fieldApiName;
        this.label = label;
        this.fieldType = fieldType;

        if (fieldType == 'Number') {
            this.precision = 18;
            this.scale = 2;
        }
    }

    public String fullName() {
        return objectApiName + '.' + fieldApiName;
    }
}
