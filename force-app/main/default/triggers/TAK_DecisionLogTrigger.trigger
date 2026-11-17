trigger TAK_DecisionLogTrigger on TAK_Agent_Decision_Log__c (before update, before delete) {
    TAK_DecisionLogGuard.preventMutation(Trigger.isDelete ? Trigger.old : Trigger.new);
}
