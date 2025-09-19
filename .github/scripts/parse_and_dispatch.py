import json
import os
import re
import sys

def get_arg(name: str) -> str:
    try:
        idx = sys.argv.index(name)
    except ValueError:
        raise SystemExit(f"missing required argument: {name}")
    try:
        return sys.argv[idx + 1]
    except IndexError:
        raise SystemExit(f"missing value for argument: {name}")

def main() -> None:
    event_path = get_arg('--event')
    issue_value = get_arg('--issue')
    event = json.load(open(event_path))
    issue_num = int(issue_value)
    body_source = event.get('comment', {}) or event.get('issue', {})
    text = body_source.get('body', '')

    match = re.search(r'@codex\s+(.*)', text, re.S)
    cmd = (match.group(1).strip() if match else '').lower()

    payload = {"issue": issue_num, "action": "", "args": {}}

    if cmd.startswith('spawn'):
        prompt_match = re.search(r'spawn\s+"([^"]+)"', text, re.S)
        cwd_match = re.search(r'\bcwd=([^\s]+)', text)
        sandbox_match = re.search(r'\bsandbox=([^\s]+)', text)
        approval_match = re.search(r'\bapproval=([^\s]+)', text)

        payload["action"] = "spawn"
        payload["args"] = {
            "prompt": prompt_match.group(1) if prompt_match else "",
            "cwd": cwd_match.group(1) if cwd_match else ".",
            "sandbox": sandbox_match.group(1) if sandbox_match else "workspace-write",
            "approval": approval_match.group(1) if approval_match else "on-request",
        }
    elif cmd.startswith('reply'):
        reply_match = re.search(r'reply\s+cid=([^\s]+)\s+"([^"]+)"', text, re.S)
        payload["action"] = "reply"
        payload["args"] = {
            "cid": reply_match.group(1),
            "message": reply_match.group(2),
        } if reply_match else {}
    elif cmd.startswith('abort'):
        abort_match = re.search(r'abort\s+cid=([^\s]+)', text)
        payload["action"] = "abort"
        payload["args"] = {"cid": abort_match.group(1)} if abort_match else {}
    elif cmd.startswith('status'):
        status_match = re.search(r'status\s+cid=([^\s]+)', text)
        payload["action"] = "status"
        payload["args"] = {"cid": status_match.group(1)} if status_match else {}
    else:
        payload["action"] = "help"

    print(json.dumps(payload))

if __name__ == '__main__':
    main()
