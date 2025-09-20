I read through each file. Below is a tight review with **surgical diffs** you can paste in as patches. They fix the issues you’ve been hitting (Inspector “method required”, ENOENT on `codex`, brittle pushes, silent failures), and bring the GitHub workflow in line with your MCP-client path.

---

# High-impact changes (apply these)

### 1) `.github/scripts/run_codex.py`

Problem: still uses `codex mcp call …` (your CLI doesn’t support `call`). Fix by routing through `tools/mcp_call.sh` (same as your local spawn/reply).

```diff
*** a/.github/scripts/run_codex.py
--- b/.github/scripts/run_codex.py
@@
-import json
-import subprocess
-import sys
+import json, subprocess, sys, os
@@
-def run_command(invocation, **kwargs):
-    return subprocess.run(invocation, text=True, capture_output=True, **kwargs)
+LEDGER_HOME = os.environ.get("LEDGER_HOME", os.path.expanduser("~/code/codex-orchestration"))
+MCP_CALL = os.path.join(LEDGER_HOME, "tools", "mcp_call.sh")
+CODEX_BIN = os.environ.get("CODEX_BIN") or subprocess.run(["bash","-lc","command -v codex"], text=True, capture_output=True).stdout.strip()
+
+def run_command(invocation, **kwargs):
+    return subprocess.run(invocation, text=True, capture_output=True, **kwargs)
@@
-def codex_call(payload, tool):
-    process = run_command(["codex", "mcp", "call", tool], input=json.dumps(payload))
-    if process.returncode != 0 and not process.stdout:
-        return process.stderr
-    return process.stdout or process.stderr
+def codex_call(payload, tool):
+    # Route through mcp_call.sh (Inspector CLI)
+    env = os.environ.copy()
+    if CODEX_BIN:
+        cmd = [MCP_CALL, CODEX_BIN, tool, json.dumps(payload)]
+    else:
+        cmd = [MCP_CALL, "codex", tool, json.dumps(payload)]
+    p = run_command(cmd, env=env)
+    return p.stdout or p.stderr
```

### 2) `.github/workflows/codex-bridge.yml`

Problem: if the comment author isn’t you, anyone can trigger runs. Also, always post a reply (even on failure), and ensure `jq` is present.

```diff
*** a/.github/workflows/codex-bridge.yml
--- b/.github/workflows/codex-bridge.yml
@@
 jobs:
   handle:
@@
     steps:
+      - name: Ensure jq present (self-hosted)
+        run: |
+          command -v jq >/dev/null || (echo "jq missing on runner" && exit 1)
       - uses: actions/checkout@v4
+      - name: Allow only owner
+        run: |
+          WHO="${{ github.event.comment.user.login || github.event.issue.user.login }}"
+          ALLOWED="rossgalloway"
+          if [ "$WHO" != "$ALLOWED" ]; then
+            echo "Not allowed: $WHO"
+            echo '{"body":"⛔ Not allowed for user '"$WHO"'."}' > result.json
+            exit 0
+          fi
       - name: Parse command
         id: parse
@@
-      - name: Run Codex command
+      - name: Run Codex command (Inspector path)
         id: codex
         run: |
           python3 .github/scripts/run_codex.py cmd.json > result.json || echo "{}" > result.json
-      - name: Post reply
+      - name: Post reply (always)
         env: { GH_TOKEN: ${{ secrets.GITHUB_TOKEN }} }
-        run: |
-          body=$(jq -r '.body // "Codex ran with no output."' result.json)
-          gh issue comment ${{ github.event.issue.number || github.event.comment.issue_url##*/ }} --body "$body"
+        if: always()
+        run: |
+          body=$(jq -r '.body // "Codex ran with no output."' result.json 2>/dev/null || echo "workflow failed without body")
+          gh issue comment ${{ github.event.issue.number || github.event.comment.issue_url##*/ }} --body "$body"
```

### 3) `tools/mcp_call.sh`

This is already close. Let’s make the **absolute path** requirement strict and keep the `tools/call` method explicitly (you’ve got it; we’ll just tighten resolution).

