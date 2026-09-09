/** Outcome of one attempted field creation. */
public inherited sharing class TPC_FieldDeployResult {

    public String fullName;
    public Boolean success;
    public String message;

    public TPC_FieldDeployResult(String fullName, Boolean success, String message) {
        this.fullName = fullName;
        this.success = success;
        this.message = message;
    }
}
