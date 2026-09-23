#!/usr/bin/env bash
source "$(dirname "$0")/../helpers.sh"

write_payload() { # <file_path> [agent_id]
  jq -nc --arg p "$1" --arg a "${2:-}" \
    '{hook_event_name: "PreToolUse", tool_name: "Write", tool_input: {file_path: $p, content: "x"}}
     + (if $a == "" then {} else {agent_id: $a, agent_type: "angel:implementer"} end)'
}

deny='.hookSpecificOutput.permissionDecision == "deny"'

new_project; p="$CLAUDE_PROJECT_DIR"
assert_empty "repo without .adlc/: main session may edit source" \
  "$(run_hook elephant-guard.sh "$(write_payload "$p/src/app.ts")")"

mkdir -p "$p/.adlc"
assert_json "opted-in repo: main session editing source is denied" \
  "$(run_hook elephant-guard.sh "$(write_payload "$p/src/app.ts")")" "$deny"

assert_contains "deny reason points at the implementer" \
  "$(run_hook elephant-guard.sh "$(write_payload "$p/src/app.ts")")" "implementer"

assert_json "relative paths are resolved against the project" \
  "$(run_hook elephant-guard.sh "$(write_payload "src/app.ts")")" "$deny"

assert_empty "subagent (agent_id present) may edit source" \
  "$(run_hook elephant-guard.sh "$(write_payload "$p/src/app.ts" a123)")"

assert_empty "main session may write under .adlc/" \
  "$(run_hook elephant-guard.sh "$(write_payload "$p/.adlc/feat/state.md")")"

assert_empty "files outside the project are not the guard's business" \
  "$(run_hook elephant-guard.sh "$(write_payload "$HOME/.claude/plans/some-plan.md")")"

printf '# docs are fine\ndocs/*\n*.md\n' >"$p/.adlc/allow"
assert_empty ".adlc/allow glob lets matching paths through" \
  "$(run_hook elephant-guard.sh "$(write_payload "$p/docs/guide.txt")")"
assert_empty ".adlc/allow top-level *.md matches" \
  "$(run_hook elephant-guard.sh "$(write_payload "$p/README.md")")"
assert_json ".adlc/allow doesn't open up everything" \
  "$(run_hook elephant-guard.sh "$(write_payload "$p/src/app.ts")")" "$deny"

assert_empty "ANGEL_ALLOW_MAIN_EDITS=1 disables the guard" \
  "$(ANGEL_ALLOW_MAIN_EDITS=1 run_hook elephant-guard.sh "$(write_payload "$p/src/app.ts")")"

nb="$(jq -nc --arg p "$p/nb.ipynb" '{tool_name: "NotebookEdit", tool_input: {notebook_path: $p}}')"
assert_json "NotebookEdit uses notebook_path and is guarded too" \
  "$(run_hook elephant-guard.sh "$nb")" "$deny"

rm -rf "$p"
finish
