# Model risk documentation template: AI agent with Trusted Agent Kit controls

Use this template to document an AI agent deployment for your model risk management (MRM) function. The section structure follows the themes of the U.S. interagency supervisory guidance on model risk management (Federal Reserve SR 11-7 / OCC 2011-12): purpose and use, conceptual soundness, data, ongoing monitoring, outcomes analysis, limitations, and governance. Your institution's own MRM standards take precedence; adapt freely.

Text in *italics* is guidance. Replace `[brackets]` with your details.

---

## 1. Overview

| Item | Value |
|---|---|
| Agent name | `[e.g. Retail Servicing Agent]` |
| Platform | Salesforce Agentforce, `[release]` |
| Language model(s) | `[as configured in the platform]` |
| Business owner | `[name, title]` |
| Model owner / developer | `[name, title]` |
| MRM risk rating | `[High / Medium / Low]` |
| Trusted Agent Kit version | `[e.g. 0.1.0]` |

*Describe what the agent does, for whom, and through which channels.*

## 2. Intended use and boundaries

- **In scope:** `[e.g. balance inquiries, internal transfers, contact-information changes]`
- **Out of scope:** `[e.g. credit decisions, investment advice, account opening]`
- **Users:** `[customers via web chat / employees in the console]`

List every governed action and its policy:

| Action | Risk tier | Approval rule | Rate limit | Redact output |
|---|---|---|---|---|
| `Get_Account_Balance` | Low | None | 60/hour | Yes |
| `Initiate_Transfer` | Critical | At or above $10,000 | 10/hour | Yes |
| `Update_Contact_Info` | High | Always | 5/hour | Yes |

*Confirm no ungoverned action in the agent's topics can reach the same systems.*

## 3. Conceptual soundness

*Explain why the control design is appropriate for the risks.*

- The language model selects actions and fills parameters; **it does not make control decisions.** Policy enforcement, approval and logging are deterministic Apex.
- High-impact actions require human approval bound to the exact payload (see `docs/ARCHITECTURE.md`).
- Unknown actions are blocked (fail-closed).
- Prompt-injection screening uses transparent, versioned rules with documented weights and a regression suite.

## 4. Data

| Data | Source | Sent to model? | Stored in logs? |
|---|---|---|---|
| Customer message | Chat channel | Yes (platform) | Yes, PII-masked |
| Action payload | Agent | n/a | Yes, PII-masked |
| Action results | `[core system]` | Masked per policy | Yes, PII-masked |

*Describe retention for Agent Decision Logs (e.g. 7 years) and how retention purges are change-controlled.*

## 5. Testing and validation

| Test | Evidence | Result |
|---|---|---|
| Apex unit tests | `sf apex run test` output, coverage report | `[pass / %]` |
| Adversarial suite | `TAK_AdversarialSuiteTest` and `tools/rule-harness` output | `[n/n]` |
| Institution-specific red team | `[cases added to TAK_AdversarialPrompts.json]` | `[n/n]` |
| False-positive review | `[sample of real benign messages scored]` | `[rate]` |
| Approval bypass attempts | `[payload change, replay, self-approval, expiry]` | `[pass]` |
| Audit chain tamper test | Edit / delete in sandbox, run verifier | `[detected]` |

*Record the injection threshold chosen per action and the rationale.*

## 6. Limitations and compensating controls

| Limitation | Compensating control |
|---|---|
| Rule-based injection screening misses paraphrased, novel or non-English attacks | Human approval for money movement; least-privilege agent user; platform trust layer; periodic red-teaming with new cases added to the suite |
| PII masking is pattern-based; names and addresses are not masked | Field-level security; restrict log access to `TAK_Governance_Admin`; consider Shield Platform Encryption |
| If a handler's external call succeeds but the subsequent log write fails, the action happened without a log record | Reconcile core-system transaction records with the decision log daily; alert on unmatched transactions |
| A privileged deployment can disable the append-only trigger | Change control; Setup Audit Trail review; export the chain-head hash daily to a write-once store outside Salesforce |
| Approval binding is per requesting user; two colluding employees can approve each other | Approver monitoring report; dual approval for the highest tier `[if implemented]` |

## 7. Ongoing monitoring

| Metric | Source | Threshold / action |
|---|---|---|
| Blocked rate by action | Decision Log report | Investigate spikes > `[x]%` week over week |
| Top injection signals | `Risk_Reasons__c` | Review weekly; tune rules |
| Approval turnaround | Approval Request `Decided_At__c - CreatedDate` | `[SLA]` |
| Rejected approvals | Approval Request report | Review each |
| Output flagged (indirect injection) | `Output_Flagged__c = true` | Review each; trace source record |
| Chain verification | Audit Chain State | Any non-VALID result is an incident |

## 8. Governance and change control

- Changes to Agent Policy records, detection rules or handler classes follow `[change process]` and require re-running the adversarial suite.
- Approver and admin permission sets are reviewed `[quarterly]`.
- This document is reviewed `[annually]` or on any material change.

## 9. Sign-off

| Role | Name | Date |
|---|---|---|
| Model owner | | |
| Business owner | | |
| Model risk management | | |
| Information security | | |
| Compliance | | |
