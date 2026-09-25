#!/usr/bin/env bash
source "$(dirname "$0")/../helpers.sh"

stop_payload() { # <agent_type> [last_message] [stop_hook_active]
  jq -nc --arg t "$1" --arg m "${2:-done}" --argjson s "${3:-false}" \
    '{hook_event_name: "SubagentStop", agent_type: $t, agent_id: "a1", last_assistant_message: $m, stop_hook_active: $s}'
}
gate() { run_hook goldfish-gate.sh "$(stop_payload "$@")"; }

block='.decision == "block"'
good_review=$'## Findings\n- ...\n\n## Decisions needed\nNone.\n\nVERDICT: APPROVE'

new_project; p="$CLAUDE_PROJECT_DIR"
assert_empty "no active feature: spec-writer isn't checked" "$(gate angel:spec-writer)"
assert_json "no .adlc/: reviewer reports are still checked (check-pr/doc-audit gate on them)" \
  "$(gate angel:code-reviewer 'lgtm')" "$block"

# --- writers
with_feature "$p" add-export spec
assert_json "spec-writer without spec.md is sent back" "$(gate angel:spec-writer)" "$block"

printf '# Spec\n\n## In plain words\n- You can export a report as CSV.\n\n## Problem\nx\n' >"$p/.adlc/add-export/spec.md"
assert_contains "spec.md missing acceptance criteria is sent back with the reason" \
  "$(gate angel:spec-writer)" "Acceptance Criteria"

printf '\n## Acceptance Criteria\n- [ ] csv-download: clicking Export downloads a CSV\n' >>"$p/.adlc/add-export/spec.md"
assert_empty "complete spec.md lets spec-writer finish" "$(gate angel:spec-writer)"

assert_json "planner without plan.md is sent back" "$(gate angel:planner)" "$block"
printf '# Plan\n\n## In plain words\nAdd an Export button.\n\n## Slices\n### export-button\n' >"$p/.adlc/add-export/plan.md"
assert_empty "plan.md with slices lets planner finish" "$(gate angel:planner)"

assert_empty "stop_hook_active prevents a second block (no loops)" "$(gate angel:planner done true)"
rm "$p/.adlc/add-export/plan.md"
assert_empty "stop_hook_active wins even when the artifact is still missing" "$(gate angel:planner done true)"

assert_json "repo-scout without .adlc/verification.md is sent back" "$(gate angel:repo-scout)" "$block"
printf '# Verification profile\n\n## Evidence recipes\n1. just test\n' >"$p/.adlc/verification.md"
assert_empty "repo-scout with a profile finishes" "$(gate angel:repo-scout)"

# --- reviewers
assert_json "code-reviewer without VERDICT or decisions is sent back" \
  "$(gate angel:code-reviewer 'Looks fine to me')" "$block"
assert_contains "missing 'Decisions needed' is named in the reason" \
  "$(gate angel:code-reviewer $'Findings\nVERDICT: APPROVE')" "Decisions needed"
assert_contains "decisions present but no verdict is sent back for the verdict" \
  "$(gate angel:code-reviewer $'## Decisions needed\nNone.')" "VERDICT"
assert_empty "code-reviewer with decisions section and VERDICT finishes" "$(gate angel:code-reviewer "$good_review")"
assert_empty "bold markdown **VERDICT:** is accepted" \
  "$(gate angel:drift-checker $'### Decisions needed\n- D: ...\n**VERDICT:** PROCEED')"
assert_json "un-namespaced agent names are handled too" "$(gate spec-reviewer 'no verdict')" "$block"

# --- verifier
assert_contains "verifier without an Evidence section is sent back" \
  "$(gate angel:verifier $'## Decisions needed\nNone.\nVERDICT: VERIFIED')" "Evidence"
assert_empty "verifier with evidence, decisions and verdict finishes" \
  "$(gate angel:verifier $'## Evidence\n### csv-download\n- ok\n## Decisions needed\nNone.\nVERDICT: VERIFIED')"

# --- reports saved by the goldfish itself ("Report: <path>" in the final message)
short=$'Report: .adlc/add-export/reviews/code-review.md\n2 major, 1 minor.\n\n## Decisions needed\nNone.\n\nVERDICT: CHANGES_REQUESTED'
assert_contains "a named report file that doesn't exist is sent back" \
  "$(gate angel:code-reviewer "$short")" "code-review.md"
mkdir -p "$p/.adlc/add-export/reviews"
printf '## Code review\n### Major\n- a\n\n## Decisions needed\nNone.\n\nVERDICT: CHANGES_REQUESTED\n' \
  >"$p/.adlc/add-export/reviews/code-review.md"
