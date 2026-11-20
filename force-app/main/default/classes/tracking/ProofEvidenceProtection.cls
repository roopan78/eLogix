/**
 * Protection of proof of delivery evidence files (Phase 5, D5). Files are Salesforce Files linked to
 * Proof_of_Delivery__c records. Once linked, a file cannot be deleted, unlinked from the proof or
 * replaced by a new version, by any user, Administrator included, through normal Salesforce operations
 * (UI, API, Apex). More evidence can always be added. Files not linked to a proof are never touched.
 *
 * ContentDocumentLink before delete   unlinking from a proof is refused (no query: the linked record
 *                                     type is known from its Id)
 * ContentDocument before delete       deleting a document linked to any proof is refused
 * ContentVersion before insert        a new version of a document linked to any proof is refused
 */
public with sharing class ProofEvidenceProtection {
    @TestVisible
    private static DeliverySelector selector = new DeliverySelector();

    public void protectLinks(List<ContentDocumentLink> links) {
        for (ContentDocumentLink link : links) {
            if (isProof(link.LinkedEntityId)) {
                link.addError(Label.eLogix_Delivery_Evidence_Protected);
            }
        }
    }

    public void protectDocuments(List<ContentDocument> documents) {
        Set<Id> documentIds = new Map<Id, ContentDocument>(documents).keySet();
        Set<Id> protectedIds = selector.documentIdsLinkedToProofs(documentIds);
        for (ContentDocument document : documents) {
            if (protectedIds.contains(document.Id)) {
                document.addError(Label.eLogix_Delivery_Evidence_Protected);
            }
        }
    }

    public void protectVersions(List<ContentVersion> versions) {
        Set<Id> documentIds = new Set<Id>();
        for (ContentVersion version : versions) {
            if (version.ContentDocumentId != null) {
                documentIds.add(version.ContentDocumentId); // a new version of an existing document
            }
        }
        if (documentIds.isEmpty()) {
            return;
        }
        Set<Id> protectedIds = selector.documentIdsLinkedToProofs(documentIds);
        for (ContentVersion version : versions) {
            if (version.ContentDocumentId != null && protectedIds.contains(version.ContentDocumentId)) {
                version.addError(Label.eLogix_Delivery_Evidence_Protected);
            }
        }
    }

    private static Boolean isProof(Id recordId) {
        return recordId != null && recordId.getSObjectType() == Proof_of_Delivery__c.SObjectType;
    }
}
