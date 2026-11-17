@IsTest
private class TAK_AuditChainTest {
    private static void appendEntries(Integer n) {
        List<TAK_AuditLogger.Entry> entries = new List<TAK_AuditLogger.Entry>();
        for (Integer i = 0; i < n; i++) {
            TAK_AuditLogger.Entry e = new TAK_AuditLogger.Entry();
            e.agentName = 'Test Agent';
            e.actionName = 'Test_Action';
            e.decision = 'Executed';
            e.riskScore = i;
            e.reasons.add('TEST:' + i);
            e.inputRedacted = '{"i":' + i + '}\r\nline two  ';
            e.correlationId = 'corr-' + i;
            e.durationMs = 5;
            entries.add(e);
        }
        TAK_AuditLogger.append(entries);
    }

    @IsTest
    static void chainIsValidAcrossSeparateAppends() {
        appendEntries(3);
        appendEntries(2);
        List<TAK_Agent_Decision_Log__c> logs = TAK_TestUtil.logs();
        System.assertEquals(5, logs.size());
        for (Integer i = 0; i < logs.size(); i++) {
            System.assert(logs[i].Sequence__c == i + 1, 'sequence ' + logs[i].Sequence__c);
        }
        TAK_AuditChainVerifier.Result r = TAK_AuditChainVerifier.verifyAll();
        System.assert(r.valid, r.detail);
        System.assert(r.recordsChecked == 5, 'checked ' + r.recordsChecked);

        TAK_Audit_Chain__c head = [SELECT Last_Sequence__c, Last_Hash__c FROM TAK_Audit_Chain__c];
        System.assert(head.Last_Sequence__c == 5, 'head ' + head.Last_Sequence__c);
        System.assertEquals(1, [SELECT COUNT() FROM TAK_Audit_Chain__c], 'exactly one chain head');
    }

    @IsTest
    static void firstRecordLinksToGenesis() {
        appendEntries(1);
        TAK_Agent_Decision_Log__c first = [SELECT Previous_Hash__c, Record_Hash__c FROM TAK_Agent_Decision_Log__c];
        System.assertEquals(TAK_AuditLogger.GENESIS_HASH, first.Previous_Hash__c);
        System.assertEquals(64, first.Record_Hash__c.length());
    }

    @IsTest
    static void editedRecordIsDetected() {
        appendEntries(4);
        TAK_DecisionLogGuard.allowMutationForTest = true;
        TAK_Agent_Decision_Log__c victim = [SELECT Id FROM TAK_Agent_Decision_Log__c WHERE Sequence__c = 3];
        victim.Decision__c = 'Blocked';
        update victim;
        TAK_DecisionLogGuard.allowMutationForTest = false;

        TAK_AuditChainVerifier.Result r = TAK_AuditChainVerifier.verifyAll();
        System.assert(!r.valid);
        System.assert(r.firstBrokenSequence == 3, 'broken at ' + r.firstBrokenSequence);
        System.assert(r.detail.startsWith('HASH_MISMATCH'), r.detail);
    }

    @IsTest
    static void deletedMiddleRecordIsDetected() {
        appendEntries(4);
        TAK_DecisionLogGuard.allowMutationForTest = true;
        delete [SELECT Id FROM TAK_Agent_Decision_Log__c WHERE Sequence__c = 2];
        TAK_DecisionLogGuard.allowMutationForTest = false;

        TAK_AuditChainVerifier.Result r = TAK_AuditChainVerifier.verifyAll();
        System.assert(!r.valid);
        System.assert(r.detail.startsWith('SEQUENCE_GAP'), r.detail);
    }

    @IsTest
    static void deletedNewestRecordIsDetected() {
        appendEntries(4);
        TAK_DecisionLogGuard.allowMutationForTest = true;
        delete [SELECT Id FROM TAK_Agent_Decision_Log__c WHERE Sequence__c = 4];
        TAK_DecisionLogGuard.allowMutationForTest = false;

        TAK_AuditChainVerifier.Result r = TAK_AuditChainVerifier.verifyAll();
        System.assert(!r.valid);
        System.assert(r.detail.startsWith('TAIL_MISSING'), r.detail);
    }

