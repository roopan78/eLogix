/**
 * Phase 5, D5: files linked to a proof of delivery cannot be deleted, unlinked or replaced by a new
 * version, even by an administrator; more evidence can be added; unrelated files are untouched.
 */
@IsTest
private class ProofEvidenceProtectionTest {
    private static final String MANAGER = 'Evidence LM Tester';

    @TestSetup
    static void setup() {
        Business_Unit__c businessUnit = TestDataFactory.createBusinessUnit('BU-EV');
        TestDataFactory.createCustomer('CUST-EV', businessUnit.Id);
        TestDataFactory.createUser(MANAGER, TestDataFactory.LOGISTICS_MANAGER);
    }

    private static Id deliveredProofId() {
        Account c = [SELECT Id, Business_Unit__c FROM Account WHERE Customer_Code__c = 'CUST-EV'];
        Vehicle__c vehicle = TestDataFactory.buildVehicle('TN-EV-1', c.Business_Unit__c);
        Driver__c driver = TestDataFactory.buildDriver('DL-EV-1', c.Business_Unit__c);
        insert vehicle;
        insert driver;
        Shipment__c shipment;
        System.runAs(TestDataFactory.getUser(MANAGER)) {
            shipment = TestDataFactory.deliveredShipment(c.Id, c.Business_Unit__c, vehicle.Id, driver.Id);
        }
        return [SELECT Id FROM Proof_of_Delivery__c WHERE Shipment__c = :shipment.Id].Id;
    }

    @IsTest
    static void evidenceCannotBeDeletedUnlinkedOrReplacedEvenByAnAdministrator() {
        Id proofId = deliveredProofId();
        ContentDocumentLink link = [SELECT Id, ContentDocumentId FROM ContentDocumentLink WHERE LinkedEntityId = :proofId LIMIT 1];

        // The running user is an administrator.
        Database.DeleteResult unlink = Database.delete(link.Id, false);
        Assert.areEqual(Label.eLogix_Delivery_Evidence_Protected, unlink.getErrors()[0].getMessage());

        Database.DeleteResult deleteFile = Database.delete(link.ContentDocumentId, false);
        Assert.areEqual(Label.eLogix_Delivery_Evidence_Protected, deleteFile.getErrors()[0].getMessage());

        Database.SaveResult replace = Database.insert(
            new ContentVersion(ContentDocumentId = link.ContentDocumentId, Title = 'Edited', PathOnClient = 'edited.jpg', VersionData = Blob.valueOf('other')),
            false
        );
        Assert.areEqual(Label.eLogix_Delivery_Evidence_Protected, replace.getErrors()[0].getMessage());

        // More evidence can always be added.
        TestDataFactory.attachEvidence(proofId);
        Assert.areEqual(2, [SELECT COUNT() FROM ContentDocumentLink WHERE LinkedEntityId = :proofId]);
        Assert.areEqual(1, [SELECT COUNT() FROM ContentDocument WHERE Id = :link.ContentDocumentId]);
    }

    @IsTest
    static void unrelatedFilesAreNotAffected() {
        Account c = [SELECT Id FROM Account WHERE Customer_Code__c = 'CUST-EV'];
        ContentVersion version = new ContentVersion(Title = 'Rate sheet', PathOnClient = 'rates.pdf', VersionData = Blob.valueOf('rates'), FirstPublishLocationId = c.Id);
        insert version;
        Id documentId = [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :version.Id].ContentDocumentId;

        insert new ContentVersion(ContentDocumentId = documentId, Title = 'Rate sheet v2', PathOnClient = 'rates.pdf', VersionData = Blob.valueOf('rates 2'));
        Assert.areEqual(2, [SELECT COUNT() FROM ContentVersion WHERE ContentDocumentId = :documentId]);

        ContentDocumentLink link = [SELECT Id FROM ContentDocumentLink WHERE ContentDocumentId = :documentId AND LinkedEntityId = :c.Id];
        Assert.isTrue(Database.delete(link.Id, false).isSuccess());
        Assert.isTrue(Database.delete(documentId, false).isSuccess());
    }

    @IsTest
    static void theHandlerRoutesEachFileObject() {
        ContentDocumentLink link = new ContentDocumentLink(LinkedEntityId = TestDataFactory.fakeId(Proof_of_Delivery__c.SObjectType, 1));
        Id linkId = TestDataFactory.fakeId(ContentDocumentLink.SObjectType, 1);
        new ProofEvidenceTriggerHandler(System.TriggerOperation.BEFORE_DELETE, null, new Map<Id, SObject>{ linkId => link }).run();
        Assert.areEqual(Label.eLogix_Delivery_Evidence_Protected, link.getErrors()[0].getMessage());

        ContentDocumentLink other = new ContentDocumentLink(LinkedEntityId = TestDataFactory.fakeId(Account.SObjectType, 1));
        new ProofEvidenceTriggerHandler(System.TriggerOperation.BEFORE_DELETE, null, new Map<Id, SObject>{ linkId => other }).run();
        Assert.isTrue(other.getErrors().isEmpty());
    }
}
