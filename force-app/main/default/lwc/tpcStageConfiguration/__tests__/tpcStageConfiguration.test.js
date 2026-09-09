import { createElement } from 'lwc';
import TpcStageConfiguration from 'c/tpcStageConfiguration';

import getConfigurations from '@salesforce/apex/TPC_StageConfigurationController.getConfigurations';
import getObjects from '@salesforce/apex/TPC_StageConfigurationController.getObjects';
import generateFields from '@salesforce/apex/TPC_StageConfigurationController.generateFields';

jest.mock(
    '@salesforce/apex/TPC_StageConfigurationController.getConfigurations',
    () => {
        const { createApexTestWireAdapter } = require('@salesforce/sfdx-lwc-jest');
        return { default: createApexTestWireAdapter(jest.fn()) };
    },
    { virtual: true }
);

jest.mock(
    '@salesforce/apex/TPC_StageConfigurationController.getObjects',
    () => ({ default: jest.fn() }),
    { virtual: true }
);
jest.mock(
    '@salesforce/apex/TPC_StageConfigurationController.getPicklistFields',
    () => ({ default: jest.fn() }),
    { virtual: true }
);
jest.mock(
    '@salesforce/apex/TPC_StageConfigurationController.getPicklistValues',
    () => ({ default: jest.fn() }),
    { virtual: true }
);
jest.mock(
    '@salesforce/apex/TPC_StageConfigurationController.saveConfiguration',
    () => ({ default: jest.fn() }),
    { virtual: true }
);
jest.mock(
    '@salesforce/apex/TPC_StageConfigurationController.deleteConfiguration',
    () => ({ default: jest.fn() }),
    { virtual: true }
);
jest.mock(
    '@salesforce/apex/TPC_StageConfigurationController.updateDoNotPrefill',
    () => ({ default: jest.fn() }),
    { virtual: true }
);
jest.mock(
    '@salesforce/apex/TPC_StageConfigurationController.generateFields',
    () => ({ default: jest.fn() }),
    { virtual: true }
);

const SUPPORTED_OBJECTS = [
    { label: 'Opportunity', value: 'Opportunity' },
    { label: 'Stage Tracking Demo', value: 'Stage_Tracking_Demo__c' }
];

const CONFIGURATIONS = [
    {
        id: 'a000000000000001AAA',
        objectApiName: 'Stage_Tracking_Demo__c',
        objectLabel: 'Stage Tracking Demo',
        stageFieldApiName: 'Stage__c',
        stageValue: 'Draft',
        active: true,
        autoCreateField: true,
        doNotPrefill: false
    }
];

function flushPromises() {
    return Promise.resolve();
}

describe('c-tpc-stage-configuration', () => {
    let element;

    beforeEach(() => {
        getObjects.mockResolvedValue(SUPPORTED_OBJECTS);
        element = createElement('c-tpc-stage-configuration', {
            is: TpcStageConfiguration
        });
    });

    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
        jest.clearAllMocks();
    });

    it('offers the supported objects returned by the server', async () => {
        document.body.appendChild(element);
        await flushPromises();

        const combobox = element.shadowRoot.querySelector('lightning-combobox');

        expect(getObjects).toHaveBeenCalled();
        expect(combobox.options).toEqual(SUPPORTED_OBJECTS);
    });

    it('shows the empty state when nothing is configured', async () => {
        document.body.appendChild(element);
        getConfigurations.emit([]);
        await flushPromises();

        expect(element.shadowRoot.querySelector('.empty-state')).not.toBeNull();
        expect(element.shadowRoot.querySelector('lightning-datatable')).toBeNull();
    });

    it('shows the table once something is configured', async () => {
        document.body.appendChild(element);
        getConfigurations.emit(CONFIGURATIONS);
        await flushPromises();

        const table = element.shadowRoot.querySelector('lightning-datatable');

        expect(table).not.toBeNull();
        expect(table.data).toEqual(CONFIGURATIONS);
        expect(element.shadowRoot.querySelector('.empty-state')).toBeNull();
    });

    it('keeps Save disabled until an object, field and value are chosen', async () => {
        document.body.appendChild(element);
        getConfigurations.emit([]);
        await flushPromises();

        const save = element.shadowRoot.querySelector('lightning-button[variant="brand"]');

        expect(save.disabled).toBe(true);
    });

    it('surfaces a server error as a toast rather than failing silently', async () => {
        getObjects.mockRejectedValue({ body: { message: 'Access denied' } });

        const handler = jest.fn();
        element.addEventListener('lightning__showtoast', handler);

        document.body.appendChild(element);
        await flushPromises();
        await flushPromises();

        expect(handler).toHaveBeenCalled();
        expect(handler.mock.calls[0][0].detail.variant).toBe('error');
        expect(handler.mock.calls[0][0].detail.message).toBe('Access denied');
    });

    it('surfaces a wire error as a toast', async () => {
        const handler = jest.fn();
        element.addEventListener('lightning__showtoast', handler);

        document.body.appendChild(element);
        getConfigurations.error({ body: { message: 'Query failed' } });
        await flushPromises();

        expect(handler).toHaveBeenCalled();
        expect(handler.mock.calls[0][0].detail.variant).toBe('error');
    });

    it('reports how many fields were queued when generation runs', async () => {
        generateFields.mockResolvedValue({ queued: 8, remaining: 0, skipped: 0 });

        const handler = jest.fn();
        element.addEventListener('lightning__showtoast', handler);

        document.body.appendChild(element);
        getConfigurations.emit(CONFIGURATIONS);
        await flushPromises();

        element.shadowRoot
            .querySelector('lightning-button[slot="actions"]')
            .dispatchEvent(new CustomEvent('click'));

        await flushPromises();
        await flushPromises();

        expect(generateFields).toHaveBeenCalled();
        expect(handler.mock.calls[0][0].detail.message).toContain('8 field(s) queued');
    });

    it('says so plainly when there is nothing left to generate', async () => {
        generateFields.mockResolvedValue({ queued: 0, remaining: 0, skipped: 0 });

        const handler = jest.fn();
        element.addEventListener('lightning__showtoast', handler);

        document.body.appendChild(element);
        getConfigurations.emit(CONFIGURATIONS);
        await flushPromises();

        element.shadowRoot
            .querySelector('lightning-button[slot="actions"]')
            .dispatchEvent(new CustomEvent('click'));

        await flushPromises();
        await flushPromises();

        expect(handler.mock.calls[0][0].detail.message).toContain('already');
    });
});
