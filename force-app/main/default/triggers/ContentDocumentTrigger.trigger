/**
 * The single ContentDocument trigger: protects proof of delivery evidence (ProofEvidenceProtection).
 */
trigger ContentDocumentTrigger on ContentDocument(before delete) {
    new ProofEvidenceTriggerHandler().run();
}
