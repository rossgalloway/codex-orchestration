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
if [[ "$server_cmd" != /* ]]; then
  if [[ -n "${CODEX_BIN:-}" ]]; then
    server_cmd="$CODEX_BIN"
  else
    server_cmd="$(command -v "$server_cmd" 2>/dev/null || true)"
  fi
fi
if [[ -z "${server_cmd:-}" || ! -x "$server_cmd" ]]; then
  echo "Cannot find executable for codex server: '$server_cmd'" >&2
  exit 1
fi
npx --yes @modelcontextprotocol/inspector@latest --cli \
  --server.command="$server_cmd" \
  --server.args="mcp" \
  --server.args="serve" \
  --method="tools/call" \
  --call.tool="$tool_name" \
  --call.input="$payload"
