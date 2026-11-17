/**
 * Appends records to the tamper-evident decision log.
 *
 * Every record stores the SHA-256 hash of its own canonical content plus the previous
 * record's hash, forming a chain. Editing any field, deleting a record, or deleting the
 * newest records breaks the chain, and TAK_AuditChainVerifier will report where.
 *
 * Concurrency: the chain head (TAK_Audit_Chain__c, key DEFAULT) is locked with FOR UPDATE
 * on every append, so concurrent agent sessions are serialised and sequence numbers never
 * collide.
 *
 * Runs without sharing on purpose: audit infrastructure must be able to read and lock the
 * chain head no matter which user the agent runs as. Callers never get data back from it.
 */
public without sharing class TAK_AuditLogger {
    public static final String CHAIN_KEY = 'DEFAULT';
    public static final String GENESIS_HASH = '0000000000000000000000000000000000000000000000000000000000000000';
    public static final Integer SHORT_TEXT = 255;
    public static final Integer LONG_TEXT = 32000;

    public class Entry {
        public String agentName;
        public String actionName;
        public String sessionId;
        public Id userId;
        public String decision;
        public Integer riskScore = 0;
        public List<String> reasons = new List<String>();
        public String policyName;
        public String inputRedacted;
        public String userMessageRedacted;
        public String outputRedacted;
        public Boolean outputFlagged = false;
        public String correlationId;
        public Id approvalGateId;
        public Long durationMs;
    }

    public static TAK_Agent_Decision_Log__c append(Entry entry) {
        return append(new List<Entry>{ entry })[0];
    }

    public static List<TAK_Agent_Decision_Log__c> append(List<Entry> entries) {
        List<TAK_Agent_Decision_Log__c> logs = new List<TAK_Agent_Decision_Log__c>();
        if (entries == null || entries.isEmpty()) {
            return logs;
        }
        TAK_Audit_Chain__c chain = lockChain();
        String prev = String.isBlank(chain.Last_Hash__c) ? GENESIS_HASH : chain.Last_Hash__c;
        Long seq = chain.Last_Sequence__c == null ? 0L : chain.Last_Sequence__c.longValue();
        Datetime ts = Datetime.now();

        for (Entry e : entries) {
            seq++;
            TAK_Agent_Decision_Log__c log = new TAK_Agent_Decision_Log__c(
                Sequence__c = seq,
                Previous_Hash__c = prev,
                Event_Timestamp__c = ts,
                Agent_Name__c = clip(e.agentName, SHORT_TEXT),
                Action_Name__c = clip(e.actionName, SHORT_TEXT),
                Session_Id__c = clip(e.sessionId, SHORT_TEXT),
                User__c = e.userId != null ? e.userId : UserInfo.getUserId(),
                Decision__c = e.decision,
                Risk_Score__c = e.riskScore == null ? 0 : e.riskScore,
                Risk_Reasons__c = clip(String.join(e.reasons == null ? new List<String>() : e.reasons, '\n'), LONG_TEXT),
                Policy_Name__c = clip(e.policyName, SHORT_TEXT),
                Input_Redacted__c = clip(e.inputRedacted, LONG_TEXT),
                User_Message_Redacted__c = clip(e.userMessageRedacted, LONG_TEXT),
                Output_Redacted__c = clip(e.outputRedacted, LONG_TEXT),
                Output_Flagged__c = e.outputFlagged == true,
                Correlation_Id__c = clip(e.correlationId, 64),
                Approval_Gate__c = e.approvalGateId,
                Duration_Ms__c = e.durationMs
            );
            log.Record_Hash__c = computeHash(log);
            prev = log.Record_Hash__c;
            logs.add(log);
        }
        insert logs;

        chain.Last_Hash__c = prev;
        chain.Last_Sequence__c = seq;
        update chain;
        return logs;
    }

    /**
     * Canonical hash of a log record. Each part is length-prefixed so field boundaries
     * cannot be shifted to forge a collision. Text is normalised (line endings, outer
     * whitespace, null vs empty) so the hash survives the database round trip.
     */
    public static String computeHash(TAK_Agent_Decision_Log__c l) {
        List<String> parts = new List<String>{
            String.valueOf(l.Sequence__c == null ? 0L : l.Sequence__c.longValue()),
            norm(l.Previous_Hash__c),
            l.Event_Timestamp__c == null ? '' : l.Event_Timestamp__c.formatGmt('yyyy-MM-dd HH:mm:ss'),
            norm(l.Agent_Name__c),
            norm(l.Action_Name__c),
            norm(l.Session_Id__c),
            l.User__c == null ? '' : String.valueOf(l.User__c),
            norm(l.Decision__c),
            String.valueOf(l.Risk_Score__c == null ? 0 : l.Risk_Score__c.intValue()),
            norm(l.Risk_Reasons__c),
            norm(l.Policy_Name__c),
            norm(l.Input_Redacted__c),
            norm(l.User_Message_Redacted__c),
            norm(l.Output_Redacted__c),
            String.valueOf(l.Output_Flagged__c == true),
            norm(l.Correlation_Id__c),
            l.Approval_Gate__c == null ? '' : String.valueOf(l.Approval_Gate__c),
            String.valueOf(l.Duration_Ms__c == null ? 0L : l.Duration_Ms__c.longValue())
        };
        List<String> framed = new List<String>();
        for (String p : parts) {
            framed.add(String.valueOf(p.length()) + ':' + p);
        }
        return TAK_Hashing.sha256(String.join(framed, '|'));
    }

    public static TAK_Audit_Chain__c lockChain() {
        List<TAK_Audit_Chain__c> rows = [
            SELECT Id, Last_Hash__c, Last_Sequence__c
            FROM TAK_Audit_Chain__c
            WHERE Chain_Key__c = :CHAIN_KEY
            LIMIT 1
            FOR UPDATE
        ];
        if (!rows.isEmpty()) {
            return rows[0];
        }
        TAK_Audit_Chain__c head = new TAK_Audit_Chain__c(
            Name = CHAIN_KEY,
            Chain_Key__c = CHAIN_KEY,
            Last_Hash__c = GENESIS_HASH,
            Last_Sequence__c = 0
        );
        Database.SaveResult sr = Database.insert(head, false);
        if (sr.isSuccess()) {
            return head;
        }
        // Another transaction created the head first; lock theirs.
        rows = [
            SELECT Id, Last_Hash__c, Last_Sequence__c
            FROM TAK_Audit_Chain__c
            WHERE Chain_Key__c = :CHAIN_KEY
            LIMIT 1
            FOR UPDATE
        ];
        if (rows.isEmpty()) {
            throw new TAK_GovernanceException('Unable to create or lock the audit chain head.');
        }
        return rows[0];
    }

    public static String norm(String s) {
        if (s == null) {
            return '';
        }
        return s.replace('\r\n', '\n').replace('\r', '\n').trim();
    }

    private static String clip(String s, Integer maxLen) {
        if (s == null) {
            return null;
        }
        String n = norm(s);
        return n.length() > maxLen ? n.substring(0, maxLen) : n;
    }
}
