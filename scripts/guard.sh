#!/usr/bin/env bash
# Turns the append-only guard on the Agent Decision Log on or off by redeploying the trigger.
# Used only for the tamper finale and for resetting demo data. Never use in production.
#
#   scripts/guard.sh off my-demo-org
#   scripts/guard.sh on  my-demo-org
set -euo pipefail
MODE="${1:-}"
ORG="${2:-}"
if [[ -z "$MODE" || -z "$ORG" ]]; then
  echo "usage: scripts/guard.sh on|off <org-alias>" >&2
  exit 1
fi
case "$MODE" in
  off) STATUS=Inactive ;;
  on)  STATUS=Active ;;
  *)   echo "first argument must be on or off" >&2; exit 1 ;;
esac
cd "$(dirname "$0")/.."
META=force-app/main/default/triggers/TAK_DecisionLogTrigger.trigger-meta.xml
sed -i.bak -E "s#<status>[A-Za-z]+</status>#<status>${STATUS}</status>#" "$META" && rm -f "$META.bak"
sf project deploy start --source-dir force-app/main/default/triggers --target-org "$ORG" --wait 10
echo "Decision log guard is now ${STATUS}."
