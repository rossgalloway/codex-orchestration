#!/usr/bin/env bash
set -euo pipefail
LEDGER_HOME="${LEDGER_HOME:-$HOME/code/codex-orchestration}"
CODEX_BIN="${CODEX_BIN:-$(command -v codex 2>/dev/null || true)}"
[[ -x "$CODEX_BIN" ]] || { echo "codex not found; set CODEX_BIN" >&2; exit 1; }
command -v tmux >/dev/null || { echo "tmux required"; exit 1; }
prompt="${1:?}"; cwd="${2:-$PWD}"; sandbox="${3:-workspace-write}"; approval="${4:-on-request}"
payload="$(python3 - "$prompt" "$cwd" "$sandbox" "$approval" <<'PY'
import json,sys
p,c,s,a=sys.argv[1:]
print(json.dumps({"prompt":p,"sandbox":s,"approval-policy":a,"cwd":c,"include-plan-tool":True}))
PY
)"
resp="$("$LEDGER_HOME/tools/mcp_call.sh" "$CODEX_BIN" codex "$payload")"
cid="$(python3 - <<'PY'
import json,sys
d=sys.stdin.read().strip()
try: print(json.loads(d)["conversationId"])
except: print("")
PY
<<< "$resp")"
[ -n "$cid" ] || { echo "Failed to get conversationId. Raw output follows:"; echo "$resp"; exit 2; }
python3 "$LEDGER_HOME/tools/ledger.py" write --type spawn --agent coordinator --cid "$cid" --cwd "$cwd" --msg "spawn"
msg="Begin. Append progress with: python3 $LEDGER_HOME/tools/ledger.py write --type progress --cid $cid --msg '<update>'"
tmux new-session -d -s "codex-$cid" -c "$cwd" bash -lc "
  printf '{\"conversationId\":\"%s\",\"prompt\":\"%s\"}' '$cid' '$msg' \
  | $LEDGER_HOME/tools/mcp_call.sh \"$CODEX_BIN\" codex-reply /dev/stdin
"
echo "$cid"
