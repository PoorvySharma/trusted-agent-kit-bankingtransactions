/**
 * Single entry point for every governed agent action:
 *
 *   parse payload -> gateway decision -> (execute handler) -> screen + redact output
 *   -> write approval request / consume approval -> append hash-chained log entry
 *
 * All DML happens at the end, after the handler runs, so handlers can make HTTP callouts
 * to core banking systems. Messages returned to the agent are written for the language
 * model: they say what happened and what to tell the customer, never internal details.
 */
public without sharing class TAK_GovernedActionRunner {
    public static final String STATUS_EXECUTED = 'EXECUTED';
    public static final String STATUS_BLOCKED = 'BLOCKED';
    public static final String STATUS_PENDING = 'PENDING_APPROVAL';
    public static final String STATUS_ERROR = 'ERROR';

    public static final String MSG_BLOCKED = 'This request was stopped by a security policy and has been logged. Do not retry it. Tell the customer you cannot complete it here and offer to connect them with a colleague.';
    public static final String MSG_PENDING = 'This action needs approval from a bank employee before it can be completed. Tell the customer it has been sent for review. Once approved, submit exactly the same request again to complete it.';
    public static final String MSG_ERROR = 'The action could not be completed because of a system error, which has been logged. Apologise to the customer and offer to connect them with a colleague.';
    public static final String MSG_EXECUTED = 'The action was completed.';
    public static final String MSG_OUTPUT_WITHHELD = 'The action was completed, but part of its result contained text that looked like instructions and was withheld for safety. Do not guess the missing details; offer to connect the customer with a colleague.';

    public class Response {
        public String status;
        public Boolean executed = false;
        public String message;
        public String resultJson;
        public String correlationId;
        public Id approvalRequestId;
        public Integer riskScore = 0;
    }

    public static Response run(String agentName, String actionName, String payloadJson, String userMessage, String sessionId) {
        Long started = System.currentTimeMillis();
        Response resp = new Response();
        resp.correlationId = UUID.randomUUID().toString();

        TAK_AuditLogger.Entry entry = new TAK_AuditLogger.Entry();
        entry.agentName = agentName;
        entry.actionName = actionName;
        entry.sessionId = sessionId;
        entry.userId = UserInfo.getUserId();
        entry.correlationId = resp.correlationId;
        entry.inputRedacted = TAK_PIIRedactor.mask(payloadJson);
        entry.userMessageRedacted = TAK_PIIRedactor.mask(userMessage);

        TAK_Approval_Gate__c gateToInsert;
        TAK_Approval_Gate__c gateToUpdate;

        Map<String, Object> payload = parsePayload(payloadJson);
        if (payload == null) {
            entry.decision = 'Blocked';
            entry.reasons.add('INVALID_PAYLOAD: payload must be a JSON object');
            resp.status = STATUS_BLOCKED;
            resp.message = 'The request details were not in the expected format. Collect the details again and resubmit.';
            finish(entry, resp, started, null, null);
            return resp;
        }

        TAK_GovernanceGateway.Request req = new TAK_GovernanceGateway.Request();
        req.actionName = actionName;
        req.agentName = agentName;
        req.sessionId = sessionId;
        req.userMessage = userMessage;
        req.payload = payload;

        TAK_GovernanceGateway.Evaluation ev = TAK_GovernanceGateway.evaluate(req);
        entry.riskScore = ev.riskScore;
        entry.reasons.addAll(ev.reasons);
        entry.policyName = ev.policy == null ? null : ev.policy.sourceName;
        resp.riskScore = ev.riskScore;

        switch on ev.outcome {
            when BLOCK {
                entry.decision = 'Blocked';
                resp.status = STATUS_BLOCKED;
                resp.message = MSG_BLOCKED;
            }
            when REQUIRE_APPROVAL {
                entry.decision = 'Pending Approval';
                resp.status = STATUS_PENDING;
                resp.message = MSG_PENDING;
                if (ev.existingPendingRequest != null) {
                    resp.approvalRequestId = ev.existingPendingRequest.Id;
                    entry.approvalGateId = ev.existingPendingRequest.Id;
                    entry.reasons.add('APPROVAL_ALREADY_PENDING:' + ev.existingPendingRequest.Name);
                } else {
                    gateToInsert = TAK_ApprovalService.buildRequest(
                        ev.policy, agentName, sessionId, ev.payloadHash,
                        entry.inputRedacted, ev.amount, ev.riskScore, resp.correlationId
                    );
                }
            }
            when ALLOW, APPROVED {
                gateToUpdate = executeHandler(ev, payload, entry, resp);
            }
        }

        finish(entry, resp, started, gateToInsert, gateToUpdate);
        return resp;
    }

    private static TAK_Approval_Gate__c executeHandler(
        TAK_GovernanceGateway.Evaluation ev,
        Map<String, Object> payload,
        TAK_AuditLogger.Entry entry,
        Response resp
    ) {
        TAK_PolicyService.Policy p = ev.policy;
        try {
            TAK_GovernedAction handler = resolveHandler(p.handlerClass);
            Map<String, Object> result = handler.execute(payload);
            if (result == null) {
                result = new Map<String, Object>();
            }
            String resultJson = JSON.serialize(result);
            String redacted = TAK_PIIRedactor.mask(resultJson);

            // Indirect prompt injection: data returned by systems (notes, memos, emails)
            // can carry instructions aimed at the agent. Screen it before the model sees it.
            TAK_InjectionDetector.Result outScan = TAK_InjectionDetector.scan(TAK_InjectionDetector.flatten(result));
            if (outScan.exceeds(p.injectionThreshold)) {
                entry.outputFlagged = true;
                for (String r : outScan.reasons) {
                    entry.reasons.add('OUTPUT_INJECTION_SIGNAL:' + r);
                }
                resp.resultJson = JSON.serialize(new Map<String, Object>{ 'withheld' => true });
                resp.message = MSG_OUTPUT_WITHHELD;
            } else {
                resp.resultJson = p.redactOutput ? redacted : resultJson;
                resp.message = MSG_EXECUTED;
            }
            entry.outputRedacted = redacted;
            entry.decision = 'Executed';
            resp.status = STATUS_EXECUTED;
            resp.executed = true;

            if (ev.outcome == TAK_GovernanceGateway.Outcome.APPROVED && ev.approvalToConsume != null) {
                entry.approvalGateId = ev.approvalToConsume.Id;
                resp.approvalRequestId = ev.approvalToConsume.Id;
                return new TAK_Approval_Gate__c(
                    Id = ev.approvalToConsume.Id,
                    Status__c = TAK_ApprovalService.STATUS_CONSUMED,
                    Consumed_At__c = Datetime.now()
                );
            }
        } catch (Exception e) {
            entry.decision = 'Error';
            entry.reasons.add('HANDLER_ERROR:' + e.getTypeName() + ': ' + TAK_PIIRedactor.mask(e.getMessage()));
            resp.status = STATUS_ERROR;
            resp.message = MSG_ERROR;
            resp.executed = false;
            resp.resultJson = null;
            // An approval is not consumed when the action fails, so it can be retried.
        }
        return null;
    }

    @TestVisible
    private static TAK_GovernedAction resolveHandler(String className) {
        if (String.isBlank(className)) {
            throw new TAK_GovernanceException('Policy has no Handler Class.');
        }
        Type t = Type.forName(className);
        if (t == null) {
            throw new TAK_GovernanceException('Handler class not found: ' + className);
        }
        Object instance = t.newInstance();
        if (!(instance instanceof TAK_GovernedAction)) {
            throw new TAK_GovernanceException(className + ' does not implement TAK_GovernedAction.');
        }
        return (TAK_GovernedAction) instance;
    }

    private static Map<String, Object> parsePayload(String payloadJson) {
        if (String.isBlank(payloadJson)) {
            return new Map<String, Object>();
        }
        try {
            Object parsed = JSON.deserializeUntyped(payloadJson);
            if (parsed instanceof Map<String, Object>) {
                return (Map<String, Object>) parsed;
            }
        } catch (Exception e) {
            return null;
        }
        return null;
    }

    private static void finish(
        TAK_AuditLogger.Entry entry,
        Response resp,
        Long started,
        TAK_Approval_Gate__c gateToInsert,
        TAK_Approval_Gate__c gateToUpdate
    ) {
        if (gateToInsert != null) {
            insert gateToInsert;
            entry.approvalGateId = gateToInsert.Id;
            resp.approvalRequestId = gateToInsert.Id;
        }
        if (gateToUpdate != null) {
            update gateToUpdate;
        }
        entry.durationMs = System.currentTimeMillis() - started;
        TAK_AuditLogger.append(entry);
    }
}
