#!/usr/bin/env bash
set -euo pipefail
LEDGER_HOME="${LEDGER_HOME:-$HOME/code/codex-orchestration}"
CODEX_BIN="${CODEX_BIN:-$(command -v codex 2>/dev/null || true)}"
CODEX_BIN="$(readlink -f "$CODEX_BIN" 2>/dev/null || echo "$CODEX_BIN")"
[[ -x "$CODEX_BIN" ]] || { echo "codex not found; set CODEX_BIN to absolute path" >&2; exit 1; }
cid="${1:?}"; message="${2:?}"
payload="$(python3 - "$cid" "$message" <<'PY'
import json,sys
c,m=sys.argv[1:]
print(json.dumps({"conversationId":c,"prompt":m}))
PY
)"
out="$(printf '%s' "$payload" | "$LEDGER_HOME/tools/mcp_call.sh" "$CODEX_BIN" codex-reply /dev/stdin 2>&1 || true)"
if ! grep -q '"content"' <<<"$out"; then
  err_data=$(python3 - <<'PY'
import json,sys
print(json.dumps({"raw": sys.stdin.read()}))
PY
<<< "$out")
  python3 "$LEDGER_HOME/tools/ledger.py" write --type error --agent coordinator --cid "$cid" --msg "reply_failed" --data "$err_data"
fi
python3 "$LEDGER_HOME/tools/ledger.py" write --type reply --agent coordinator --cid "$cid" --msg "$message"
