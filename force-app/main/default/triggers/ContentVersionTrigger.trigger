/**
 * The single ContentVersion trigger: protects proof of delivery evidence (ProofEvidenceProtection).
 */
trigger ContentVersionTrigger on ContentVersion(before insert) {
    new ProofEvidenceTriggerHandler().run();
}
