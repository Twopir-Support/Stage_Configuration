/**
 * Creates custom fields in the org.
 *
 * Behind an interface so the deployment mechanism can be swapped without
 * touching the generator, and so tests can exercise the generator without a
 * callout. TPC_ToolingFieldDeployer is the shipped implementation; if Tooling
 * API field creation proves unavailable in some org, an implementation over the
 * SOAP Metadata API can be dropped in here instead.
 */
public interface TPC_FieldDeployer {

    List<TPC_FieldDeployResult> deploy(List<TPC_FieldDefinition> definitions);
}
