# Demo guide

A 15-minute live demo of Trusted Agent Kit, built as a story: a bank's AI agent faces a normal customer, an attacker, a poisoned record, a large wire, and finally a dishonest insider. Every scene runs the real governance engine.

Run the demo in a Developer Edition, scratch org or sandbox. Never use production.

---

## One-time setup (about 20 minutes)

### 1. Deploy the demo pack

The `demo/` folder adds a scene runner (`TAK_Demo`), a poisoned case-note handler and its policy.

```bash
sf project deploy start --source-dir demo --target-org <your-org-alias>
```

### 2. Permissions for yourself (the "requesting" user)

Setup → Users → your user → Permission Set Assignments. Assign:

- `Trusted Agent Kit - Governance Admin`
- `Trusted Agent Kit - Approver` (so scene 6 shows the segregation-of-duties refusal, not just a missing permission)

### 3. Create a second user: the bank approver

Setup → Users → New User.

| Field | Value |
|---|---|
| Name | e.g. *Priya Approver* |
| User License | Salesforce |
| Profile | System Administrator (so they can run scene 7 from the Developer Console) |
| Email | an address you can receive the activation email at |

Then assign `Trusted Agent Kit - Approver` to this user. Developer Edition orgs include a second full Salesforce licence, which is enough. Activate the user from the email and log in once in a **private / incognito window**. During the demo, keep that window side by side with your own: *"Customer + agent"* on the left, *"Bank approver"* on the right.

### 4. Tabs so the audience can see the records

Setup → Tabs → Custom Object Tabs → New. Create a tab for each, and add them to the app you'll demo from:

- Agent Decision Log
- Agent Approval Request
- Audit Chain State

Check each object's page layout (Object Manager → object → Page Layouts) shows all fields; add any missing ones.

### 5. List views

**Agent Decision Logs → New list view "Audit trail" (All records)**, columns:
Log Number, Sequence, Action Name, Decision, Risk Score, Risk Reasons, User, Output Flagged, Event Timestamp.

**Agent Approval Requests → "Open requests"**, filter *Status equals Pending, Approved*, columns:
Request Number, Status, Action Name, Amount, Risk Tier, Requested By, Decided By, Expires At.

Optional but impressive: a report on Agent Decision Logs grouped by **Decision** with a donut chart, placed on a dashboard.

### 6. Where to run the scenes

Pick one:

- **Developer Console** (simplest on screen): Debug → Open Execute Anonymous Window, paste the one-line command, tick *Open Log*, click Execute, then tick **Debug Only** in the log viewer. Increase the font (Help → Preferences) for the audience.
- **VS Code / terminal** (cleanest output):
  ```bash
  sf apex run --file scripts/apex/01_safe_balance.apex --target-org <alias> | grep "TAK>"
  ```

Each scene is also a one-liner you can type live, e.g. `TAK_Demo.scene2_directInjection();`

### 7. Rehearse, then reset

Rehearse the full run once. **Then reset**, because rate limits count attempts in the last hour and rehearsal approvals would otherwise be reused:

```bash
scripts/reset-demo.sh <alias>
```

