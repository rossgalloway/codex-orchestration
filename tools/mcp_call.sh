#!/usr/bin/env bash
set -euo pipefail
server_cmd="${1:?}"; shift
tool_name="${1:?}"; shift
json_payload_input="${1:-}"
if [ "$json_payload_input" = "/dev/stdin" ] || [ -z "$json_payload_input" ]; then
  payload="$(cat)"
else
  payload="$json_payload_input"
fi
command -v node >/dev/null || { echo "Node.js required"; exit 1; }
npx @modelcontextprotocol/inspector@latest --cli \
  --server.command "$server_cmd" \
  --server.args mcp serve \
  --call.tool "$tool_name" \
  --call.input "$payload"
