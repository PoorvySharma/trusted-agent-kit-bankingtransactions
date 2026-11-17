/**
 * Typed Agentforce action for internal transfers, governed by the Initiate_Transfer policy.
 *
 * This is the pattern to copy for each high-value action: named, described inputs for the
 * model, and a body that only builds the payload and calls the runner. The agent never
 * gets a path to the transfer logic that skips governance.
 */
public with sharing class TAK_InitiateTransferAgentAction {
    public static final String ACTION_NAME = 'Initiate_Transfer';

    public class Request {
        @InvocableVariable(label='From Account' description='Account number or record Id to transfer from. Must belong to the verified customer.' required=true)
        public String fromAccount;

        @InvocableVariable(label='To Account' description='Account number or record Id to transfer to.' required=true)
        public String toAccount;

        @InvocableVariable(label='Amount' description='Amount in US dollars, as a number.' required=true)
        public Decimal amount;

        @InvocableVariable(label='Memo' description='Optional memo from the customer.' required=false)
        public String memo;

        @InvocableVariable(label='Customer Message' description='The customer\'s most recent message, verbatim.' required=false)
        public String userMessage;

        @InvocableVariable(label='Session Id' description='Conversation or session identifier.' required=false)
        public String sessionId;
    }

    public class Response {
        @InvocableVariable(label='Status' description='EXECUTED, BLOCKED, PENDING_APPROVAL or ERROR.')
        public String status;

        @InvocableVariable(label='Executed' description='True only when the transfer actually ran.')
        public Boolean executed;

        @InvocableVariable(label='Message' description='What happened and what to tell the customer.')
        public String message;

        @InvocableVariable(label='Result JSON' description='Transfer confirmation (PII masked). Empty unless executed.')
        public String resultJson;

        @InvocableVariable(label='Approval Request Id' description='Approval request created or used, if any.')
        public Id approvalRequestId;

        @InvocableVariable(label='Correlation Id' description='Reference for the audit log.')
        public String correlationId;
    }

    @InvocableMethod(
        label='Initiate Transfer (Governed)'
        description='Moves money between accounts. Large transfers wait for human approval. Always follow the returned Message.'
        category='Trusted Agent Kit'
    )
    public static List<Response> invoke(List<Request> requests) {
        List<Response> out = new List<Response>();
        for (Request r : requests) {
            Map<String, Object> payload = new Map<String, Object>{
                'fromAccount' => r.fromAccount,
                'toAccount' => r.toAccount,
                'amount' => r.amount,
                'memo' => r.memo
            };
            TAK_GovernedActionRunner.Response res = TAK_GovernedActionRunner.run(
                'Agentforce', ACTION_NAME, JSON.serialize(payload), r.userMessage, r.sessionId
            );
            Response o = new Response();
            o.status = res.status;
            o.executed = res.executed;
            o.message = res.message;
            o.resultJson = res.resultJson;
            o.approvalRequestId = res.approvalRequestId;
            o.correlationId = res.correlationId;
            out.add(o);
        }
        return out;
    }
}
