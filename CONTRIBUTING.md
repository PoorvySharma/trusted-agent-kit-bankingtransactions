# Contributing

Thank you for helping make AI agents safer in financial services.

## Most wanted

- **New attack patterns** you have seen against banking assistants. Add them to `force-app/main/default/staticresources/TAK_AdversarialPrompts.json` with `"expect": "block"`.
- **False positives**: ordinary customer messages that get blocked. Add them with `"expect": "allow"`.
- PII formats the redactor misses (with synthetic examples only).
- Translations of the detection rules into other languages.

## Ground rules

- **Never include real customer data**, real account numbers, or anything from an employer's systems. Use synthetic values (e.g. card `4111 1111 1111 1111`, routing `021000021`).
- Keep each detection regex on a single line directly below its `// @rule` marker so the offline harness can extract it.
- Every change to rules must keep `python3 tools/rule-harness/run.py` passing.
- Every Apex change needs tests; keep overall coverage above 90%.

## Workflow

1. Fork and create a branch.
2. `python3 tools/rule-harness/run.py`
3. Deploy to a scratch org and run `sf apex run test --test-level RunLocalTests --code-coverage`.
4. Open a pull request describing the risk your change addresses.

## Reporting a security issue

Please do not open a public issue for a bypass. Email the maintainer (see the repository profile) with steps to reproduce.
