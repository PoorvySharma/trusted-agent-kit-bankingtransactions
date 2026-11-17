/**
 * The policy decision point. Given a requested action, decides whether it may run, must be
 * blocked, or needs human approval. It performs queries only (no DML), so the runner can
 * still make callouts afterwards.
 *
 * Order of checks (first failure wins):
 *   1. Policy exists and is active          (fail-closed: unknown actions are blocked)
 *   2. Prompt-injection score below threshold (user message + every payload string)
 *   3. Per-user hourly rate limit
 *   4. Approval rules (amount threshold; unreadable amounts require approval)
 */
public without sharing class TAK_GovernanceGateway {
    public enum Outcome {
        ALLOW,
        BLOCK,
        REQUIRE_APPROVAL,
        APPROVED
    }

    public static final Set<String> ATTEMPT_DECISIONS = new Set<String>{
        'Executed',
        'Error',
        'Blocked',
        'Pending Approval'
    };

    public class Request {
        public String actionName;
        public String agentName;
        public String sessionId;
        public String userMessage;
        public Map<String, Object> payload = new Map<String, Object>();
    }

    public class Evaluation {
        public Outcome outcome;
        public TAK_PolicyService.Policy policy;
        public Integer riskScore = 0;
        public List<String> reasons = new List<String>();
        public String payloadHash;
        public Decimal amount;
        public TAK_Approval_Gate__c approvalToConsume;
        public TAK_Approval_Gate__c existingPendingRequest;
    }

    public static Evaluation evaluate(Request req) {
        Evaluation ev = new Evaluation();

        TAK_PolicyService.Policy p = TAK_PolicyService.forAction(req.actionName);
        ev.policy = p;
        if (p == null) {
            return block(ev, 'NO_POLICY: no Agent Policy is registered for action "' + req.actionName + '"');
        }
        if (!p.active) {
            return block(ev, 'POLICY_INACTIVE: ' + p.sourceName);
        }

        String scanText = (req.userMessage == null ? '' : req.userMessage) + ' \n ' + TAK_InjectionDetector.flatten(req.payload);
        TAK_InjectionDetector.Result scan = TAK_InjectionDetector.scan(scanText);
        ev.riskScore = scan.score;
        for (String r : scan.reasons) {
            ev.reasons.add('INJECTION_SIGNAL:' + r);
        }
        if (scan.exceeds(p.injectionThreshold)) {
            return block(ev, 'INJECTION_BLOCKED: score ' + scan.score + ' >= threshold ' + p.injectionThreshold);
        }

        if (p.maxCallsPerHour != null && p.maxCallsPerHour > 0) {
            Integer recent = countRecentAttempts(p.actionName, UserInfo.getUserId());
            if (recent >= p.maxCallsPerHour) {
                return block(ev, 'RATE_LIMIT: ' + recent + ' attempts in the last hour (limit ' + p.maxCallsPerHour + ')');
            }
        }

        if (approvalRequired(p, req.payload, ev)) {
            ev.payloadHash = TAK_Hashing.payloadHash(p.actionName, req.payload);
            TAK_Approval_Gate__c approved = TAK_ApprovalService.findUsableApproval(p.actionName, ev.payloadHash, UserInfo.getUserId());
            if (approved != null) {
                ev.approvalToConsume = approved;
                ev.reasons.add('APPROVAL_CONSUMED:' + approved.Name);
                ev.outcome = Outcome.APPROVED;
                return ev;
            }
            ev.existingPendingRequest = TAK_ApprovalService.findPendingRequest(p.actionName, ev.payloadHash, UserInfo.getUserId());
            ev.reasons.add('APPROVAL_REQUIRED: risk tier ' + p.riskTier);
            ev.outcome = Outcome.REQUIRE_APPROVAL;
            return ev;
        }

        ev.outcome = Outcome.ALLOW;
        return ev;
    }

    @TestVisible
    private static Boolean approvalRequired(TAK_PolicyService.Policy p, Map<String, Object> payload, Evaluation ev) {
        if (!p.requiresApproval) {
            return false;
        }
        if (p.approvalAmountThreshold == null) {
            return true;
        }
        Decimal amount = extractAmount(payload, p.amountField);
        ev.amount = amount;
        if (amount == null) {
            ev.reasons.add('AMOUNT_UNREADABLE: approval required (fail-closed)');
            return true;
        }
        return amount >= p.approvalAmountThreshold;
    }

    @TestVisible
    private static Decimal extractAmount(Map<String, Object> payload, String field) {
        if (payload == null || String.isBlank(field)) {
            return null;
        }
        Object raw = payload.get(field);
        if (raw == null) {
            for (String k : payload.keySet()) {
                if (k.equalsIgnoreCase(field)) {
                    raw = payload.get(k);
                    break;
                }
            }
        }
        if (raw == null) {
            return null;
        }
        try {
            return Decimal.valueOf(String.valueOf(raw).replaceAll('[,$\\s]', ''));
        } catch (Exception e) {
            return null;
        }
    }

    private static Integer countRecentAttempts(String actionName, Id userId) {
        Datetime since = Datetime.now().addHours(-1);
        return [
            SELECT COUNT()
            FROM TAK_Agent_Decision_Log__c
            WHERE User__c = :userId
                AND Action_Name__c = :actionName
                AND Event_Timestamp__c >= :since
                AND Decision__c IN :ATTEMPT_DECISIONS
        ];
    }

    private static Evaluation block(Evaluation ev, String reason) {
        ev.outcome = Outcome.BLOCK;
        ev.reasons.add(reason);
        return ev;
    }
}
