the failure is now:

```
Failed to connect to MCP server: spawn --server.command=/home/ross/.nvm/versions/node/v22.19.0/bin/node ENOENT
```

So the Inspector is trying to exec your **NVM Node path**, and the OS says “no such file or directory” for that exact path in this spawn context. Two rock-solid fixes:

---

# Fix 1 (quick + robust): use the system Node (`/usr/bin/node`) to launch the Codex JS

1. Install system Node (separate from NVM), so we have a stable binary at `/usr/bin/node`:

```bash
sudo apt-get update
sudo apt-get install -y nodejs
command -v /usr/bin/node && /usr/bin/node -v
```

2. Patch `tools/mcp_call.sh` so **.js → /usr/bin/node** (not the NVM path):

Replace the file contents with this:

```bash
#!/usr/bin/env bash
set -euo pipefail

server_cmd="${1:?}"     # absolute path preferred
tool_name="${2:?}"      # 'codex' or 'codex-reply'
json_payload_input="${3:-}"

# Read payload from arg or stdin
if [ "${json_payload_input:-}" = "/dev/stdin" ] || [ -z "${json_payload_input:-}" ]; then
  payload="$(cat)"
else
  payload="$json_payload_input"
fi

command -v node >/dev/null || { echo "Node.js required" >&2; exit 1; }

# Resolve server_cmd -> absolute path (prefer CODEX_BIN if provided)
if [[ "$server_cmd" != /* ]]; then
  server_cmd="${CODEX_BIN:-$(command -v "$server_cmd" 2>/dev/null || true)}"
fi
server_cmd="$(readlink -f "$server_cmd" 2>/dev/null || echo "$server_cmd")"
[ -n "$server_cmd" ] || { echo "empty server_cmd" >&2; exit 1; }

# Decide how to exec the server
server_exec=""
server_args=()
if [[ "$server_cmd" == *.js ]]; then
  # Use a stable system node, not NVM's path
  if [[ -x /usr/bin/node ]]; then
    server_exec="/usr/bin/node"
  else
    server_exec="$(command -v node)"
  fi
  [ -x "$server_exec" ] || { echo "node not found" >&2; exit 1; }
  server_args=( "$server_cmd" mcp serve )
else
  [ -x "$server_cmd" ] || { echo "Cannot exec codex server: '$server_cmd'" >&2; exit 1; }
  server_exec="$server_cmd"
  server_args=( mcp serve )
fi

# Call Inspector CLI
npx --yes @modelcontextprotocol/inspector@latest --cli \
  --server.command="$server_exec" \
  $(for a in "${server_args[@]}"; do printf -- '--server.args=%s ' "$a"; done) \
  --method="tools/call" \
  --call.tool="$tool_name" \
  --call.input="$payload"
```

```bash
chmod +x "$LEDGER_HOME/tools/mcp_call.sh"
```

3. Test a direct call (no wrappers besides mcp\_call):

```bash
echo "CODEX_BIN=$CODEX_BIN"
"$LEDGER_HOME/tools/mcp_call.sh" "$CODEX_BIN" codex \
'{"prompt":"ping","sandbox":"workspace-write","approval-policy":"on-request","cwd":"'"$(pwd)"'","include-plan-tool":true}'
```

4. If that prints JSON (good), run the normal spawn:

```bash
CID=$(codex_spawn.sh "Say hello and write one progress entry via ledger.py." "$(pwd)")
echo "CID=$CID"
```
