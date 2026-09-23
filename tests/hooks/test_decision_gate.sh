#!/usr/bin/env bash
source "$(dirname "$0")/../helpers.sh"

payload() { jq -nc --argjson a "${1:-false}" '{hook_event_name: "Stop", session_id: "s1", stop_hook_active: $a}'; }
block='.decision == "block"'

new_project; p="$CLAUDE_PROJECT_DIR"
assert_empty "no .adlc/: silent" "$(run_hook decision-gate.sh "$(payload)")"

with_feature "$p" add-export review
assert_empty "no decisions.md: silent" "$(run_hook decision-gate.sh "$(payload)")"

cat >"$p/.adlc/add-export/decisions.md" <<'EOF'
# Decisions: add-export

## D1: Stream the CSV or build it in memory?
- Status: decided
- Decision: B (stream), user, 2026-09-23

## D2: Put export behind a feature flag?
- Status: pending
- Options:
  - A) Yes, flag it
  - B) No

## D3: Support Excel too?
- Status: deferred
EOF
out="$(run_hook decision-gate.sh "$(payload)")"
assert_json "a pending decision blocks the stop" "$out" "$block"
assert_contains "the pending ids are named" "$out" "D2"
if grep -q "D1\|D3" <<<"$(jq -r .reason <<<"$out")"; then
  fail "decided and deferred decisions are not listed" "$out"
else
  pass "decided and deferred decisions are not listed"
fi
assert_contains "the reason points at AskUserQuestion" "$out" "AskUserQuestion"

assert_empty "stop_hook_active: at most one nudge per turn" "$(run_hook decision-gate.sh "$(payload true)")"

sed -i.bak 's/^- Status: pending/- Status: decided/' "$p/.adlc/add-export/decisions.md"
assert_empty "all decided or deferred: silent" "$(run_hook decision-gate.sh "$(payload)")"

rm -rf "$p"
finish
