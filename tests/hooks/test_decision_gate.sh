#!/usr/bin/env bash
source "$(dirname "$0")/../helpers.sh"

payload() { jq -nc --argjson a "${1:-false}" '{hook_event_name: "Stop", session_id: "s1", stop_hook_active: $a}'; }
block='.decision == "block"'

new_project; p="$CLAUDE_PROJECT_DIR"
assert_empty "no .adlc/: silent" "$(run_hook decision-gate.sh "$(payload)")"

with_feature "$p" add-export review
assert_empty "no decisions.md: silent" "$(run_hook decision-gate.sh "$(payload)")"

# Decisions are named, not numbered: "## <decision-name>: <question>".
cat >"$p/.adlc/add-export/decisions.md" <<'EOF'
# Decisions: add-export

## csv-streaming: Stream the CSV or build it in memory?
- Status: decided
- Decision: stream, by user, 2026-09-23

## export-feature-flag: Put export behind a feature flag?
- Status: pending
- Options:
  - Flag it - safer rollout
  - No flag - simpler

## excel-support: Support Excel too?
- Status: deferred
EOF
out="$(run_hook decision-gate.sh "$(payload)")"
assert_json "a pending decision blocks the stop" "$out" "$block"
assert_contains "the pending decision is named, not numbered" "$out" "export-feature-flag"
reason="$(jq -r .reason <<<"$out")"
if grep -q "csv-streaming\|excel-support" <<<"$reason"; then
  fail "decided and deferred decisions are not listed" "$out"
else
  pass "decided and deferred decisions are not listed"
fi
assert_contains "the reason points at AskUserQuestion" "$out" "AskUserQuestion"

assert_empty "stop_hook_active: at most one nudge per turn" "$(run_hook decision-gate.sh "$(payload true)")"

printf '\n## D7: legacy numbered decision?\n- Status: pending\n' >>"$p/.adlc/add-export/decisions.md"
assert_contains "older numbered files still work" "$(run_hook decision-gate.sh "$(payload)")" "D7"

sed -i.bak 's/^- Status: pending/- Status: decided/' "$p/.adlc/add-export/decisions.md"
assert_empty "all decided or deferred: silent" "$(run_hook decision-gate.sh "$(payload)")"

rm -rf "$p"
finish
