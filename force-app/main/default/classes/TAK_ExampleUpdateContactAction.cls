/**
 * EXAMPLE handler (mock). Changing a phone number or email is a classic account-takeover
 * step, so the Update_Contact_Info policy always requires approval.
 */
public with sharing class TAK_ExampleUpdateContactAction implements TAK_GovernedAction {
    public Map<String, Object> execute(Map<String, Object> payload) {
        if (payload.get('customerId') == null) {
            throw new TAK_GovernanceException('customerId is required.');
        }
        return new Map<String, Object>{ 'status' => 'UPDATED', 'customerId' => payload.get('customerId') };
    }
}
