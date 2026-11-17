/**
 * Recomputes the decision-log hash chain and reports the first problem found:
 *   SEQUENCE_GAP     a record was deleted from the middle of the chain
 *   BROKEN_LINK      a record's Previous Hash does not match its predecessor
 *   HASH_MISMATCH    a record's content was changed after it was written
 *   TAIL_MISSING     the newest records were deleted (chain head is ahead of the logs)
 *
 * verifyAll() handles up to 50,000 records synchronously. For larger logs run
 * TAK_AuditChainVerifyBatch, which uses the same verifyChunk() logic.
 */
public without sharing class TAK_AuditChainVerifier {
    public static final String FIELDS = 'Id, Name, Sequence__c, Previous_Hash__c, Record_Hash__c, Event_Timestamp__c, '
        + 'Agent_Name__c, Action_Name__c, Session_Id__c, User__c, Decision__c, Risk_Score__c, Risk_Reasons__c, '
        + 'Policy_Name__c, Input_Redacted__c, User_Message_Redacted__c, Output_Redacted__c, Output_Flagged__c, '
        + 'Correlation_Id__c, Approval_Gate__c, Duration_Ms__c';

    public class Result {
        public Boolean valid = true;
        public Long recordsChecked = 0;
        public Long firstBrokenSequence;
        public String detail = 'VALID';
        public String lastHash;
        public Long lastSequence;
    }

    public static Result verifyAll() {
        Result r = new Result();
        List<TAK_Agent_Decision_Log__c> logs = Database.query(
            'SELECT ' + FIELDS + ' FROM TAK_Agent_Decision_Log__c ORDER BY Sequence__c ASC LIMIT 50000'
        );
        verifyChunk(logs, r);
        checkHead(r);
        return r;
    }

    public static void verifyChunk(List<TAK_Agent_Decision_Log__c> logs, Result r) {
        for (TAK_Agent_Decision_Log__c log : logs) {
            if (!r.valid) {
                return;
            }
            Long seq = log.Sequence__c == null ? -1L : log.Sequence__c.longValue();
            Long expectedSeq = (r.lastSequence == null ? 0L : r.lastSequence) + 1;
            String expectedPrev = r.lastHash == null ? TAK_AuditLogger.GENESIS_HASH : r.lastHash;
            if (seq != expectedSeq) {
                fail(r, seq, 'SEQUENCE_GAP: expected ' + expectedSeq + ' but found ' + seq + ' (' + log.Name + ')');
            } else if (log.Previous_Hash__c == null || !expectedPrev.equals(log.Previous_Hash__c)) {
                fail(r, seq, 'BROKEN_LINK at sequence ' + seq + ' (' + log.Name + ')');
            } else if (log.Record_Hash__c == null || !TAK_AuditLogger.computeHash(log).equals(log.Record_Hash__c)) {
                fail(r, seq, 'HASH_MISMATCH at sequence ' + seq + ' (' + log.Name + '): content changed after it was written');
            } else {
                r.lastHash = log.Record_Hash__c;
                r.lastSequence = seq;
                r.recordsChecked++;
            }
        }
    }

    /** Detects deletion of the newest records by comparing with the chain head. */
    public static void checkHead(Result r) {
        if (!r.valid) {
            return;
        }
        List<TAK_Audit_Chain__c> heads = [
            SELECT Last_Sequence__c, Last_Hash__c
            FROM TAK_Audit_Chain__c
            WHERE Chain_Key__c = :TAK_AuditLogger.CHAIN_KEY
            LIMIT 1
        ];
        if (heads.isEmpty()) {
            return;
        }
        Long headSeq = heads[0].Last_Sequence__c == null ? 0L : heads[0].Last_Sequence__c.longValue();
        Long seen = r.lastSequence == null ? 0L : r.lastSequence;
        if (headSeq > seen) {
            fail(r, seen + 1, 'TAIL_MISSING: chain head is at sequence ' + headSeq + ' but logs end at ' + seen);
        } else if (headSeq == seen && seen > 0 && heads[0].Last_Hash__c != null && !heads[0].Last_Hash__c.equals(r.lastHash)) {
            fail(r, seen, 'HEAD_MISMATCH: chain head hash does not match the newest record');
        }
    }

    /** Stores the outcome on the chain head so a Flow or report can alert on it. */
    public static void recordResult(Result r) {
        List<TAK_Audit_Chain__c> heads = [
            SELECT Id FROM TAK_Audit_Chain__c WHERE Chain_Key__c = :TAK_AuditLogger.CHAIN_KEY LIMIT 1
        ];
        if (heads.isEmpty()) {
            return;
        }
        heads[0].Last_Verified_At__c = Datetime.now();
        String summary = r.valid ? 'VALID (' + r.recordsChecked + ' records)' : r.detail;
        heads[0].Last_Verification_Result__c = summary.length() > 255 ? summary.substring(0, 255) : summary;
        update heads[0];
    }

    private static void fail(Result r, Long seq, String detail) {
        r.valid = false;
        r.firstBrokenSequence = seq;
        r.detail = detail;
    }
}
