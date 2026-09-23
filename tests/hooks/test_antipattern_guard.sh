#!/usr/bin/env bash
source "$(dirname "$0")/../helpers.sh"

write() { jq -nc --arg p "$1" --arg c "$2" '{tool_name: "Write", tool_input: {file_path: $p, content: $c}, agent_id: "a1"}'; }
edit() { jq -nc --arg p "$1" --arg o "$2" --arg n "$3" '{tool_name: "Edit", tool_input: {file_path: $p, old_string: $o, new_string: $n}}'; }
deny='.hookSpecificOutput.permissionDecision == "deny"'
ask='.hookSpecificOutput.permissionDecision == "ask"'

new_project; p="$CLAUDE_PROJECT_DIR"
assert_empty "no rules: everything passes" "$(run_hook antipattern-guard.sh "$(write "$p/src/a.ts" 'fetch("/x")')")"

mkdir -p "$p/.adlc/rules" "$p/src/lib"
cat >"$p/.adlc/rules/no-direct-fetch.md" <<'EOF'
---
id: no-direct-fetch
pattern: \bfetch\(    # raw fetch calls
paths: src/**/*.ts, src/*.tsx
exclude: src/lib/http.ts
---
# No direct fetch

## Why
Raw fetch skipped auth headers and retries, which caused the 2026-08 outage.

## Instead
Use `http.get` / `http.post` from src/lib/http.ts.
EOF

out="$(run_hook antipattern-guard.sh "$(write "$p/src/a.ts" 'const r = await fetch("/x")')")"
assert_json "a goldfish writing a banned pattern is denied" "$out" "$deny"
assert_contains "the reason names the rule" "$out" "no-direct-fetch"
assert_contains "the reason explains why" "$out" "outage"
assert_contains "the reason says what to do instead" "$out" "http.get"

# Regression: `src/**` used to be pathname-expanded against real files in the cwd
# (hooks run from the repo root), turning the glob into a list of existing files.
printf 'x\n' >"$p/src/existing.ts"
printf -- '---\nid: no-banned-call\npattern: banned_call\\(\npaths: src/**\n---\n## Why\nx\n\n## Instead\ny\n' \
  >"$p/.adlc/rules/no-banned-call.md"
assert_json "globs aren't expanded against real files in the cwd (regression)" \
  "$(run_hook antipattern-guard.sh "$(write "$p/src/new-file.ts" 'banned_call(1)')")" "$deny"
rm "$p/.adlc/rules/no-banned-call.md" "$p/src/existing.ts"

assert_json "** globs match nested paths" \
  "$(run_hook antipattern-guard.sh "$(write "$p/src/deep/er/b.ts" 'fetch(u)')")" "$deny"
assert_empty "clean code passes" "$(run_hook antipattern-guard.sh "$(write "$p/src/a.ts" 'await http.get("/x")')")"
assert_empty "word boundary: prefetch( isn't fetch(" "$(run_hook antipattern-guard.sh "$(write "$p/src/a.ts" 'prefetch(x)')")"
assert_empty "excluded path passes" "$(run_hook antipattern-guard.sh "$(write "$p/src/lib/http.ts" 'return fetch(u)')")"
assert_empty "paths outside the rule's globs pass" "$(run_hook antipattern-guard.sh "$(write "$p/scripts/x.js" 'fetch(u)')")"
assert_empty "rule files under .adlc/ are never checked" \
  "$(run_hook antipattern-guard.sh "$(write "$p/.adlc/rules/copy.md" 'pattern: fetch(')")"

assert_json "the elephant (no agent_id) is gated too, via Edit" \
  "$(run_hook antipattern-guard.sh "$(edit "$p/src/a.ts" 'http.get(u)' 'fetch(u)')")" "$deny"
assert_empty "editing near an existing violation without adding one passes" \
  "$(run_hook antipattern-guard.sh "$(edit "$p/src/a.ts" $'const a = 1\nfetch(u)' $'const a = 2\nfetch(u)')")"

printf 'const old = fetch(u)\n' >"$p/src/legacy.ts"
assert_empty "rewriting a legacy file without adding occurrences passes" \
  "$(run_hook antipattern-guard.sh "$(write "$p/src/legacy.ts" $'// touched\nconst old = fetch(u)')")"
assert_json "rewriting a legacy file and adding a second occurrence is denied" \
  "$(run_hook antipattern-guard.sh "$(write "$p/src/legacy.ts" $'const old = fetch(u)\nconst neu = fetch(v)')")" "$deny"

multi="$(jq -nc --arg p "$p/src/a.ts" '{tool_name: "MultiEdit", tool_input: {file_path: $p, edits: [{old_string: "a", new_string: "b"}, {old_string: "c", new_string: "fetch(z)"}]}}')"
assert_json "MultiEdit edits are checked" "$(run_hook antipattern-guard.sh "$multi")" "$deny"

cat >"$p/.adlc/rules/no-console-log.md" <<'EOF'
---
id: no-console-log
pattern: 'console\.log\('
action: ask
---
## Why
Noise in production logs.

## Instead
Use the logger from src/lib/log.ts.
EOF
assert_json "action: ask asks instead of denying" \
  "$(run_hook antipattern-guard.sh "$(write "$p/tools/x.js" 'console.log(1)')")" "$ask"
assert_json "block wins over ask when both match" \
  "$(run_hook antipattern-guard.sh "$(write "$p/src/a.ts" $'console.log(1)\nfetch(u)')")" "$deny"

rm -rf "$p"
finish