assert_empty "short final message + saved report lets the reviewer finish" "$(gate angel:code-reviewer "$short")"
assert_empty "bold, backticked absolute report paths are understood" \
  "$(gate angel:drift-checker "**Report:** \`$p/.adlc/add-export/reviews/code-review.md\`"$'\n## Decisions needed\nNone.\nVERDICT: PROCEED')"
assert_contains "a saved report doesn't excuse a missing verdict in the final message" \
  "$(gate angel:code-reviewer $'Report: .adlc/add-export/reviews/code-review.md\n## Decisions needed\nNone.')" "VERDICT"

vshort=$'Report: .adlc/add-export/reviews/verification.md\n5/5 ACs verified.\n## Decisions needed\nNone.\nVERDICT: VERIFIED'
printf '## Verification\n## Summary\n5/5\nVERDICT: VERIFIED\n' >"$p/.adlc/add-export/reviews/verification.md"
assert_contains "verifier's saved report must have the Evidence section" \
  "$(gate angel:verifier "$vshort")" "Evidence"
printf '## Verification\n## Evidence\n### csv-download\n- ok\n## Decisions needed\nNone.\n' >"$p/.adlc/add-export/reviews/verification.md"
assert_contains "verifier's saved report must carry the VERDICT line (the ship-gate reads it)" \
  "$(gate angel:verifier "$vshort")" "VERDICT"
printf 'VERDICT: VERIFIED\n' >>"$p/.adlc/add-export/reviews/verification.md"
assert_empty "verifier with a complete saved report and a short message finishes" "$(gate angel:verifier "$vshort")"

# --- plain words: specs and plans open with a digest a human can take in at a glance
printf '# Spec\n\n## Problem\nx\n\n## Acceptance Criteria\n- [ ] csv-download: works\n' >"$p/.adlc/add-export/spec.md"
assert_contains "spec.md without an 'In plain words' digest is sent back" "$(gate angel:spec-writer)" "In plain words"
printf '# Plan\n\n## Slices\n### export-button\n' >"$p/.adlc/add-export/plan.md"
assert_contains "plan.md without an 'In plain words' digest is sent back" "$(gate angel:planner)" "In plain words"

# --- names, not id labels (S1, D12, AC3, CR7, E2, F8)
printf '# Spec\n\n## In plain words\n- x\n\n## Acceptance Criteria\n- [ ] AC1: exports\n- [ ] AC2: headers\n' \
  >"$p/.adlc/add-export/spec.md"
out="$(gate angel:spec-writer)"
assert_json "spec.md that labels criteria AC1, AC2 is sent back" "$out" "$block"
assert_contains "the reason lists the labels it found" "$out" "AC1"
assert_contains "the reason asks for real names" "$out" "descriptive name"
printf '# Plan\n\n## In plain words\nx\n\n## Slices\n### S1: scaffold\n- Depends on: none\n### S2: button\n- Depends on: S1\n' \
  >"$p/.adlc/add-export/plan.md"
assert_contains "plan.md with slices named S1, S2 is sent back" "$(gate angel:planner)" "S2"
assert_contains "a reviewer message that says 'D12' is sent back" \
  "$(gate angel:code-reviewer $'Blocked on D12 and CR7.\n## Decisions needed\nNone.\nVERDICT: APPROVE')" "D12"
assert_empty "real names that look like labels are fine inside backticks (\`S3\`), and E2E / P95 aren't labels" \
  "$(gate angel:code-reviewer $'Uploads to `S3`; E2E passes; P95 is 80ms.\n## Decisions needed\nNone.\nVERDICT: APPROVE')"
assert_empty "labels inside fenced code blocks are ignored" \
  "$(gate angel:code-reviewer $'```\nS1=1\n```\n## Decisions needed\nNone.\nVERDICT: APPROVE')"
printf '## Code review\nSee S4 and S5.\n## Decisions needed\nNone.\nVERDICT: APPROVE\n' >"$p/.adlc/add-export/reviews/code-review.md"
assert_contains "labels in a saved report are caught too" \
  "$(gate angel:code-reviewer "$short")" "S4"
printf '## Code review\n## Decisions needed\nNone.\nVERDICT: APPROVE\n' >"$p/.adlc/add-export/reviews/code-review.md"

# --- implementers log milestones to progress.log, so the elephant can give live updates
done_msg=$'## Work item export-button: DONE\n- Files changed: src/export.ts'
assert_contains "implementer that never logged its finish to progress.log is sent back" \
  "$(gate angel:implementer "$done_msg")" "progress.log"
printf '14:02 export-button started: reading the report page\n14:20 export-button done: button works end to end\n' \
  >"$p/.adlc/add-export/progress.log"
assert_empty "implementer with a logged 'done' milestone finishes" "$(gate angel:implementer "$done_msg")"
assert_empty "a logged 'blocked' milestone counts too" \
  "$(printf '14:30 csv-streaming blocked: needs a decision\n' >>"$p/.adlc/add-export/progress.log"; gate angel:implementer $'## Work item csv-streaming: BLOCKED\n- Blockers: x')"
rm "$p/.adlc/ACTIVE"
assert_empty "implementer outside an active feature isn't checked for progress" "$(gate angel:implementer "$done_msg")"

assert_empty "unrelated agents are ignored" "$(gate general-purpose)"

rm -rf "$p"
finish
