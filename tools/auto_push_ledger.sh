#!/usr/bin/env bash
set -euo pipefail
branch="${1:-codex-ledger}"
interval="${2:-15}"
repo_root="$(git rev-parse --show-toplevel)"
cd "$repo_root"
git switch -C "$branch" || git switch "$branch"
git pull --rebase origin "$branch" || true
while true; do
  if ! git diff --quiet -- agents/ledger.jsonl; then
    ts="$(date -Iseconds)"
    git add agents/ledger.jsonl
    git commit -m "chore(ledger): $ts" || true
    git pull --rebase origin "$branch" || true
    git push -u origin "$branch" || true
  fi
  sleep "$interval"
done
