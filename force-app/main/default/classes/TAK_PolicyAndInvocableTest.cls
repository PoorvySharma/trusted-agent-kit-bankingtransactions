@IsTest
private class TAK_PolicyAndInvocableTest {
    @IsTest
    static void deployedSamplePoliciesLoad() {
        TAK_PolicyService.Policy transfer = TAK_PolicyService.forAction('initiate_transfer');
        System.assertNotEquals(null, transfer, 'sample Initiate_Transfer policy should be deployed');
        System.assert(transfer.requiresApproval);
        System.assertEquals('amount', transfer.amountField);
        System.assertEquals('TAK_ExampleInitiateTransferAction', transfer.handlerClass);
        System.assertEquals(null, TAK_PolicyService.forAction(null));
        System.assertEquals(null, TAK_PolicyService.forAction('No_Such_Action'));
    }

    @IsTest
    static void fromRecordAppliesDefaults() {
        TAK_Agent_Policy__mdt rec = (TAK_Agent_Policy__mdt) JSON.deserialize(
            '{"DeveloperName":"Sample","Action_Name__c":null,"Active__c":true,"Redact_Output__c":false,'
                + '"Max_Calls_Per_Hour__c":7,"Injection_Threshold__c":40,"Approval_Expiry_Minutes__c":0}',
            TAK_Agent_Policy__mdt.class
        );
        TAK_PolicyService.Policy p = TAK_PolicyService.fromRecord(rec);
        System.assertEquals('Sample', p.actionName, 'falls back to DeveloperName');
        System.assertEquals(7, p.maxCallsPerHour);
        System.assertEquals(40, p.injectionThreshold);
        System.assertEquals(TAK_PolicyService.DEFAULT_APPROVAL_EXPIRY_MINUTES, p.approvalExpiryMinutes);
        System.assert(!p.redactOutput);
        System.assert(!p.requiresApproval);
    }

    @IsTest
    static void amountExtractionHandlesFormats() {
        Map<String, Object> p = new Map<String, Object>{ 'Amount' => '$25,000.50' };
        System.assertEquals(25000.50, TAK_GovernanceGateway.extractAmount(p, 'amount'));
        System.assertEquals(null, TAK_GovernanceGateway.extractAmount(p, null));
        System.assertEquals(null, TAK_GovernanceGateway.extractAmount(new Map<String, Object>{ 'amount' => 'abc' }, 'amount'));
        System.assertEquals(null, TAK_GovernanceGateway.extractAmount(new Map<String, Object>(), 'amount'));
    }

    @IsTest
    static void genericInvocableRunsGovernedAction() {
        TAK_TestUtil.registerPolicies();
        TAK_RunGovernedActionInvocable.Request req = new TAK_RunGovernedActionInvocable.Request();
        req.actionName = TAK_TestUtil.BALANCE;
        req.payloadJson = '{"accountNumber":"12345678"}';
        req.userMessage = 'balance please';
        req.sessionId = 'sess-9';
        List<TAK_RunGovernedActionInvocable.Response> res = TAK_RunGovernedActionInvocable.invoke(
            new List<TAK_RunGovernedActionInvocable.Request>{ req }
        );
        System.assertEquals('EXECUTED', res[0].status);
        System.assert(res[0].executed);
        TAK_Agent_Decision_Log__c log = [SELECT Agent_Name__c, Session_Id__c FROM TAK_Agent_Decision_Log__c];
        System.assertEquals('Agentforce', log.Agent_Name__c);
        System.assertEquals('sess-9', log.Session_Id__c);
    }

    @IsTest
    static void typedTransferActionUsesTransferPolicy() {
        TAK_PolicyService.Policy p = TAK_TestUtil.basePolicy(
            TAK_InitiateTransferAgentAction.ACTION_NAME, 'TAK_ExampleInitiateTransferAction', 'Critical'
        );
        p.requiresApproval = true;
        p.approvalAmountThreshold = 10000;
        p.amountField = 'amount';
        TAK_PolicyService.registerForTest(p);

        TAK_InitiateTransferAgentAction.Request small = new TAK_InitiateTransferAgentAction.Request();
        small.fromAccount = '11112222';
        small.toAccount = '33334444';
        small.amount = 250;
        TAK_InitiateTransferAgentAction.Request large = new TAK_InitiateTransferAgentAction.Request();
        large.fromAccount = '11112222';
        large.toAccount = '33334444';
        large.amount = 50000;
        large.userMessage = 'paying for the house';

        List<TAK_InitiateTransferAgentAction.Response> res = TAK_InitiateTransferAgentAction.invoke(
            new List<TAK_InitiateTransferAgentAction.Request>{ small, large }
        );
        System.assertEquals('EXECUTED', res[0].status);
        System.assert(res[0].resultJson.contains('TRF-'));
        System.assertEquals('PENDING_APPROVAL', res[1].status);
        System.assertNotEquals(null, res[1].approvalRequestId);
        System.assert(TAK_AuditChainVerifier.verifyAll().valid);
    }

    @IsTest
    static void exampleHandlersValidateInput() {
        Boolean threw = false;
        try {
            new TAK_ExampleInitiateTransferAction().execute(
                new Map<String, Object>{ 'fromAccount' => 'a', 'toAccount' => 'b', 'amount' => -5 }
            );
        } catch (TAK_GovernanceException e) {
            threw = true;
        }
        System.assert(threw, 'negative amounts are rejected');

        threw = false;
        try {
            new TAK_ExampleInitiateTransferAction().execute(new Map<String, Object>());
        } catch (TAK_GovernanceException e) {
            threw = true;
        }
        System.assert(threw, 'missing fields are rejected');

        Map<String, Object> ok = new TAK_ExampleUpdateContactAction().execute(new Map<String, Object>{ 'customerId' => 'C-1' });
        System.assertEquals('UPDATED', ok.get('status'));
    }
}
