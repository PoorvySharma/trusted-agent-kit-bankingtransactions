#!/usr/bin/env bash
# One command to wipe demo data and restore the guard:  scripts/reset-demo.sh my-demo-org
set -euo pipefail
ORG="${1:?usage: scripts/reset-demo.sh <org-alias>}"
cd "$(dirname "$0")/.."
trap 'scripts/guard.sh on "$ORG"' EXIT
scripts/guard.sh off "$ORG"
sf apex run --file scripts/apex/reset_demo_data.apex --target-org "$ORG" | grep "TAK>" || true
