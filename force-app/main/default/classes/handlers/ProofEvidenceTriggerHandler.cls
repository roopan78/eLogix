/**
 * Routes the Salesforce Files triggers to ProofEvidenceProtection (Phase 5, D5). One handler for the
 * three standard objects involved; each trigger is still the only trigger on its object.
 *
 * ContentDocumentLink before delete, ContentDocument before delete, ContentVersion before insert.
 */
public with sharing class ProofEvidenceTriggerHandler extends TriggerHandler {
    public ProofEvidenceTriggerHandler() {
        super();
    }

    @TestVisible
    private ProofEvidenceTriggerHandler(System.TriggerOperation operation, List<SObject> newList, Map<Id, SObject> oldMap) {
        super(operation, newList, oldMap);
    }

    protected override void beforeInsert() {
        if (!newList.isEmpty() && newList.getSObjectType() == ContentVersion.SObjectType) {
            new ProofEvidenceProtection().protectVersions((List<ContentVersion>) newList);
        }
    }

    protected override void beforeDelete() {
        List<SObject> records = oldMap.values();
        if (records.isEmpty()) {
            return;
        }
        Schema.SObjectType type = records[0].getSObjectType();
        if (type == ContentDocumentLink.SObjectType) {
            new ProofEvidenceProtection().protectLinks((List<ContentDocumentLink>) records);
        } else if (type == ContentDocument.SObjectType) {
            new ProofEvidenceProtection().protectDocuments((List<ContentDocument>) records);
        }
    }
}
