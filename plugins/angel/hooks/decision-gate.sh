#!/usr/bin/env bash
# Stop: the elephant can't end its turn while the user still has decisions to make.
#
# Architecture-level findings (from reviewers, the verifier, the spec-writer or the
# planner) are recorded in .adlc/<slug>/decisions.md as entries with
# "- Status: pending". They belong to the user, not to an agent. If any are pending
# when the elephant tries to stop, this hook sends it back to ask them with
# AskUserQuestion (skills/decide), or to mark them deferred if the user said so.
#
# stop_hook_active guards against loops: at most one nudge per turn.

# shellcheck source=hooks/lib.sh
source "$(dirname "$0")/lib.sh"
angel_read_input

[ "$(angel_field .stop_hook_active)" = "true" ] && angel_allow

feature="$(angel_feature_dir)"
[ -n "$feature" ] || angel_allow
file="$feature/decisions.md"
[ -f "$file" ] || angel_allow

# Each decision is a "## D<n>: <question>" heading followed by its fields; list the pending ones.
pending="$(awk '
  /^## D[0-9]+/ { id = $2; sub(/:$/, "", id); next }
  /^- Status:[[:space:]]*pending/ && id != "" { printf "%s%s", (n++ ? ", " : ""), id }
' "$file")"
[ -n "$pending" ] || angel_allow

angel_block "angel decision-gate: decisions still waiting for the user in .adlc/$(angel_active_slug)/decisions.md: $pending. Follow the angel:decide skill: ask them now with AskUserQuestion (recommended option first), then record each answer. If the user has explicitly chosen to postpone one, set its status to 'deferred'. Don't decide them yourself."