```diff
*** a/tools/mcp_call.sh
--- b/tools/mcp_call.sh
@@
-if [[ "$server_cmd" != /* ]]; then
-  if [[ -n "${CODEX_BIN:-}" ]]; then
-    server_cmd="$CODEX_BIN"
-  else
-    server_cmd="$(command -v "$server_cmd" 2>/dev/null || true)"
-  fi
-fi
-if [[ -z "${server_cmd:-}" || ! -x "$server_cmd" ]]; then
-  echo "Cannot find executable for codex server: '$server_cmd'" >&2
-  exit 1
-fi
+if [[ "$server_cmd" != /* ]]; then
+  server_cmd="${CODEX_BIN:-$(command -v "$server_cmd" 2>/dev/null || true)}"
+fi
+# Canonicalize if possible
+server_cmd="$(readlink -f "$server_cmd" 2>/dev/null || echo "$server_cmd")"
+if [[ -z "${server_cmd:-}" || ! -x "$server_cmd" ]]; then
+  echo "Cannot exec codex server: '$server_cmd'" >&2
+  exit 1
+fi
@@
-npx --yes @modelcontextprotocol/inspector@latest --cli \
+npx --yes @modelcontextprotocol/inspector@latest --cli \
   --server.command="$server_cmd" \
   --server.args="mcp" \
   --server.args="serve" \
   --method="tools/call" \
   --call.tool="$tool_name" \
   --call.input="$payload"
```

### 4) `tools/codex_spawn.sh`

Add better failure logging (to the ledger) and sanitize the tmux session name.

```diff
*** a/tools/codex_spawn.sh
--- b/tools/codex_spawn.sh
@@
-CODEX_BIN="${CODEX_BIN:-$(command -v codex 2>/dev/null || true)}"
-[[ -x "$CODEX_BIN" ]] || { echo "codex not found; set CODEX_BIN" >&2; exit 1; }
+CODEX_BIN="${CODEX_BIN:-$(command -v codex 2>/dev/null || true)}"
+CODEX_BIN="$(readlink -f "$CODEX_BIN" 2>/dev/null || echo "$CODEX_BIN")"
+[[ -x "$CODEX_BIN" ]] || { echo "codex not found; set CODEX_BIN to absolute path" >&2; exit 1; }
@@
-resp="$("$LEDGER_HOME/tools/mcp_call.sh" "$CODEX_BIN" codex "$payload")"
+resp="$("$LEDGER_HOME/tools/mcp_call.sh" "$CODEX_BIN" codex "$payload" 2>&1 || true)"
@@
-[ -n "$cid" ] || { echo "Failed to get conversationId. Raw output follows:"; echo "$resp"; exit 2; }
+[ -n "$cid" ] || {
+  echo "Failed to get conversationId" >&2
+  python3 "$LEDGER_HOME/tools/ledger.py" write \
+    --type error --agent coordinator --msg "spawn_failed" \
+    --data "$(python3 - <<'P'
+import json,sys; print(json.dumps({"raw":sys.stdin.read()}))
+P
+<<< "$resp")"
+  exit 2
+}
@@
-tmux new-session -d -s "codex-$cid" -c "$cwd" bash -lc "
+session=\"codex-${cid//[^A-Za-z0-9._-]/_}\"
+tmux new-session -d -s \"$session\" -c \"$cwd\" bash -lc "
   printf '{\"conversationId\":\"%s\",\"prompt\":\"%s\"}' '$cid' '$msg' \
   | $LEDGER_HOME/tools/mcp_call.sh \"$CODEX_BIN\" codex-reply /dev/stdin
 "
```

### 5) `tools/codex_reply.sh`

Mirror absolute-path resolution and ledger logging on failure.

