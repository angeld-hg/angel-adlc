#!/usr/bin/env bash
source "$(dirname "$0")/../helpers.sh"

write_payload() { # <file_path> [agent_type] [tool_name]
  jq -nc --arg p "$1" --arg t "${2:-}" --arg tool "${3:-Write}" \
    '{hook_event_name: "PreToolUse", tool_name: $tool, tool_input: {file_path: $p, content: "## Review\nVERDICT: APPROVE"}}
     + (if $t == "" then {} else {agent_id: "a1", agent_type: $t} end)'
}
guard() { run_hook reviewer-write-guard.sh "$(write_payload "$@")"; }

deny='.hookSpecificOutput.permissionDecision == "deny"'

new_project; p="$CLAUDE_PROJECT_DIR"
with_feature "$p" add-export review
reviews="$p/.adlc/add-export/reviews"

# --- the four report writers
for a in code-reviewer drift-checker spec-reviewer verifier; do
  assert_empty "$a may write its report under .adlc/<slug>/reviews/" \
    "$(guard "$reviews/report.md" "angel:$a")"
  assert_json "$a may not write source" "$(guard "$p/src/app.ts" "angel:$a")" "$deny"
done

assert_empty "reviews/ doesn't have to exist yet" "$(guard "$reviews/code-review-2.md" angel:code-reviewer)"
assert_empty "relative report paths are resolved against the project" \
  "$(guard ".adlc/add-export/reviews/diff-drift.md" angel:drift-checker)"
assert_empty "un-namespaced agent names are handled too" "$(guard "$reviews/x.md" code-reviewer)"

assert_contains "deny reason names the allowed location" \
  "$(guard "$p/src/app.ts" angel:code-reviewer)" ".adlc/<slug>/reviews/"
assert_json "other files in the feature folder are denied (spec.md)" \
  "$(guard "$p/.adlc/add-export/spec.md" angel:spec-reviewer)" "$deny"
assert_json "state.md is denied" "$(guard "$p/.adlc/add-export/state.md" angel:code-reviewer)" "$deny"
assert_json "a report must be markdown" "$(guard "$reviews/report.sh" angel:code-reviewer)" "$deny"
assert_json "no nested folders under reviews/" "$(guard "$reviews/sub/report.md" angel:code-reviewer)" "$deny"
assert_json "repo-wide .adlc/verification.md is denied" \
  "$(guard "$p/.adlc/verification.md" angel:verifier)" "$deny"
assert_json "a feature folder that doesn't exist is denied (no opting a repo in by accident)" \
  "$(guard "$p/.adlc/other-feature/reviews/r.md" angel:code-reviewer)" "$deny"
assert_json "'..' segments can't climb out of reviews/" \
  "$(guard "$p/.adlc/add-export/reviews/nope/../../../src/app.md" angel:code-reviewer)" "$deny"
assert_json "files outside the project are denied" "$(guard "$HOME/notes.md" angel:code-reviewer)" "$deny"
assert_json "Edit is guarded as well as Write" \
  "$(guard "$p/src/app.ts" angel:code-reviewer Edit)" "$deny"
nb="$(jq -nc --arg p "$p/nb.ipynb" '{tool_name: "NotebookEdit", agent_id: "a1", agent_type: "angel:verifier", tool_input: {notebook_path: $p}}')"
assert_json "NotebookEdit uses notebook_path and is guarded too" "$(run_hook reviewer-write-guard.sh "$nb")" "$deny"

# --- verifier's throwaway scripts
assert_empty "verifier may write throwaway scripts under .adlc/<slug>/evidence/" \
  "$(guard "$p/.adlc/add-export/evidence/check.sh" angel:verifier)"
assert_json "code-reviewer may not write under evidence/" \
  "$(guard "$p/.adlc/add-export/evidence/check.sh" angel:code-reviewer)" "$deny"
assert_empty "verifier may write the e2e artifact in subfolders (rerun script, results)" \
  "$(guard "$p/.adlc/add-export/evidence/e2e/2026-09-24/rerun.sh" angel:verifier)"
assert_empty "verifier may save screenshots for the PR under evidence/screenshots/" \
  "$(guard "$p/.adlc/add-export/evidence/screenshots/export-button.png" angel:verifier)"
assert_json "'..' still can't climb out of evidence/" \
  "$(guard "$p/.adlc/add-export/evidence/../../../src/app.ts" angel:verifier)" "$deny"
assert_json "reviews/ stays flat: no subfolders" \
  "$(guard "$p/.adlc/add-export/reviews/sub/r.md" angel:code-reviewer)" "$deny"

# --- everyone else is not this hook's business
assert_empty "main session (no agent_type) is left to elephant-guard" "$(guard "$p/src/app.ts")"
assert_empty "implementer may write source" "$(guard "$p/src/app.ts" angel:implementer)"
assert_empty "planner is not restricted by this hook" "$(guard "$p/.adlc/add-export/plan.md" angel:planner)"
assert_empty "unrelated agents are ignored" "$(guard "$p/src/app.ts" general-purpose)"
assert_json "ANGEL_ALLOW_MAIN_EDITS=1 does not unlock reviewer writes" \
  "$(ANGEL_ALLOW_MAIN_EDITS=1 guard "$p/src/app.ts" angel:code-reviewer)" "$deny"

# --- repos without .adlc/
new_project; q="$CLAUDE_PROJECT_DIR"
assert_json "no .adlc/: reviewer writes are still denied (the agents are read-only everywhere)" \
  "$(guard "$q/src/app.ts" angel:code-reviewer)" "$deny"
assert_json "no .adlc/: a reviewer can't create .adlc/ to write a report" \
  "$(guard "$q/.adlc/x/reviews/r.md" angel:code-reviewer)" "$deny"

rm -rf "$p" "$q"
finish
