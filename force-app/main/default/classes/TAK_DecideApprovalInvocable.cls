/**
 * Flow action for approvers: approve or reject an agent approval request.
 * Use it from a Screen Flow launched by a button on the Agent Approval Request record.
 */
public with sharing class TAK_DecideApprovalInvocable {
    public class Request {
        @InvocableVariable(label='Approval Request Id' required=true)
        public Id approvalRequestId;

        @InvocableVariable(label='Approve' description='True to approve, false to reject.' required=true)
        public Boolean approve;

        @InvocableVariable(label='Comment' description='Reason for the decision.' required=false)
        public String comment;
    }

    public class Response {
        @InvocableVariable(label='Success')
        public Boolean success;

        @InvocableVariable(label='Status')
        public String status;

        @InvocableVariable(label='Message')
        public String message;
    }

    @InvocableMethod(label='Decide Agent Approval' description='Approve or reject an action requested by an AI agent.' category='Trusted Agent Kit')
    public static List<Response> invoke(List<Request> requests) {
        List<Response> out = new List<Response>();
        for (Request r : requests) {
            TAK_ApprovalService.DecisionResult d = TAK_ApprovalService.decide(r.approvalRequestId, r.approve == true, r.comment);
            Response res = new Response();
            res.success = d.success;
            res.status = d.status;
            res.message = d.message;
            out.add(res);
        }
        return out;
    }
}