```diff
*** a/tools/codex_reply.sh
--- b/tools/codex_reply.sh
@@
-LEDGER_HOME="${LEDGER_HOME:-$HOME/code/codex-orchestration}"
-CODEX_BIN="${CODEX_BIN:-$(command -v codex 2>/dev/null || true)}"
-[[ -x "$CODEX_BIN" ]] || { echo "codex not found; set CODEX_BIN" >&2; exit 1; }
+LEDGER_HOME="${LEDGER_HOME:-$HOME/code/codex-orchestration}"
+CODEX_BIN="${CODEX_BIN:-$(command -v codex 2>/dev/null || true)}"
+CODEX_BIN="$(readlink -f "$CODEX_BIN" 2>/dev/null || echo "$CODEX_BIN")"
+[[ -x "$CODEX_BIN" ]] || { echo "codex not found; set CODEX_BIN to absolute path" >&2; exit 1; }
@@
-printf '%s' "$payload" | "$LEDGER_HOME/tools/mcp_call.sh" "$CODEX_BIN" codex-reply /dev/stdin
+out="$(printf '%s' "$payload" | "$LEDGER_HOME/tools/mcp_call.sh" "$CODEX_BIN" codex-reply /dev/stdin 2>&1 || true)"
+if ! grep -q '"content"' <<<"$out"; then
+  python3 "$LEDGER_HOME/tools/ledger.py" write --type error --agent coordinator --cid "$cid" --msg "reply_failed" --data "$(python3 - <<'P'
+import json,sys; print(json.dumps({"raw":sys.stdin.read()}))
+P
+<<< "$out")"
+fi
 python3 "$LEDGER_HOME/tools/ledger.py" write --type reply --agent coordinator --cid "$cid" --msg "$message"
```

### 6) `tools/auto_push_ledger.sh`

Make pushing resilient to races, and create the branch if it doesn’t exist.

```diff
*** a/tools/auto_push_ledger.sh
--- b/tools/auto_push_ledger.sh
@@
-repo_root="$(git rev-parse --show-toplevel)"
-cd "$repo_root"
-git switch -C "$branch" || git switch "$branch"
-git pull --rebase origin "$branch" || true
+repo_root="$(git rev-parse --show-toplevel)"
+cd "$repo_root"
+git fetch origin "$branch" || true
+git switch "$branch" 2>/dev/null || git switch -c "$branch"
+git pull --rebase origin "$branch" || true
@@
-    git pull --rebase origin "$branch" || true
-    git push -u origin "$branch" || true
+    tries=0
+    while :; do
+      git pull --rebase origin "$branch" || true
+      if git push -u origin "$branch"; then break; fi
+      tries=$((tries+1)); sleep $((tries*2)); [ $tries -gt 5 ] && break
+    done
```

### 7) `tools/ledger.py`

Flush quickly to avoid partial writes on abrupt exits.

```diff
*** a/tools/ledger.py
--- b/tools/ledger.py
@@
-    with open(args.path, "a", encoding="utf-8") as handle:
-        handle.write(json.dumps(filtered) + "\n")
+    line = json.dumps(filtered)
+    with open(args.path, "a", encoding="utf-8") as handle:
+        handle.write(line + "\n")
+        handle.flush()
```

---

# Quick validation (run these)

From a project repo:

```bash
# 0) ensure CODEX_BIN resolves to an absolute, executable file
echo "CODEX_BIN=${CODEX_BIN:-$(command -v codex)}"
readlink -f "${CODEX_BIN:-$(command -v codex)}" || true

# 1) direct inspector call (no wrappers) – should print JSON with conversationId or error payload
$LEDGER_HOME/tools/mcp_call.sh "${CODEX_BIN:-codex}" codex \
'{"prompt":"ping","sandbox":"workspace-write","approval-policy":"on-request","cwd":"'"$(pwd)"'","include-plan-tool":true}'

# 2) spawn (non-blocking) – should echo a non-empty CID and append a spawn event
CID=$(codex_spawn.sh "Say hello and write one progress entry via ledger.py." "$(pwd)"); echo "CID=$CID"

# 3) reply – should append a reply event and not log an error
codex_reply.sh "$CID" "Please append a progress entry and then stop."

# 4) ledger check – local and pushed
tail -n 5 "$LEDGER_HOME/agents/ledger.jsonl"
git -C "$LEDGER_HOME" fetch origin codex-ledger
git -C "$LEDGER_HOME" log -1 -- agents/ledger.jsonl
```
