/**
 * EXAMPLE handler (mock). Replace the body with a callout to your payments platform.
 * Governed by the Initiate_Transfer policy: approval required at or above $10,000.
 */
public with sharing class TAK_ExampleInitiateTransferAction implements TAK_GovernedAction {
    public Map<String, Object> execute(Map<String, Object> payload) {
        Object amountRaw = payload.get('amount');
        if (payload.get('fromAccount') == null || payload.get('toAccount') == null || amountRaw == null) {
            throw new TAK_GovernanceException('fromAccount, toAccount and amount are required.');
        }
        Decimal amount = Decimal.valueOf(String.valueOf(amountRaw));
        if (amount <= 0) {
            throw new TAK_GovernanceException('amount must be positive.');
        }
        return new Map<String, Object>{
            'confirmationNumber' => 'TRF-' + String.valueOf(Crypto.getRandomInteger()).replace('-', '').left(8),
            'status' => 'SUBMITTED',
            'amount' => amount
        };
    }
}
