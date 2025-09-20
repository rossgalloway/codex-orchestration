#!/usr/bin/env bash
set -euo pipefail
branch="${1:-codex-ledger}"
interval="${2:-15}"
repo_root="$(git rev-parse --show-toplevel)"
cd "$repo_root"
git fetch origin "$branch" || true
git switch "$branch" 2>/dev/null || git switch -c "$branch"
git pull --rebase origin "$branch" || true
while true; do
  if ! git diff --quiet -- agents/ledger.jsonl; then
    ts="$(date -Iseconds)"
    git add agents/ledger.jsonl
    git commit -m "chore(ledger): $ts" || true
    tries=0
    while :; do
      git pull --rebase origin "$branch" || true
      if git push -u origin "$branch"; then
        break
      fi
      tries=$((tries + 1))
      [ "$tries" -gt 5 ] && break
      sleep $((tries * 2))
    done
  fi
  sleep "$interval"
done
