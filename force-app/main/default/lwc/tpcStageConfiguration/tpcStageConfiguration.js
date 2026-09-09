import { LightningElement, wire } from 'lwc';
import { refreshApex } from '@salesforce/apex';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

import getObjects from '@salesforce/apex/TPC_StageConfigurationController.getObjects';
import getPicklistFields from '@salesforce/apex/TPC_StageConfigurationController.getPicklistFields';
import getPicklistValues from '@salesforce/apex/TPC_StageConfigurationController.getPicklistValues';
import getConfigurations from '@salesforce/apex/TPC_StageConfigurationController.getConfigurations';
import saveConfiguration from '@salesforce/apex/TPC_StageConfigurationController.saveConfiguration';
import deleteConfiguration from '@salesforce/apex/TPC_StageConfigurationController.deleteConfiguration';
import updateDoNotPrefill from '@salesforce/apex/TPC_StageConfigurationController.updateDoNotPrefill';
import generateFields from '@salesforce/apex/TPC_StageConfigurationController.generateFields';

const COLUMNS = [
    { label: 'Object', fieldName: 'objectLabel' },
    { label: 'Field', fieldName: 'stageFieldApiName' },
    { label: 'Value', fieldName: 'stageValue' },
    { label: 'Active', fieldName: 'active', type: 'boolean', initialWidth: 90 },
    { label: 'Auto create', fieldName: 'autoCreateField', type: 'boolean', initialWidth: 120 },
    {
        label: 'Do not prefill',
        fieldName: 'doNotPrefill',
        type: 'boolean',
        editable: true,
        initialWidth: 140
    },
    {
        type: 'action',
        typeAttributes: {
            rowActions: [
                { label: 'Edit', name: 'edit' },
                { label: 'Delete', name: 'delete' }
            ]
        }
    }
];

export default class TpcStageConfiguration extends LightningElement {
    columns = COLUMNS;

    objectOptions = [];
    fieldOptions = [];
    valueOptions = [];
    configurations = [];
    draftValues = [];

    objectApi = '';
    fieldApi = '';
    stageValue = '';
    active = true;
    autoCreate = true;

    editingId = null;
    isLoading = false;

    wiredConfigurations;

    // ------------------------------------------------------------- lifecycle

    connectedCallback() {
        this.loadObjects();
    }

    @wire(getConfigurations)
    handleWiredConfigurations(result) {
        this.wiredConfigurations = result;

        if (result.data) {
            this.configurations = result.data;
        } else if (result.error) {
            this.showError(result.error);
        }
    }

    // ---------------------------------------------------------------- getters

    get hasConfigurations() {
        return this.configurations && this.configurations.length > 0;
    }

    get isSaveDisabled() {
        return this.isLoading || !this.objectApi || !this.fieldApi || !this.stageValue;
    }

    get isFieldDisabled() {
        return !this.objectApi;
    }

    get isValueDisabled() {
        return !this.fieldApi;
    }

    get saveLabel() {
        return this.editingId ? 'Update' : 'Save';
    }

    // ---------------------------------------------------------------- loading

    async loadObjects() {
        try {
            this.objectOptions = await getObjects();
        } catch (error) {
            this.showError(error);
        }
    }

    async loadFields() {
        try {
            this.fieldOptions = await getPicklistFields({ objectApi: this.objectApi });
        } catch (error) {
            this.showError(error);
        }
    }

    async loadValues() {
        try {
            this.valueOptions = await getPicklistValues({
                objectApi: this.objectApi,
                fieldApi: this.fieldApi
            });
        } catch (error) {
            this.showError(error);
        }
    }

    // --------------------------------------------------------------- handlers

    handleObjectChange(event) {
        this.objectApi = event.detail.value;
        this.fieldApi = '';
        this.stageValue = '';
        this.fieldOptions = [];
        this.valueOptions = [];
        this.loadFields();
    }

    handleFieldChange(event) {
        this.fieldApi = event.detail.value;
        this.stageValue = '';
        this.valueOptions = [];
        this.loadValues();
    }

    handleValueChange(event) {
        this.stageValue = event.detail.value;
    }

    handleActiveChange(event) {
        this.active = event.target.checked;
    }

    handleAutoCreateChange(event) {
        this.autoCreate = event.target.checked;
    }

