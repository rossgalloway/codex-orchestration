#!/usr/bin/env bash
set -euo pipefail
prompt="$1"
cwd="${2:-$PWD}"
sandbox="${3:-workspace-write}"
approval="${4:-on-request}"
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ledger_home="${LEDGER_HOME:-$(cd "$script_dir/.." && pwd)}"
ledger_cli="$ledger_home/tools/ledger.py"
payload=$(jq -n --arg p "$prompt" --arg s "$sandbox" --arg a "$approval" --arg c "$cwd" '{prompt:$p,"sandbox":$s,"approval-policy":$a,"cwd":$c,"include-plan-tool":true}')
resp=$(printf '%s' "$payload" | codex mcp call codex)
cid=$(printf '%s' "$resp" | jq -r '.conversationId')
python3 "$ledger_cli" write --type spawn --agent coordinator --cid "$cid" --cwd "$cwd" --msg "spawn"
msg="Begin. Append progress to agents/ledger.jsonl via: python3 \"$ledger_cli\" write --type progress --cid $cid --msg '<update>'"
tmux new-session -d -s "codex-$cid" bash -lc "printf '{\"conversationId\":\"%s\",\"prompt\":\"%s\"}' '$cid' '$msg' | codex mcp call codex-reply"
echo "$cid"
