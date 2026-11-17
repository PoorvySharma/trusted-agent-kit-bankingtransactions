// FINALE ONLY. Requires the log guard to be OFF (scripts/guard.sh off <org>).
// Simulates a privileged insider who disables the guard and rewrites a blocked attack
// as a normal execution to hide it. Run 13_verify_chain.apex afterwards to catch it.
List<TAK_Agent_Decision_Log__c> targets = [
    SELECT Id, Name, Sequence__c, Decision__c
    FROM TAK_Agent_Decision_Log__c
    WHERE Decision__c = 'Blocked'
    ORDER BY Sequence__c ASC
    LIMIT 1
];
if (targets.isEmpty()) {
    System.debug(LoggingLevel.INFO, 'TAK> No blocked record to tamper with. Run scene 2 first.');
} else {
    TAK_Agent_Decision_Log__c t = targets[0];
    System.debug(LoggingLevel.INFO, 'TAK> Insider rewrites ' + t.Name + ' (sequence ' + t.Sequence__c + ') from ' + t.Decision__c + ' to Executed');
    t.Decision__c = 'Executed';
    update t;
    System.debug(LoggingLevel.INFO, 'TAK> Edit saved. The record now looks harmless. Run scene 13 to check the chain.');
}
