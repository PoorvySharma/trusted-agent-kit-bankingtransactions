@IsTest
private class TAK_DemoTest {
    @IsTest
    static void fullDemoRunsEndToEnd() {
        User approver = TAK_TestUtil.createUser('takdemo', 'TAK_Approver');

        TAK_Demo.status();
        TAK_Demo.scene1_safeBalance();
        TAK_Demo.scene2_directInjection();
        TAK_Demo.scene3_hiddenInPayload();
        TAK_Demo.scene4_indirectInjection();
        TAK_Demo.scene5_requestLargeTransfer();
        TAK_Demo.scene6_trySelfApproval();
        System.runAs(approver) {
            TAK_Demo.scene7_approveAsApprover();
        }
        TAK_Demo.scene8_tamperedAmount();
        TAK_Demo.scene9_executeApproved();
        TAK_Demo.scene10_replay();
        TAK_Demo.scene11_rateLimit();
        TAK_Demo.scene12_tryToEditLog();
        TAK_Demo.scene13_verifyChain();
        TAK_Demo.recentLogs(5);

        Set<String> decisions = new Set<String>();
        Boolean flagged = false;
        for (TAK_Agent_Decision_Log__c l : [SELECT Decision__c, Output_Flagged__c FROM TAK_Agent_Decision_Log__c]) {
            decisions.add(l.Decision__c);
            flagged = flagged || l.Output_Flagged__c;
        }
        System.assert(decisions.containsAll(new Set<String>{ 'Executed', 'Blocked', 'Pending Approval', 'Approval Granted' }), decisions);
        System.assert(flagged, 'scene 4 should flag the poisoned case note');
        System.assertEquals(1, [SELECT COUNT() FROM TAK_Approval_Gate__c WHERE Status__c = 'Consumed']);
        System.assert(TAK_AuditChainVerifier.verifyAll().valid);
    }

    @IsTest
    static void scenesHandleMissingPrerequisites() {
        TAK_Demo.scene6_trySelfApproval();
        TAK_Demo.scene7_approveAsApprover();
        TAK_Demo.scene12_tryToEditLog();
        TAK_Demo.scene13_verifyChain();
        System.assertEquals(0, [SELECT COUNT() FROM TAK_Agent_Decision_Log__c]);
    }
}
