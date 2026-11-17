/**
 * EXAMPLE handler (mock data). Replace the body with a callout to your core banking
 * balance API. Governed by the Get_Account_Balance policy (low risk, no approval).
 */
public with sharing class TAK_ExampleGetBalanceAction implements TAK_GovernedAction {
    public Map<String, Object> execute(Map<String, Object> payload) {
        String account = payload.get('accountNumber') == null ? null : String.valueOf(payload.get('accountNumber'));
        if (String.isBlank(account)) {
            throw new TAK_GovernanceException('accountNumber is required.');
        }
        return new Map<String, Object>{
            'accountNumber' => account,
            'availableBalance' => 2450.18,
            'currency' => 'USD',
            'asOf' => Datetime.now().formatGmt('yyyy-MM-dd\'T\'HH:mm:ss\'Z\'')
        };
    }
}
