#!/usr/bin/env bash
source "$(dirname "$0")/../helpers.sh"

payload='{"hook_event_name":"SessionStart","source":"startup"}'
ctx='.hookSpecificOutput.additionalContext'

new_project; p="$CLAUDE_PROJECT_DIR"
assert_empty "repo without .adlc/: silent" "$(run_hook session-start.sh "$payload")"

mkdir -p "$p/.adlc"
out="$(run_hook session-start.sh "$payload")"
assert_json "opted-in repo: injects the elephant primer" "$out" "$ctx | contains(\"You are the **elephant**\")"
assert_json "no active feature: suggests /angel:start" "$out" "$ctx | contains(\"No active feature\")"

with_feature "$p" add-export plan
printf '# Spec\n' >"$p/.adlc/add-export/spec.md"
out="$(run_hook session-start.sh "$payload")"
assert_json "event name is SessionStart" "$out" '.hookSpecificOutput.hookEventName == "SessionStart"'
assert_json "active feature slug is shown" "$out" "$ctx | contains(\"add-export\")"
assert_json "phase comes from state.md frontmatter" "$out" "$ctx | contains(\"Phase: plan\")"
assert_json "next step comes from state.md frontmatter" "$out" "$ctx | contains(\"run /angel:plan\")"
assert_json "last decision is the newest log line" "$out" "$ctx | contains(\"spec approved by user\")"
assert_json "artifacts are listed" "$out" "$ctx | contains(\"spec.md\")"

assert_json "no verification profile: suggests /angel:discover" "$out" "$ctx | contains(\"/angel:discover before building\")"

printf '# Verification profile\n' >"$p/.adlc/verification.md"
mkdir -p "$p/.adlc/rules"
printf -- '---\nid: no-direct-fetch\npattern: fetch\\(\n---\n' >"$p/.adlc/rules/no-direct-fetch.md"
printf '## D1: flag?\n- Status: pending\n## D2: excel?\n- Status: decided\n' >"$p/.adlc/add-export/decisions.md"
out="$(run_hook session-start.sh "$payload")"
assert_json "verification profile is pointed at" "$out" "$ctx | contains(\"Verification profile: .adlc/verification.md\")"
assert_json "banned pattern ids are listed" "$out" "$ctx | contains(\"no-direct-fetch\")"
assert_json "pending decisions are counted and flagged" "$out" "$ctx | contains(\"Pending user decisions: 1\")"

printf 'missing-slug\n' >"$p/.adlc/ACTIVE"
out="$(run_hook session-start.sh "$payload")"
assert_json "ACTIVE pointing at a missing folder falls back gracefully" "$out" "$ctx | contains(\"No active feature\")"

rm -rf "$p"
finish
