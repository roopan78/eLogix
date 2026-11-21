/**
 * The single ContentDocumentLink trigger: protects proof of delivery evidence (ProofEvidenceProtection).
 */
trigger ContentDocumentLinkTrigger on ContentDocumentLink(before delete) {
    new ProofEvidenceTriggerHandler().run();
}
