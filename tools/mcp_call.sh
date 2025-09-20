#!/usr/bin/env bash
set -euo pipefail
server_cmd="${1:?}"; shift
tool_name="${1:?}"; shift
json_payload_input="${1:-}"
if [ "${json_payload_input:-}" = "/dev/stdin" ] || [ -z "${json_payload_input:-}" ]; then
  payload="$(cat)"
else
  payload="$json_payload_input"
fi
command -v node >/dev/null || { echo "Node.js required" >&2; exit 1; }
if [[ "$server_cmd" != /* ]]; then
  server_cmd="${CODEX_BIN:-$(command -v "$server_cmd" 2>/dev/null || true)}"
fi
server_cmd="$(readlink -f "$server_cmd" 2>/dev/null || echo "$server_cmd")"
if [ -z "$server_cmd" ]; then
  echo "empty server_cmd" >&2
  exit 1
fi
server_exec=""
server_args=()
if [[ "$server_cmd" == *.js ]]; then
  if [[ -x /usr/bin/node ]]; then
    server_exec="/usr/bin/node"
  else
    server_exec="$(command -v node)"
  fi
  [ -x "$server_exec" ] || { echo "node not found" >&2; exit 1; }
  server_args=("$server_cmd" mcp serve)
else
  [ -x "$server_cmd" ] || { echo "Cannot exec codex server: '$server_cmd'" >&2; exit 1; }
  server_exec="$server_cmd"
  server_args=(mcp serve)
fi
npx --yes @modelcontextprotocol/inspector@latest --cli \
  --server.command="$server_exec" \
  $(for a in "${server_args[@]}"; do printf -- '--server.args=%s ' "$a"; done) \
  --method="tools/call" \
  --call.tool="$tool_name" \
  --call.input="$payload"
