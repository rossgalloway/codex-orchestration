#!/usr/bin/env bash
set -euo pipefail
cid="$1"
message="$2"
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ledger_home="${LEDGER_HOME:-$(cd "$script_dir/.." && pwd)}"
ledger_cli="$ledger_home/tools/ledger.py"
printf '{"conversationId":"%s","prompt":"%s"}' "$cid" "$message" | codex mcp call codex-reply
python3 "$ledger_cli" write --type reply --agent coordinator --cid "$cid" --msg "$message"
