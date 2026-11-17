#!/usr/bin/env python3
"""
Run Trusted Agent Kit's detection rules without a Salesforce org.

Extracts every regex marked `// @rule` from the Apex source, then replays the
adversarial prompt suite and the PII cases below through Java's regex engine
(the same engine Apex uses).

    python3 tools/rule-harness/run.py

Requires Python 3.9+ and a JDK 17+ on PATH.
"""
import base64
import json
import re
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
CLASSES = ROOT / "force-app/main/default/classes"
SUITE = ROOT / "force-app/main/default/staticresources/TAK_AdversarialPrompts.json"
HERE = Path(__file__).resolve().parent

# id, input, expected redacted output
PII_CASES = [
    ("PII-001", "My SSN is 123-45-6789.", "My SSN is [SSN REDACTED]."),
    ("PII-002", "ssn: 123456789", "ssn: [SSN REDACTED]"),
    ("PII-003", "Card 4111 1111 1111 1111 was declined", "Card [CARD ****1111] was declined"),
    ("PII-004", "Card 4111 1111 1111 1112 is a typo", "Card 4111 1111 1111 1112 is a typo"),
    ("PII-005", "routing number 021000021 please", "routing number [ROUTING REDACTED] please"),
    ("PII-006", "account #12345678 is overdrawn", "account #[ACCOUNT ****5678] is overdrawn"),
    ("PII-007", '{"fromAccount":"9876543210","amount":25000}', '{"fromAccount":"[ACCOUNT ****3210]","amount":25000}'),
    ("PII-008", "Reach me at jane.doe@example.com or (312) 555-0199", "Reach me at [EMAIL REDACTED] or [PHONE REDACTED]"),
    ("PII-009", "Call 312-555-0199 about the $25,000.00 wire on 2026-11-06", "Call [PHONE REDACTED] about the $25,000.00 wire on 2026-11-06"),
    ("PII-010", '{"routingNumber":"021000021","accountNumber":"000123456789"}', '{"routingNumber":"[ROUTING REDACTED]","accountNumber":"[ACCOUNT ****6789]"}'),
    ("PII-011", "Order 000-12-3456 is not an SSN", "Order 000-12-3456 is not an SSN"),
    ("PII-012", "Amex 3782 822463 10005 on file", "Amex [CARD ****0005] on file"),
]

RULE_MARKER = re.compile(r"//\s*@rule\s+(\w+)\s+(\w+)\s+(\d+)")
APEX_STRING = re.compile(r"'((?:[^'\\]|\\.)*)'")


def apex_unescape(s: str) -> str:
    out, i = [], 0
    while i < len(s):
        if s[i] == "\\" and i + 1 < len(s):
            nxt = s[i + 1]
            out.append({"n": "\n", "t": "\t", "r": "\r"}.get(nxt, nxt))
            i += 2
        else:
            out.append(s[i])
            i += 1
    return "".join(out)


def extract_rules():
    rules = []
    for cls in sorted(CLASSES.glob("*.cls")):
        lines = cls.read_text().splitlines()
        for i, line in enumerate(lines):
            m = RULE_MARKER.search(line)
            if not m:
                continue
            literals = APEX_STRING.findall(lines[i + 1])
            if not literals:
                sys.exit(f"{cls.name}:{i + 2}: no string literal after @rule marker")
            rules.append((m.group(1), m.group(2), m.group(3), apex_unescape(literals[-1])))
    return rules


def b64(s) -> str:
    return base64.b64encode(str(s).encode("utf-8")).decode()


def main():
    rules = extract_rules()
    suite = json.loads(SUITE.read_text())
    with tempfile.TemporaryDirectory() as tmp:
        t = Path(tmp)
        (t / "rules.tsv").write_text("\n".join("\t".join(b64(x) for x in r) for r in rules) + "\n")
        (t / "cases.tsv").write_text("\n".join("\t".join(b64(c[k]) for k in ("id", "expect", "text")) for c in suite["cases"]) + "\n")
        (t / "pii.tsv").write_text("\n".join("\t".join(b64(x) for x in c) for c in PII_CASES) + "\n")
        subprocess.run(["javac", "-d", tmp, str(HERE / "RuleHarness.java")], check=True)
        res = subprocess.run(["java", "-cp", tmp, "RuleHarness", tmp, str(suite.get("threshold", 50))])
        sys.exit(res.returncode)


if __name__ == "__main__":
    main()
