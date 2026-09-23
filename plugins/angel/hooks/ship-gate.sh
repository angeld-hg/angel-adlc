#!/usr/bin/env bash
# PreToolUse (Bash): no PR without proof.
#
# In a repo with an active angel feature, `gh pr create` is denied unless the
# feature's verification report (.adlc/<slug>/reviews/verification.md) ends in
# "VERDICT: VERIFIED", or the user has waived verification (state.md frontmatter
# `verification: waived`, set only after the user chose to waive it through
# /angel:decide). This makes the verify phase a hard gate, not a suggestion.

# shellcheck source=hooks/lib.sh
source "$(dirname "$0")/lib.sh"
angel_read_input

cmd="$(angel_field .tool_input.command)"
grep -qE '(^|[;&|[:space:]])gh[[:space:]]+pr[[:space:]]+create' <<<"$cmd" || angel_allow

feature="$(angel_feature_dir)"
[ -n "$feature" ] || angel_allow

[ "$(angel_frontmatter_value "$feature/state.md" verification)" = "waived" ] && angel_allow

report="$feature/reviews/verification.md"
if [ -f "$report" ] && grep -qE '^[[:space:]*_#]*VERDICT:[[:space:]*_]*VERIFIED\b' "$report"; then
  angel_allow
fi

slug="$(angel_active_slug)"
if [ -f "$report" ]; then
  why="the latest verification report (.adlc/$slug/reviews/verification.md) isn't VERIFIED"
else
  why="there's no verification report for '$slug' yet"
fi
angel_deny "angel ship-gate: can't open a PR because $why. Run /angel:verify to collect evidence for every acceptance criterion. If some ACs genuinely can't be verified, raise them as decisions with /angel:decide; only the user can waive verification."
