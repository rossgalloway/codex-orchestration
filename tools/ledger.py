#!/usr/bin/env python3
import argparse
import json
import os
import time

def now() -> str:
    return time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())

def write_event(args: argparse.Namespace) -> None:
    event = {
        "v": 1,
        "ts": now(),
        "type": args.type,
        "cid": args.cid,
        "task": args.task,
        "agent": args.agent,
        "branch": args.branch,
        "worktree": args.worktree,
        "cwd": args.cwd,
        "sha": args.sha,
        "msg": args.msg,
    }
    if args.tags:
        event["tags"] = args.tags
    if args.data:
        event["data"] = json.loads(args.data)

    os.makedirs(os.path.dirname(args.path), exist_ok=True)
    filtered = {k: v for k, v in event.items() if v not in (None, "")}
    line = json.dumps(filtered)
    with open(args.path, "a", encoding="utf-8") as handle:
        handle.write(line + "\n")
        handle.flush()

def status(args: argparse.Namespace) -> None:
    latest = {}
    try:
        with open(args.path, encoding="utf-8") as handle:
            for line in handle:
                entry = json.loads(line)
                key = entry.get("cid") or entry.get("task")
                if key:
                    latest[key] = entry
    except FileNotFoundError:
        pass
    output = [latest[key] for key in sorted(latest)]
    print(json.dumps(output, indent=2))

def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser()
    sub = parser.add_subparsers(dest="cmd", required=True)

    write_cmd = sub.add_parser("write")
    write_cmd.add_argument("--path", default="agents/ledger.jsonl")
    write_cmd.add_argument("--type", required=True)
    write_cmd.add_argument("--cid")
    write_cmd.add_argument("--task")
    write_cmd.add_argument("--agent")
    write_cmd.add_argument("--branch")
    write_cmd.add_argument("--worktree")
    write_cmd.add_argument("--cwd")
    write_cmd.add_argument("--sha")
    write_cmd.add_argument("--msg")
    write_cmd.add_argument("--tags", nargs="*")
    write_cmd.add_argument("--data")
    write_cmd.set_defaults(func=write_event)

    status_cmd = sub.add_parser("status")
    status_cmd.add_argument("--path", default="agents/ledger.jsonl")
    status_cmd.set_defaults(func=status)

    return parser

def main() -> None:
    parser = build_parser()
    arguments = parser.parse_args()
    arguments.func(arguments)

if __name__ == "__main__":
    main()
