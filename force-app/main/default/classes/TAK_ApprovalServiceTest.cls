@IsTest
private class TAK_ApprovalServiceTest {
    private static TAK_Approval_Gate__c pendingGate(Id requester, Integer minutesToExpiry) {
        TAK_Approval_Gate__c g = new TAK_Approval_Gate__c(
            Status__c = 'Pending',
            Action_Name__c = TAK_TestUtil.TRANSFER,
            Agent_Name__c = 'Test Agent',
            Requested_By__c = requester,
            Payload_Hash__c = TAK_Hashing.sha256('x'),
            Expires_At__c = Datetime.now().addMinutes(minutesToExpiry),
            Correlation_Id__c = 'corr-1',
            Risk_Score__c = 10
        );
        insert g;
        return g;
    }

    @IsTest
    static void requesterCannotApproveOwnRequest() {
        TAK_TestUtil.registerPolicies();
        User approver = TAK_TestUtil.createUser('taksod', 'TAK_Approver');
        TAK_Approval_Gate__c g = pendingGate(approver.Id, 30);
        System.runAs(approver) {
            TAK_ApprovalService.DecisionResult d = TAK_ApprovalService.approve(g.Id, 'self approve');
            System.assert(!d.success);
            System.assert(d.message.contains('Segregation of duties'));
        }
        System.assertEquals('Pending', [SELECT Status__c FROM TAK_Approval_Gate__c WHERE Id = :g.Id].Status__c);
    }

    @IsTest
    static void userWithoutPermissionCannotDecide() {
        TAK_TestUtil.registerPolicies();
        User plain = TAK_TestUtil.createUser('taknop', null);
        TAK_Approval_Gate__c g = pendingGate(UserInfo.getUserId(), 30);
        System.runAs(plain) {
            TAK_ApprovalService.DecisionResult d = TAK_ApprovalService.approve(g.Id, 'try');
            System.assert(!d.success);
            System.assert(d.message.contains('permission'));
        }
    }

    @IsTest
    static void rejectRecordsDecisionAndLogs() {
        TAK_TestUtil.registerPolicies();
        User approver = TAK_TestUtil.createUser('takrej', 'TAK_Approver');
        TAK_Approval_Gate__c g = pendingGate(UserInfo.getUserId(), 30);
        System.runAs(approver) {
            TAK_ApprovalService.DecisionResult d = TAK_ApprovalService.reject(g.Id, 'Payee does not match, call 312-555-0199');
            System.assert(d.success);
            System.assertEquals('Rejected', d.status);
        }
        TAK_Approval_Gate__c after = [SELECT Status__c, Decided_By__c, Decided_At__c FROM TAK_Approval_Gate__c WHERE Id = :g.Id];
        System.assertEquals('Rejected', after.Status__c);
        System.assertEquals(approver.Id, after.Decided_By__c);
        TAK_Agent_Decision_Log__c log = TAK_TestUtil.logs()[0];
        System.assertEquals('Approval Rejected', log.Decision__c);
        System.assertEquals(approver.Id, log.User__c);
        System.assert(log.Risk_Reasons__c.contains('[PHONE REDACTED]'), 'approver comments are redacted too');
    }

    @IsTest
    static void expiredRequestCannotBeApproved() {
        TAK_TestUtil.registerPolicies();
        User approver = TAK_TestUtil.createUser('takexp', 'TAK_Approver');
        TAK_Approval_Gate__c g = pendingGate(UserInfo.getUserId(), -5);
        System.runAs(approver) {
            TAK_ApprovalService.DecisionResult d = TAK_ApprovalService.approve(g.Id, 'late');
            System.assert(!d.success);
            System.assertEquals('Expired', d.status);
        }
        System.assertEquals('Expired', [SELECT Status__c FROM TAK_Approval_Gate__c WHERE Id = :g.Id].Status__c);
    }

    @IsTest
    static void decidedRequestCannotBeDecidedAgain() {
        TAK_TestUtil.registerPolicies();
        User approver = TAK_TestUtil.createUser('takdbl', 'TAK_Approver');
        TAK_Approval_Gate__c g = pendingGate(UserInfo.getUserId(), 30);
        System.runAs(approver) {
            System.assert(TAK_ApprovalService.approve(g.Id, 'ok').success);
            TAK_ApprovalService.DecisionResult second = TAK_ApprovalService.reject(g.Id, 'changed my mind');
            System.assert(!second.success);
            System.assert(second.message.contains('already'));
        }
    }

    @IsTest
    static void missingRequestIsReported() {
        TAK_TestUtil.registerPolicies();
        User approver = TAK_TestUtil.createUser('takmis', 'TAK_Approver');
        TAK_Approval_Gate__c g = pendingGate(UserInfo.getUserId(), 30);
        Id goneId = g.Id;
        delete g;
        System.runAs(approver) {
            TAK_ApprovalService.DecisionResult d = TAK_ApprovalService.approve(goneId, 'ok');
            System.assert(!d.success);
            System.assert(d.message.contains('not found'));
        }
    }

    @IsTest
    static void requestsAreRoutedToConfiguredQueue() {
        Group queue;
        System.runAs(new User(Id = UserInfo.getUserId())) {
            queue = new Group(Name = 'TAK Test Approvers', DeveloperName = 'TAK_Test_Approvers', Type = 'Queue');
            insert queue;
            insert new QueueSobject(QueueId = queue.Id, SobjectType = 'TAK_Approval_Gate__c');
        }
        TAK_PolicyService.Policy p = TAK_TestUtil.basePolicy('Test_Queue', 'TAK_ExampleUpdateContactAction', 'High');
        p.approverQueue = 'TAK_Test_Approvers';
        TAK_Approval_Gate__c g = TAK_ApprovalService.buildRequest(p, 'Agent', 's', 'hash', '{}', null, 0, 'c');
        System.assertEquals(queue.Id, g.OwnerId);

        p.approverQueue = 'No_Such_Queue';
        TAK_Approval_Gate__c g2 = TAK_ApprovalService.buildRequest(p, 'Agent', 's', 'hash', '{}', null, 0, 'c');
        System.assertEquals(null, g2.OwnerId);
    }

    @IsTest
    static void decideInvocableWrapsService() {
        TAK_TestUtil.registerPolicies();
        User approver = TAK_TestUtil.createUser('takinv', 'TAK_Approver');
        TAK_Approval_Gate__c g = pendingGate(UserInfo.getUserId(), 30);
        TAK_DecideApprovalInvocable.Request req = new TAK_DecideApprovalInvocable.Request();
        req.approvalRequestId = g.Id;
        req.approve = true;
        req.comment = 'ok';
        System.runAs(approver) {
            List<TAK_DecideApprovalInvocable.Response> res = TAK_DecideApprovalInvocable.invoke(
                new List<TAK_DecideApprovalInvocable.Request>{ req }
            );
            System.assert(res[0].success, res[0].message);
            System.assertEquals('Approved', res[0].status);
        }
    }
}
