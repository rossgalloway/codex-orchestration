#!/usr/bin/env python3
import json
import os
import subprocess
import sys

LEDGER_HOME = os.environ.get("LEDGER_HOME", os.path.expanduser("~/code/codex-orchestration"))
MCP_CALL = os.path.join(LEDGER_HOME, "tools", "mcp_call.sh")
CODEX_BIN = os.environ.get("CODEX_BIN") or subprocess.run(
    ["bash", "-lc", "command -v codex"],
    text=True,
    capture_output=True,
).stdout.strip()

def run_command(invocation, **kwargs):
    return subprocess.run(invocation, text=True, capture_output=True, **kwargs)

def codex_call(payload, tool):
    env = os.environ.copy()
    payload_json = json.dumps(payload)
    if CODEX_BIN:
        cmd = [MCP_CALL, CODEX_BIN, tool, payload_json]
    else:
        cmd = [MCP_CALL, "codex", tool, payload_json]
    process = run_command(cmd, env=env)
    return process.stdout or process.stderr

def handle_spawn(args):
    payload = {
        "prompt": args.get("prompt", ""),
        "sandbox": args.get("sandbox", "workspace-write"),
        "approval-policy": args.get("approval", "on-request"),
        "cwd": args.get("cwd", "."),
        "include-plan-tool": True,
    }
    output = codex_call(payload, "codex")
    try:
        conversation_id = json.loads(output)["conversationId"]
    except Exception:
        conversation_id = "unknown"
    body = f"🛠️ spawned: cid `{conversation_id}`\n\n```\n{output}\n```"
    return body

def handle_reply(args):
    payload = {
        "conversationId": args.get("cid", ""),
        "prompt": args.get("message", ""),
    }
    output = codex_call(payload, "codex-reply")
    body = f"💬 reply → `{args.get('cid', '')}`\n\n```\n{output}\n```"
    return body

def handle_abort(args):
    session_name = f"codex-{args.get('cid', '')}"
    subprocess.run(["tmux", "kill-session", "-t", session_name])
    return f"🛑 aborted session `{session_name}`"

def handle_status(args):
    return f"ℹ️ status for `{args.get('cid', '')}` not yet implemented."

def handle_help():
    return (
        "Available: `@codex spawn \"prompt\" cwd=/path [sandbox=..] [approval=..]`, "
        "`@codex reply cid=... \"msg\"`, `@codex abort cid=...`, `@codex status cid=...`"
    )

HANDLERS = {
    "spawn": handle_spawn,
    "reply": handle_reply,
    "abort": handle_abort,
    "status": handle_status,
    "help": lambda _: handle_help(),
}

def main() -> None:
    if len(sys.argv) < 2:
        raise SystemExit("usage: run_codex.py <cmd.json>")
    command_path = sys.argv[1]
    command = json.load(open(command_path))
    action = command.get("action", "help")
    args = command.get("args", {})

    handler = HANDLERS.get(action, handle_help)
    body = handler(args)
    print(json.dumps({"body": body}))

if __name__ == "__main__":
    main()
