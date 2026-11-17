/**
 * Generic Agentforce / Flow action. Add it to an agent topic as "Run Governed Action" and
 * give the agent no direct access to the underlying bank actions, so every call passes
 * through policy, screening, approval and audit.
 *
 * For better tool-calling accuracy, prefer typed wrappers such as
 * TAK_InitiateTransferAgentAction, which give the model named, described inputs.
 */
public with sharing class TAK_RunGovernedActionInvocable {
    public class Request {
        @InvocableVariable(
            label='Action Name'
            description='Name of the governed action to run, for example Get_Account_Balance or Initiate_Transfer.'
            required=true
        )
        public String actionName;

        @InvocableVariable(
            label='Payload JSON'
            description='The action parameters as a JSON object, for example {"accountId":"001...","amount":250}.'
            required=false
        )
        public String payloadJson;

        @InvocableVariable(
            label='Customer Message'
            description='The customer\'s most recent message, verbatim. Used to screen for manipulation attempts.'
            required=false
        )
        public String userMessage;

        @InvocableVariable(label='Agent Name' description='Name of the calling agent.' required=false)
        public String agentName;

        @InvocableVariable(label='Session Id' description='Conversation or session identifier.' required=false)
        public String sessionId;
    }

    public class Response {
        @InvocableVariable(label='Status' description='EXECUTED, BLOCKED, PENDING_APPROVAL or ERROR.')
        public String status;

        @InvocableVariable(label='Executed' description='True only when the action actually ran.')
        public Boolean executed;

        @InvocableVariable(label='Message' description='What happened and what to tell the customer.')
        public String message;

        @InvocableVariable(label='Result JSON' description='Action result (PII masked per policy). Empty unless executed.')
        public String resultJson;

        @InvocableVariable(label='Approval Request Id' description='Approval request created or used, if any.')
        public String approvalRequestId;

        @InvocableVariable(label='Correlation Id' description='Reference for the audit log.')
        public String correlationId;
    }

    @InvocableMethod(
        label='Run Governed Action'
        description='Runs a bank action through Trusted Agent Kit: policy check, prompt-injection screening, rate limits, human approval for high-risk requests, PII masking and tamper-evident audit logging. Always follow the returned Message.'
        category='Trusted Agent Kit'
    )
    public static List<Response> invoke(List<Request> requests) {
        List<Response> out = new List<Response>();
        for (Request r : requests) {
            String agent = String.isBlank(r.agentName) ? 'Agentforce' : r.agentName;
            out.add(toResponse(TAK_GovernedActionRunner.run(agent, r.actionName, r.payloadJson, r.userMessage, r.sessionId)));
        }
        return out;
    }

    public static Response toResponse(TAK_GovernedActionRunner.Response src) {
        Response res = new Response();
        res.status = src.status;
        res.executed = src.executed;
        res.message = src.message;
        res.resultJson = src.resultJson;
        res.approvalRequestId = src.approvalRequestId;
        res.correlationId = src.correlationId;
        return res;
    }
}
