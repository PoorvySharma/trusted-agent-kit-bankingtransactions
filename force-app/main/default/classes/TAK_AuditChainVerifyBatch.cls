/**
 * Verifies the full decision-log chain in batches and stores the result on the chain head.
 * Batch chunks run serially in Sequence order, and state carries across chunks.
 *
 * Run once:      Database.executeBatch(new TAK_AuditChainVerifyBatch(), 2000);
 * Run nightly:   System.schedule('TAK chain verify', '0 0 2 * * ?', new TAK_AuditChainVerifyBatch());
 */
public without sharing class TAK_AuditChainVerifyBatch implements Database.Batchable<SObject>, Database.Stateful, Schedulable {
    @TestVisible
    private TAK_AuditChainVerifier.Result result = new TAK_AuditChainVerifier.Result();

    public Database.QueryLocator start(Database.BatchableContext bc) {
        return Database.getQueryLocator(
            'SELECT ' + TAK_AuditChainVerifier.FIELDS + ' FROM TAK_Agent_Decision_Log__c ORDER BY Sequence__c ASC'
        );
    }

    public void execute(Database.BatchableContext bc, List<SObject> scope) {
        TAK_AuditChainVerifier.verifyChunk((List<TAK_Agent_Decision_Log__c>) scope, result);
    }

    public void finish(Database.BatchableContext bc) {
        TAK_AuditChainVerifier.checkHead(result);
        TAK_AuditChainVerifier.recordResult(result);
    }

    public void execute(SchedulableContext sc) {
        Database.executeBatch(new TAK_AuditChainVerifyBatch(), 2000);
    }
}
