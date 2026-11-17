/**
 * Makes the decision log append-only. Any update or delete is rejected, including by
 * administrators. Retention purges should be done by a documented, change-controlled
 * deployment that disables this guard, which itself leaves a Setup Audit Trail entry.
 */
public without sharing class TAK_DecisionLogGuard {
    public static final String MESSAGE = 'Agent Decision Logs are append-only and cannot be changed or deleted.';

    @TestVisible
    private static Boolean allowMutationForTest = false;

    public static void preventMutation(List<TAK_Agent_Decision_Log__c> records) {
        if (allowMutationForTest) {
            return;
        }
        for (TAK_Agent_Decision_Log__c r : records) {
            r.addError(MESSAGE);
        }
    }
}
