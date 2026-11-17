/**
 * Contract for any bank action an AI agent is allowed to perform through Trusted Agent Kit.
 *
 * Implementations do the real work (call core banking, update records, etc.). They never
 * need to handle governance: the runner has already checked policy, screened for prompt
 * injection, enforced rate limits and approvals before execute() is called, and it logs
 * and redacts the result afterwards.
 *
 * Callouts are safe here: the runner performs no DML until after execute() returns.
 */
public interface TAK_GovernedAction {
    /**
     * @param payload  the action's parameters, parsed from the JSON the agent supplied
     * @return         a result map; it is redacted and screened before reaching the agent
     */
    Map<String, Object> execute(Map<String, Object> payload);
}
