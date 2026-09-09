/** Payloads exchanged with the tpcStageConfiguration component. */
public inherited sharing class TPC_StageConfigurationWrapper {

    public class Option {

        @AuraEnabled
        public String label;

        @AuraEnabled
        public String value;

        public Option() {
        }

        public Option(String label, String value) {
            this.label = label;
            this.value = value;
        }
    }

    public class ConfigurationRow {

        @AuraEnabled
        public Id id;

        @AuraEnabled
        public String objectApiName;

        @AuraEnabled
        public String objectLabel;

        @AuraEnabled
        public String stageFieldApiName;

        @AuraEnabled
        public String stageValue;

        @AuraEnabled
        public Boolean active;

        @AuraEnabled
        public Boolean autoCreateField;

        @AuraEnabled
        public Boolean doNotPrefill;
    }

    /** Reported back after a field-generation run so the UI can be truthful. */
    public class GenerationSummary {

        @AuraEnabled
        public Integer queued = 0;

        @AuraEnabled
        public Integer remaining = 0;

        @AuraEnabled
        public Integer skipped = 0;
    }
}
