#!/usr/bin/env bash
source "$(dirname "$0")/../helpers.sh"

sid="test-$$-$RANDOM"
payload() { jq -nc --arg s "$sid" --argjson a "${1:-false}" '{hook_event_name: "Stop", session_id: $s, stop_hook_active: $a}'; }
block='.decision == "block"'
export TMPDIR="${TMPDIR:-/tmp}"

new_project; p="$CLAUDE_PROJECT_DIR"
assert_empty "no .adlc/: silent" "$(run_hook retro-nudge.sh "$(payload)")"

with_feature "$p" add-export review
assert_empty "feature not shipped yet: silent" "$(run_hook retro-nudge.sh "$(payload)")"

sed -i.bak 's/^phase: review/phase: shipped/' "$p/.adlc/add-export/state.md"
assert_empty "stop_hook_active: silent" "$(run_hook retro-nudge.sh "$(payload true)")"
assert_json "shipped without retro.md: nudges once" "$(run_hook retro-nudge.sh "$(payload)")" "$block"
assert_empty "second stop in the same session: silent" "$(run_hook retro-nudge.sh "$(payload)")"

rm -f "$TMPDIR/angel-retro-nudge-$sid"
printf 'retro\n' >"$p/.adlc/add-export/retro.md"
assert_empty "retro.md exists: silent" "$(run_hook retro-nudge.sh "$(payload)")"

rm -f "$TMPDIR/angel-retro-nudge-$sid"
rm -rf "$p"
finish
