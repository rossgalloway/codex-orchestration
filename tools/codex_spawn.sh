#!/usr/bin/env bash
set -euo pipefail
LEDGER_HOME="${LEDGER_HOME:-$HOME/code/codex-orchestration}"
CODEX_BIN="${CODEX_BIN:-$(command -v codex 2>/dev/null || true)}"
CODEX_BIN="$(readlink -f "$CODEX_BIN" 2>/dev/null || echo "$CODEX_BIN")"
[[ -x "$CODEX_BIN" ]] || { echo "codex not found; set CODEX_BIN to absolute path" >&2; exit 1; }
command -v tmux >/dev/null || { echo "tmux required"; exit 1; }
prompt="${1:?}"; cwd="${2:-$PWD}"; sandbox="${3:-workspace-write}"; approval="${4:-on-request}"
payload="$(python3 - "$prompt" "$cwd" "$sandbox" "$approval" <<'PY'
import json,sys
p,c,s,a=sys.argv[1:]
print(json.dumps({"prompt":p,"sandbox":s,"approval-policy":a,"cwd":c,"include-plan-tool":True}))
PY
)"
resp="$("$LEDGER_HOME/tools/mcp_call.sh" "$CODEX_BIN" codex "$payload" 2>&1 || true)"
cid="$(python3 - <<'PY'
import json,sys
data=sys.stdin.read().strip()
try:
    print(json.loads(data)["conversationId"])
except Exception:
    print("")
PY
<<< "$resp")"
if [ -z "$cid" ]; then
  echo "Failed to get conversationId" >&2
  err_data=$(python3 - <<'PY'
import json,sys
print(json.dumps({"raw": sys.stdin.read()}))
PY
<<< "$resp")
  python3 "$LEDGER_HOME/tools/ledger.py" write \
    --type error --agent coordinator --msg "spawn_failed" \
    --data "$err_data"
  exit 2
fi
python3 "$LEDGER_HOME/tools/ledger.py" write --type spawn --agent coordinator --cid "$cid" --cwd "$cwd" --msg "spawn"
msg="Begin. Append progress with: python3 $LEDGER_HOME/tools/ledger.py write --type progress --cid $cid --msg '<update>'"
session="codex-${cid//[^A-Za-z0-9._-]/_}"
tmux new-session -d -s "$session" -c "$cwd" bash -lc "
  printf '{\"conversationId\":\"%s\",\"prompt\":\"%s\"}' '$cid' '$msg' \
  | $LEDGER_HOME/tools/mcp_call.sh \"$CODEX_BIN\" codex-reply /dev/stdin
"
echo "$cid"
