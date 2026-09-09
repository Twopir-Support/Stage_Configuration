/**
 * Single source of truth for the API names of generated stage-tracking fields.
 *
 * Both the class that CREATES these fields (TPC_StageFieldGeneratorService) and
 * the class that READS them at runtime (TPC_StageTrackingService) derive names
 * here. They previously had separate implementations that disagreed on two
 * points — trailing underscores, and whether to truncate at 40 characters — so
 * any stage label long enough to be truncated produced fields that were created
 * and then never populated, silently and with no error.
 */
public inherited sharing class TPC_StageFieldNames {

    /**
     * A custom field API name is capped at 43 characters including the '__c'
     * suffix, leaving 40 for the generated portion. This is a platform limit the
     * algorithm is built around, not business configuration, so it stays a
     * constant rather than moving to Custom Metadata.
     */
    @TestVisible
    private static final Integer MAX_BASE_LENGTH = 40;

    public static final String ENTERED_PREFIX = 'Date_Entered_';
    public static final String EXITED_PREFIX = 'Date_Exited_';
    public static final String LATEST_PREFIX = 'Latest_Time_';
    public static final String CUMULATIVE_PREFIX = 'Cumulative_Time_';

    public static final List<String> ALL_PREFIXES = new List<String>{
        ENTERED_PREFIX,
        EXITED_PREFIX,
        LATEST_PREFIX,
        CUMULATIVE_PREFIX
    };

    /**
     * Reduces a picklist label to the identifier fragment used in field names.
     * Non-alphanumerics collapse to single underscores; leading and trailing
     * underscores are removed because neither is valid in a field API name.
     */
    public static String sanitize(String stageValue) {

        if (String.isBlank(stageValue)) {
            return '';
        }

        String api = stageValue.trim().replaceAll('[^A-Za-z0-9]', '_');

        while (api.contains('__')) {
            api = api.replace('__', '_');
        }

        while (api.startsWith('_')) {
            api = api.substring(1);
        }

        while (api.endsWith('_')) {
            api = api.substring(0, api.length() - 1);
        }

        return api;
    }

    /**
     * The field API name without the '__c' suffix, truncated to fit.
     * Returns blank when the stage cannot yield a usable name.
     */
    public static String baseName(String prefix, String stageValue) {

        String stage = sanitize(stageValue);

        if (String.isBlank(stage)) {
            return '';
        }

        String raw = prefix + stage;

        if (raw.length() > MAX_BASE_LENGTH) {
            raw = raw.substring(0, MAX_BASE_LENGTH);
        }

        // Truncation can land on an underscore, which is not a valid ending.
        while (raw.endsWith('_')) {
            raw = raw.substring(0, raw.length() - 1);
        }

        return raw;
    }

    /** The full field API name, including the '__c' suffix. */
    public static String fieldName(String prefix, String stageValue) {

        String base = baseName(prefix, stageValue);

        return String.isBlank(base) ? '' : base + '__c';
    }

    public static String enteredField(String stageValue) {
        return fieldName(ENTERED_PREFIX, stageValue);
    }

    public static String exitedField(String stageValue) {
        return fieldName(EXITED_PREFIX, stageValue);
    }

    public static String latestField(String stageValue) {
        return fieldName(LATEST_PREFIX, stageValue);
    }

    public static String cumulativeField(String stageValue) {
        return fieldName(CUMULATIVE_PREFIX, stageValue);
    }

    /** Every generated field name for one stage value. */
    public static List<String> allFieldNames(String stageValue) {

        List<String> names = new List<String>();

        for (String prefix : ALL_PREFIXES) {

            String name = fieldName(prefix, stageValue);

            if (String.isNotBlank(name)) {
                names.add(name);
            }
        }

        return names;
    }

    /**
     * Whether a stage label can produce a valid field API name at all.
     * A label of '123' or '!!!' cannot — the first would start with a digit and
     * the second sanitises to nothing. Catching that here makes it an
     * attributable skip rather than a deployment error much later.
     */
    public static Boolean isUsableStage(String stageValue) {

        String stage = sanitize(stageValue);

        if (String.isBlank(stage)) {
            return false;
        }

        return !stage.substring(0, 1).isNumeric();
    }
}
