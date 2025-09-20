## MCP-native spawn/reply (Inspector CLI)
Prereq: Node installed (`node -v`), Codex MCP server available via `codex mcp serve`.
Environment:
```
export LEDGER_HOME="$HOME/code/codex-orchestration"
export PATH="$LEDGER_HOME/tools:$PATH"
```
Spawn:
```
CID=$(codex_spawn.sh "Say hello. Write a progress line to agents/ledger.jsonl." "$(pwd)")
echo "$CID"
```
Reply:
```
codex_reply.sh "$CID" "Status? If blocked, log reason + next step via ledger."
```
Each task runs in `tmux` as `codex-$CID`. Progress should appear in `agents/ledger.jsonl` and be pushed by the background pusher.

Run:
- chmod +x tools/mcp_call.sh tools/codex_spawn.sh tools/codex_reply.sh
- Do not change other files.
- Commit with message: "feat(mcp): inspector-based spawn/reply scripts"
- End.
