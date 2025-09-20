#!/usr/bin/env bash
set -euo pipefail

server_cmd="${1:?}"     # absolute path preferred (codex or codex.js)
tool_name="${2:?}"      # 'codex' or 'codex-reply'
json_payload_input="${3:-}"

# Read payload from arg or stdin
if [ "${json_payload_input:-}" = "/dev/stdin" ] || [ -z "${json_payload_input:-}" ]; then
  payload="$(cat)"
else
  payload="$json_payload_input"
fi

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
  # JS entrypoint → launch via a stable node
  NODE_BIN="${MCP_NODE_BIN:-/usr/bin/node}"
  if [[ ! -x "$NODE_BIN" ]]; then NODE_BIN="$(command -v node || true)"; fi
  [[ -x "$NODE_BIN" ]] || { echo "node not found for JS entrypoint" >&2; exit 1; }
  server_exec="$NODE_BIN"
  server_args=( "$server_cmd" mcp serve )
else
  [[ -x "$server_cmd" ]] || { echo "Cannot exec codex server: '$server_cmd'" >&2; exit 1; }
  server_exec="$server_cmd"
  server_args=( mcp serve )
fi

# Expand the JSON payload into repeated --tool-arg key=value tokens
mapfile -t KV < <(python3 - <<'PY' "$payload"
import json, sys
data = json.loads(sys.argv[1])
for k, v in data.items():
  if isinstance(v, (dict, list)): s = json.dumps(v, separators=(',',':'))
  elif isinstance(v, bool): s = 'true' if v else 'false'
  else: s = str(v)
  print(f"{k}={s}")
PY
)

tool_args=()
for kv in "${KV[@]}"; do tool_args+=( --tool-arg "$kv" ); done

# Prefer global binary if installed to avoid npx download each time
if command -v mcp-inspector >/dev/null 2>&1; then
  INSPECTOR=(mcp-inspector)
else
  INSPECTOR=(npx --yes @modelcontextprotocol/inspector@latest)
fi

# Call Inspector CLI:
#   <inspector> --cli <server_command> <server_args...> --method tools/call --tool-name <tool> --tool-arg k=v ...
"${INSPECTOR[@]}" --cli \
  "$server_exec" "${server_args[@]}" \
  --method tools/call \
  --tool-name "$tool_name" \
  "${tool_args[@]}"
