#!/usr/bin/env bash
source "$(dirname "$0")/../helpers.sh"

bash_payload() { jq -nc --arg c "$1" --arg a "${2:-}" \
  '{hook_event_name: "PreToolUse", tool_name: "Bash", tool_input: {command: $c}} + (if $a == "" then {} else {agent_id: $a} end)'; }
deny='.hookSpecificOutput.permissionDecision == "deny"'
pr='gh pr create --title "x" --body-file .adlc/add-export/pr-body.md'

new_project; p="$CLAUDE_PROJECT_DIR"
assert_empty "no active feature: gh pr create is not the gate's business" "$(run_hook ship-gate.sh "$(bash_payload "$pr")")"

with_feature "$p" add-export ship
assert_empty "other commands pass" "$(run_hook ship-gate.sh "$(bash_payload 'gh pr view 12')")"
assert_empty "mentioning the command in a string isn't creating a PR" "$(run_hook ship-gate.sh "$(bash_payload 'echo run-gh-pr-create-later')")"

out="$(run_hook ship-gate.sh "$(bash_payload "$pr")")"
assert_json "no verification report: PR creation denied" "$out" "$deny"
assert_contains "denial points at /angel:verify" "$out" "/angel:verify"
assert_json "chained commands are caught too" "$(run_hook ship-gate.sh "$(bash_payload "git push -u origin HEAD && $pr")")" "$deny"
assert_json "goldfish are gated as well" "$(run_hook ship-gate.sh "$(bash_payload "$pr" a1)")" "$deny"

mkdir -p "$p/.adlc/add-export/reviews"
printf '## Evidence\n...\nVERDICT: PARTIAL\n' >"$p/.adlc/add-export/reviews/verification.md"
assert_json "PARTIAL verification: denied" "$(run_hook ship-gate.sh "$(bash_payload "$pr")")" "$deny"

printf '## Evidence\n...\n**VERDICT:** VERIFIED\n' >"$p/.adlc/add-export/reviews/verification.md"
assert_empty "VERIFIED: allowed" "$(run_hook ship-gate.sh "$(bash_payload "$pr")")"

printf 'VERDICT: FAILED\n' >"$p/.adlc/add-export/reviews/verification.md"
sed -i.bak 's/^phase: ship/phase: ship\nverification: waived/' "$p/.adlc/add-export/state.md"
assert_empty "user waiver in state.md: allowed" "$(run_hook ship-gate.sh "$(bash_payload "$pr")")"

rm -rf "$p"
finish
