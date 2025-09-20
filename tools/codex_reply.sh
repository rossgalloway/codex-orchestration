#!/usr/bin/env bash
set -euo pipefail
LEDGER_HOME="${LEDGER_HOME:-$HOME/code/codex-orchestration}"
cid="${1:?}"; message="${2:?}"
payload="$(python3 - "$cid" "$message" <<'PY'
import json,sys
c,m=sys.argv[1:]
print(json.dumps({"conversationId":c,"prompt":m}))
PY
)"
printf '%s' "$payload" | "$LEDGER_HOME/tools/mcp_call.sh" codex codex-reply /dev/stdin
python3 "$LEDGER_HOME/tools/ledger.py" write --type reply --agent coordinator --cid "$cid" --msg "$message"