    @IsTest
    static void rewrittenLinkIsDetected() {
        appendEntries(3);
        TAK_DecisionLogGuard.allowMutationForTest = true;
        TAK_Agent_Decision_Log__c victim = [SELECT Id FROM TAK_Agent_Decision_Log__c WHERE Sequence__c = 2];
        victim.Previous_Hash__c = TAK_Hashing.sha256('forged');
        update victim;
        TAK_DecisionLogGuard.allowMutationForTest = false;

        TAK_AuditChainVerifier.Result r = TAK_AuditChainVerifier.verifyAll();
        System.assert(!r.valid);
        System.assert(r.detail.startsWith('BROKEN_LINK'), r.detail);
    }

    @IsTest
    static void logsCannotBeUpdatedOrDeleted() {
        appendEntries(1);
        TAK_Agent_Decision_Log__c log = [SELECT Id FROM TAK_Agent_Decision_Log__c];
        log.Decision__c = 'Blocked';
        Database.SaveResult up = Database.update(log, false);
        System.assert(!up.isSuccess());
        System.assertEquals(TAK_DecisionLogGuard.MESSAGE, up.getErrors()[0].getMessage());

        Database.DeleteResult del = Database.delete(log.Id, false);
        System.assert(!del.isSuccess());
        System.assertEquals(TAK_DecisionLogGuard.MESSAGE, del.getErrors()[0].getMessage());
    }

    @IsTest
    static void batchVerifiesAndRecordsResult() {
        appendEntries(6);
        Test.startTest();
        Database.executeBatch(new TAK_AuditChainVerifyBatch());
        Test.stopTest();
        TAK_Audit_Chain__c head = [SELECT Last_Verified_At__c, Last_Verification_Result__c FROM TAK_Audit_Chain__c];
        System.assertNotEquals(null, head.Last_Verified_At__c);
        System.assertEquals('VALID (6 records)', head.Last_Verification_Result__c);
    }

    @IsTest
    static void batchRecordsFailure() {
        appendEntries(3);
        TAK_DecisionLogGuard.allowMutationForTest = true;
        TAK_Agent_Decision_Log__c victim = [SELECT Id FROM TAK_Agent_Decision_Log__c WHERE Sequence__c = 1];
        victim.Output_Redacted__c = 'rewritten';
        update victim;
        TAK_DecisionLogGuard.allowMutationForTest = false;

        Test.startTest();
        Database.executeBatch(new TAK_AuditChainVerifyBatch());
        Test.stopTest();
        TAK_Audit_Chain__c head = [SELECT Last_Verification_Result__c FROM TAK_Audit_Chain__c];
        System.assert(head.Last_Verification_Result__c.startsWith('HASH_MISMATCH'), head.Last_Verification_Result__c);
    }

    @IsTest
    static void schedulableStartsBatch() {
        appendEntries(1);
        Test.startTest();
        String jobId = System.schedule('TAK verify test', '0 0 2 * * ?', new TAK_AuditChainVerifyBatch());
        Test.stopTest();
        System.assertNotEquals(null, jobId);
    }

    @IsTest
    static void emptyLogIsValid() {
        TAK_AuditChainVerifier.Result r = TAK_AuditChainVerifier.verifyAll();
        System.assert(r.valid);
        System.assert(r.recordsChecked == 0);
        TAK_AuditChainVerifier.recordResult(r); // no head yet: no-op
        System.assertEquals(0, [SELECT COUNT() FROM TAK_Audit_Chain__c]);
        System.assertEquals(0, TAK_AuditLogger.append(new List<TAK_AuditLogger.Entry>()).size());
    }
}
