// Deletes ALL Trusted Agent Kit demo data so the next run starts clean.
// Requires the log guard to be OFF (scripts/guard.sh off <org>). Never run in production.
Integer logs = [SELECT COUNT() FROM TAK_Agent_Decision_Log__c];
Integer gates = [SELECT COUNT() FROM TAK_Approval_Gate__c];
delete [SELECT Id FROM TAK_Agent_Decision_Log__c];
delete [SELECT Id FROM TAK_Approval_Gate__c];
delete [SELECT Id FROM TAK_Audit_Chain__c];
System.debug(LoggingLevel.INFO, 'TAK> Reset complete: deleted ' + logs + ' logs and ' + gates + ' approval requests. Turn the guard back ON.');