On Windows (no bash): `Setup → Apex Triggers → TAK_DecisionLogTrigger → Edit`, untick *Is Active*, save; run `scripts/apex/reset_demo_data.apex`; then tick *Is Active* again. (If Setup doesn't let you edit the trigger, change `<status>Active</status>` to `Inactive` in `TAK_DecisionLogTrigger.trigger-meta.xml`, deploy that folder, and change it back afterwards.)

Finish with `TAK_Demo.status();`. It should report 0 logs and 0 open approvals.

---

## Run sheet

| # | Run as | Command | What the audience sees | Line to say |
|---|---|---|---|---|
| 0 | You | `TAK_Demo.status();` | Policies loaded, clean org | "Every action the agent can take is declared here, with a risk tier. Anything not on this list is refused." |
| 1 | You | `scene1_safeBalance()` | **EXECUTED**. The model sees `[ACCOUNT ****6789]` | "Normal customers aren't slowed down. And the AI model never sees the full account number." |
| 2 | You | `scene2_directInjection()` | **BLOCKED**, risk 100, reasons listed | "Prompt injection. Stopped before any bank system is touched, and logged with the reason." |
| 3 | You | `scene3_hiddenInPayload()` | **BLOCKED**. The customer message was innocent | "The attack was in the memo field. We screen every value, not just the chat." |
| 4 | You | `scene4_indirectInjection()` | **EXECUTED** but result **withheld**, *OUTPUT FLAGGED* | "This is the attack most teams miss: poisoned data in your own systems. The model never reads it." |
| 5 | You | `scene5_requestLargeTransfer()` | **PENDING_APPROVAL**, request AAR-… with masked payload | "Over $10,000, a human decides. Nothing has moved." *Show the record in the Approval Requests tab.* |
| 6 | You | `scene6_trySelfApproval()` | Refused: *Segregation of duties* | "I have approver rights, but I can't approve a request raised under my own session." |
| 7 | **Approver window** | `scene7_approveAsApprover()` | Approved by the second user | "A different employee approves the masked request. The approval is locked to this exact payload, single-use, with a 60-minute window." |
| 8 | You | `scene8_tamperedAmount()` | **PENDING_APPROVAL** again, new request | "Change $25,000 to $95,000 and the approval doesn't carry over." |
| 9 | You | `scene9_executeApproved()` | **EXECUTED**; approval → **Consumed** | "Same request, even reformatted, matches and runs exactly once." |
| 10 | You | `scene10_replay()` | **PENDING_APPROVAL** | "Try to replay it, and it needs a fresh approval." |
| 11 | You | `scene11_rateLimit()` | Attempts 1–5 pending, attempt 6 **BLOCKED** | "Contact-detail changes are an account-takeover step, so they're rate-limited too." |
| 12 | You | `scene12_tryToEditLog()` | Edit and delete both refused | "Even as a System Administrator, I can't change the audit record." |
| 13 | You | `scene13_verifyChain()` | **Chain valid: true**, N records | "This is what an examiner runs: every record hash-chained to the previous one." |

Switch to the **Agent Decision Logs** tab after scene 13: one record for every attempt, including the blocked ones, with PII masked.

### Finale: the dishonest insider (optional, 2 minutes)

The strongest moment. Run it last, because it deliberately breaks the chain in your demo org.

1. `scripts/guard.sh off <alias>`, then say: *"Suppose a privileged insider disables the protection to hide the blocked attack from scene 2."*
2. Run `scripts/apex/insider_tamper.apex`. The blocked record now says *Executed*. Show it in the tab: it looks harmless.
3. Run `TAK_Demo.scene13_verifyChain();` → **Chain valid: false — HASH_MISMATCH at sequence 2**.
4. *"The cover-up is detected, and we know exactly which record was changed. Disabling the guard also leaves an entry in Setup Audit Trail."*
5. Reset afterwards: `scripts/reset-demo.sh <alias>`.

---

## If you have Agentforce

After the scripted demo, show the same controls in a real conversation. Follow [AGENTFORCE_SETUP.md](AGENTFORCE_SETUP.md), then in the agent's preview pane type the customer lines from scenes 1, 2 and 5. Because the agent runs as its own agent user, **you** can approve its requests directly. Then open Agent Decision Logs to show the conversation's audit trail.

## Troubleshooting

| Symptom | Cause / fix |
|---|---|
| Scene 5 says EXECUTED immediately | An approved request is left over from rehearsal. Reset. |
| Everything for a transfer is BLOCKED with `RATE_LIMIT` | More than 10 transfer attempts in the past hour (limit on the Initiate_Transfer policy). Reset, or raise *Max Calls Per Hour* in Setup → Custom Metadata Types → Agent Policy. |
| Scene 6 says "You do not have permission" | Assign the Approver permission set to yourself (setup step 2). |
| Scene 7 says no pending request | Run scene 5 first, as yourself, and within the 60-minute window. |
| `Missing policy Read_Case_Note` | Deploy the `demo` folder (setup step 1). |
| Verify fails without the finale | Something modified logs (for example a reset that only partly ran). Reset. |
| No `TAK>` lines in Developer Console | Tick **Debug Only** in the log, or set the Apex Code log level to DEBUG. |

## Record it

Record the run (a screen recorder at 1080p is enough). Keep it under 8 minutes, add captions with the "line to say" text, and link it from the README. A public demo video gives reviewers and potential adopters an easy way to see the project working.