    async handleSave() {
        if (this.isSaveDisabled) {
            return;
        }

        this.isLoading = true;

        try {
            await saveConfiguration({
                recordId: this.editingId,
                objectApi: this.objectApi,
                fieldApi: this.fieldApi,
                stageValue: this.stageValue,
                active: this.active,
                autoCreate: this.autoCreate
            });

            this.showToast('Saved', 'Configuration saved.', 'success');
            this.handleReset();
            await refreshApex(this.wiredConfigurations);
        } catch (error) {
            this.showError(error);
        } finally {
            this.isLoading = false;
        }
    }

    /**
     * Field creation is a separate, explicit action rather than a side effect of
     * saving. It writes schema to the org, so it should be something the
     * administrator chooses to do and can see the result of.
     */
    async handleGenerateFields() {
        this.isLoading = true;

        try {
            const summary = await generateFields();
            this.showToast(
                'Field generation started',
                this.describeGeneration(summary),
                summary.queued > 0 ? 'success' : 'info'
            );
        } catch (error) {
            this.showError(error);
        } finally {
            this.isLoading = false;
        }
    }

    describeGeneration(summary) {
        if (!summary || !summary.queued) {
            return 'Every configured stage already has its tracking fields.';
        }

        const parts = [`${summary.queued} field(s) queued for creation.`];

        if (summary.remaining) {
            parts.push(
                `${summary.remaining} configuration(s) were not reached this run — run it again once these finish.`
            );
        }

        if (summary.skipped) {
            parts.push(`${summary.skipped} configuration(s) were skipped.`);
        }

        return parts.join(' ');
    }

    handleReset() {
        this.editingId = null;
        this.objectApi = '';
        this.fieldApi = '';
        this.stageValue = '';
        this.fieldOptions = [];
        this.valueOptions = [];
        this.active = true;
        this.autoCreate = true;
    }

    handleRowAction(event) {
        const action = event.detail.action.name;
        const row = event.detail.row;

        if (action === 'edit') {
            this.startEdit(row);
        } else if (action === 'delete') {
            this.removeConfiguration(row.id);
        }
    }

    async startEdit(row) {
        this.isLoading = true;

        try {
            this.editingId = row.id;
            this.objectApi = row.objectApiName;
            this.active = row.active;
            this.autoCreate = row.autoCreateField;

            this.fieldOptions = await getPicklistFields({ objectApi: this.objectApi });
            this.fieldApi = row.stageFieldApiName;

            this.valueOptions = await getPicklistValues({
                objectApi: this.objectApi,
                fieldApi: this.fieldApi
            });
            this.stageValue = row.stageValue;
        } catch (error) {
            this.showError(error);
        } finally {
            this.isLoading = false;
        }
    }

    async removeConfiguration(recordId) {
        this.isLoading = true;

        try {
            await deleteConfiguration({ recordId });
            this.showToast('Deleted', 'Configuration deleted.', 'success');
            await refreshApex(this.wiredConfigurations);
        } catch (error) {
            this.showError(error);
        } finally {
            this.isLoading = false;
        }
    }

    async handleInlineSave(event) {
        const drafts = event.detail.draftValues;

        if (!drafts || drafts.length === 0) {
            return;
        }

        this.isLoading = true;

        const valuesByRecordId = {};
        drafts.forEach((draft) => {
            valuesByRecordId[draft.id] = draft.doNotPrefill;
        });

        try {
            await updateDoNotPrefill({ valuesByRecordId });
            this.draftValues = [];
            this.showToast('Saved', 'Configurations updated.', 'success');
            await refreshApex(this.wiredConfigurations);
        } catch (error) {
            // Leave the drafts in place so the edits are not silently lost.
            this.showError(error);
        } finally {
            this.isLoading = false;
        }
    }

    // ----------------------------------------------------------------- toasts

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }

    showError(error) {
        this.dispatchEvent(
            new ShowToastEvent({
                title: 'Something went wrong',
                message: this.reduceError(error),
                variant: 'error',
                mode: 'sticky'
            })
        );
    }

    reduceError(error) {
        if (!error) {
            return 'Unknown error.';
        }

        if (Array.isArray(error.body)) {
            return error.body.map((e) => e.message).join(', ');
        }

        if (error.body && typeof error.body.message === 'string') {
            return error.body.message;
        }

        return error.message || 'Unknown error.';
    }
}
