/**
 * Human-in-the-loop approvals for high-risk agent actions.
 *
 * Controls enforced here:
 *  - Payload binding: an approval is tied to a hash of the exact action + payload. The agent
 *    must resubmit the identical request to execute it; a changed amount or payee needs a
 *    new approval.
 *  - Single use: an approved request is marked Consumed when it executes, so it cannot be
 *    replayed.
 *  - Expiry: pending requests expire if nobody decides in time; approved requests must be
 *    executed within the policy's window.
 *  - Segregation of duties: approvers need the TAK_Approve_Agent_Actions custom permission
 *    and can never approve a request raised under their own user.
 *  - Every decision is written to the hash-chained decision log.
 *
 * Runs without sharing so approvals work regardless of record ownership; the custom
 * permission check is the authorisation control.
 */
public without sharing class TAK_ApprovalService {
    public static final String PERMISSION = 'TAK_Approve_Agent_Actions';
    public static final String STATUS_PENDING = 'Pending';
    public static final String STATUS_APPROVED = 'Approved';
    public static final String STATUS_REJECTED = 'Rejected';
    public static final String STATUS_EXPIRED = 'Expired';
    public static final String STATUS_CONSUMED = 'Consumed';

    public class DecisionResult {
        public Boolean success = false;
        public String status;
        public String message;
    }

    /** Builds (but does not insert) a pending approval request. */
    public static TAK_Approval_Gate__c buildRequest(
        TAK_PolicyService.Policy policy,
        String agentName,
        String sessionId,
        String payloadHash,
        String payloadRedacted,
        Decimal amount,
        Integer riskScore,
        String correlationId
    ) {
        Integer minutes = policy.approvalExpiryMinutes == null
            ? TAK_PolicyService.DEFAULT_APPROVAL_EXPIRY_MINUTES
            : policy.approvalExpiryMinutes;
        TAK_Approval_Gate__c gate = new TAK_Approval_Gate__c(
            Status__c = STATUS_PENDING,
            Action_Name__c = policy.actionName,
            Agent_Name__c = clip(agentName, 255),
            Session_Id__c = clip(sessionId, 255),
            Requested_By__c = UserInfo.getUserId(),
            Payload_Hash__c = payloadHash,
            Payload_Redacted__c = clip(payloadRedacted, TAK_AuditLogger.LONG_TEXT),
            Amount__c = amount,
            Risk_Tier__c = policy.riskTier,
            Risk_Score__c = riskScore,
            Expires_At__c = Datetime.now().addMinutes(minutes),
            Correlation_Id__c = correlationId
        );
        Id queueId = resolveQueue(policy.approverQueue);
        if (queueId != null) {
            gate.OwnerId = queueId;
        }
        return gate;
    }

    /** Returns an approved, unexpired, unused approval for this exact request, if any. */
    public static TAK_Approval_Gate__c findUsableApproval(String actionName, String payloadHash, Id requesterId) {
        Datetime now = Datetime.now();
        List<TAK_Approval_Gate__c> gates = [
            SELECT Id, Name, Status__c, Expires_At__c, Correlation_Id__c
            FROM TAK_Approval_Gate__c
            WHERE Action_Name__c = :actionName
                AND Payload_Hash__c = :payloadHash
                AND Requested_By__c = :requesterId
                AND Status__c = :STATUS_APPROVED
                AND Expires_At__c > :now
            ORDER BY Decided_At__c DESC
            LIMIT 1
        ];
        return gates.isEmpty() ? null : gates[0];
    }

    /** True when a request for the same payload is already waiting for a decision. */
    public static TAK_Approval_Gate__c findPendingRequest(String actionName, String payloadHash, Id requesterId) {
        Datetime now = Datetime.now();
        List<TAK_Approval_Gate__c> gates = [
            SELECT Id, Name, Status__c, Expires_At__c
            FROM TAK_Approval_Gate__c
            WHERE Action_Name__c = :actionName
                AND Payload_Hash__c = :payloadHash
                AND Requested_By__c = :requesterId
                AND Status__c = :STATUS_PENDING
                AND Expires_At__c > :now
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];
        return gates.isEmpty() ? null : gates[0];
    }

    public static DecisionResult approve(Id gateId, String comment) {
        return decide(gateId, true, comment);
    }

    public static DecisionResult reject(Id gateId, String comment) {
        return decide(gateId, false, comment);
    }

    public static DecisionResult decide(Id gateId, Boolean approve, String comment) {
        DecisionResult res = new DecisionResult();
        if (!FeatureManagement.checkPermission(PERMISSION)) {
            res.message = 'You do not have permission to approve agent actions.';
            return res;
        }
        List<TAK_Approval_Gate__c> rows = [
            SELECT Id, Name, Status__c, Action_Name__c, Agent_Name__c, Session_Id__c, Requested_By__c,
                Expires_At__c, Correlation_Id__c, Risk_Score__c
            FROM TAK_Approval_Gate__c
            WHERE Id = :gateId
            LIMIT 1
            FOR UPDATE
        ];
        if (rows.isEmpty()) {
            res.message = 'Approval request not found.';
            return res;
        }
        TAK_Approval_Gate__c gate = rows[0];
        res.status = gate.Status__c;

        if (gate.Status__c != STATUS_PENDING) {
            res.message = 'This request is already ' + gate.Status__c + '.';
            return res;
        }
        if (gate.Requested_By__c == UserInfo.getUserId()) {
            res.message = 'Segregation of duties: you cannot approve or reject a request raised under your own user.';
            return res;
        }
        if (gate.Expires_At__c != null && gate.Expires_At__c <= Datetime.now()) {
            gate.Status__c = STATUS_EXPIRED;
            update gate;
            res.status = STATUS_EXPIRED;
            res.message = 'This request expired before a decision was made. The agent must submit it again.';
            return res;
        }

        TAK_PolicyService.Policy policy = TAK_PolicyService.forAction(gate.Action_Name__c);
        Integer window = policy == null || policy.approvalExpiryMinutes == null
            ? TAK_PolicyService.DEFAULT_APPROVAL_EXPIRY_MINUTES
            : policy.approvalExpiryMinutes;

        gate.Status__c = approve ? STATUS_APPROVED : STATUS_REJECTED;
        gate.Decided_By__c = UserInfo.getUserId();
        gate.Decided_At__c = Datetime.now();
        gate.Decision_Comment__c = clip(comment, 4000);
        if (approve) {
            gate.Expires_At__c = Datetime.now().addMinutes(window);
        }
        update gate;

        TAK_AuditLogger.Entry entry = new TAK_AuditLogger.Entry();
        entry.agentName = gate.Agent_Name__c;
        entry.actionName = gate.Action_Name__c;
        entry.sessionId = gate.Session_Id__c;
        entry.userId = UserInfo.getUserId();
        entry.decision = approve ? 'Approval Granted' : 'Approval Rejected';
        entry.riskScore = gate.Risk_Score__c == null ? 0 : gate.Risk_Score__c.intValue();
        entry.reasons.add('APPROVER_DECISION:' + gate.Name);
        if (String.isNotBlank(comment)) {
            entry.reasons.add('COMMENT:' + TAK_PIIRedactor.mask(comment));
        }
        entry.policyName = policy == null ? null : policy.sourceName;
        entry.correlationId = gate.Correlation_Id__c;
        entry.approvalGateId = gate.Id;
        TAK_AuditLogger.append(entry);

        res.success = true;
        res.status = gate.Status__c;
        res.message = approve
            ? 'Approved. The agent can now complete this exact request within ' + window + ' minutes.'
            : 'Rejected. The agent will not perform this request.';
        return res;
    }

    private static Id resolveQueue(String developerName) {
        if (String.isBlank(developerName)) {
            return null;
        }
        List<QueueSobject> qs = [
            SELECT QueueId
            FROM QueueSobject
            WHERE Queue.DeveloperName = :developerName
                AND SobjectType = 'TAK_Approval_Gate__c'
            LIMIT 1
        ];
        return qs.isEmpty() ? null : qs[0].QueueId;
    }

    private static String clip(String s, Integer maxLen) {
        if (s == null) {
            return null;
        }
        return s.length() > maxLen ? s.substring(0, maxLen) : s;
    }
}
