@IsTest
public class TAK_TestUtil {
    public static final String BALANCE = 'Test_Balance';
    public static final String TRANSFER = 'Test_Transfer';
    public static final String CONTACT = 'Test_Contact';

    /** Registers in-memory policies so tests do not depend on deployed metadata values. */
    public static void registerPolicies() {
        TAK_PolicyService.Policy balance = basePolicy(BALANCE, 'TAK_ExampleGetBalanceAction', 'Low');
        balance.maxCallsPerHour = 3;
        TAK_PolicyService.registerForTest(balance);

        TAK_PolicyService.Policy transfer = basePolicy(TRANSFER, 'TAK_ExampleInitiateTransferAction', 'Critical');
        transfer.requiresApproval = true;
        transfer.approvalAmountThreshold = 10000;
        transfer.amountField = 'amount';
        TAK_PolicyService.registerForTest(transfer);

        TAK_PolicyService.Policy contact = basePolicy(CONTACT, 'TAK_ExampleUpdateContactAction', 'High');
        contact.requiresApproval = true;
        TAK_PolicyService.registerForTest(contact);
    }

    public static TAK_PolicyService.Policy basePolicy(String action, String handler, String tier) {
        TAK_PolicyService.Policy p = new TAK_PolicyService.Policy();
        p.sourceName = action;
        p.actionName = action;
        p.handlerClass = handler;
        p.riskTier = tier;
        p.active = true;
        p.redactOutput = true;
        return p;
    }

    public static User createUser(String alias, String permissionSetName) {
        Profile prof = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        String unique = alias + String.valueOf(Crypto.getRandomInteger()).replace('-', '');
        User u = new User(
            Alias = alias.left(8),
            Email = unique + '@tak.example.com',
            EmailEncodingKey = 'UTF-8',
            LastName = 'TAK ' + alias,
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            ProfileId = prof.Id,
            TimeZoneSidKey = 'America/Chicago',
            Username = unique + '@tak.example.com'
        );
        System.runAs(new User(Id = UserInfo.getUserId())) {
            insert u;
            if (permissionSetName != null) {
                PermissionSet ps = [SELECT Id FROM PermissionSet WHERE Name = :permissionSetName LIMIT 1];
                insert new PermissionSetAssignment(AssigneeId = u.Id, PermissionSetId = ps.Id);
            }
        }
        return u;
    }

    public static List<TAK_Agent_Decision_Log__c> logs() {
        return [
            SELECT Id, Decision__c, Risk_Score__c, Risk_Reasons__c, Input_Redacted__c, Output_Redacted__c,
                Output_Flagged__c, Approval_Gate__c, Sequence__c, Action_Name__c, Correlation_Id__c, User__c
            FROM TAK_Agent_Decision_Log__c
            ORDER BY Sequence__c ASC
        ];
    }
}
