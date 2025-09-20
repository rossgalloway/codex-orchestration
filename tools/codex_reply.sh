#!/usr/bin/env bash
set -euo pipefail
LEDGER_HOME="${LEDGER_HOME:-$HOME/code/codex-orchestration}"
CODEX_BIN="${CODEX_BIN:-$(command -v codex 2>/dev/null || true)}"
[[ -x "$CODEX_BIN" ]] || { echo "codex not found; set CODEX_BIN" >&2; exit 1; }
cid="${1:?}"; message="${2:?}"
payload="$(python3 - "$cid" "$message" <<'PY'
import json,sys
c,m=sys.argv[1:]
print(json.dumps({"conversationId":c,"prompt":m}))
PY
)"
printf '%s' "$payload" | "$LEDGER_HOME/tools/mcp_call.sh" "$CODEX_BIN" codex-reply /dev/stdin
python3 "$LEDGER_HOME/tools/ledger.py" write --type reply --agent coordinator --cid "$cid" --msg "$message"
