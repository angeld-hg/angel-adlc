#!/usr/bin/env bash
# Stop: once a feature ships, don't let the session end without a retro.
#
# Fires at most once per session (marker file keyed on session_id), and only
# when the active feature's state.md says `phase: shipped` and retro.md is missing.
# The retro is where gaps in skills, agents and CLAUDE.md get turned into edits.

# shellcheck source=hooks/lib.sh
source "$(dirname "$0")/lib.sh"
angel_read_input

[ "$(angel_field .stop_hook_active)" = "true" ] && angel_allow

feature="$(angel_feature_dir)"
[ -n "$feature" ] || angel_allow
[ "$(angel_frontmatter_value "$feature/state.md" phase)" = "shipped" ] || angel_allow
[ -f "$feature/retro.md" ] && angel_allow

session="$(angel_field .session_id)"
marker="${TMPDIR:-/tmp}/angel-retro-nudge-${session:-unknown}"
[ -f "$marker" ] && angel_allow
touch "$marker" 2>/dev/null || true

angel_block "angel retro-nudge: $(angel_active_slug) has shipped but has no retro yet. Run /angel:retro now: capture what went wrong or was slow, and propose concrete edits to skills, agents, hooks or CLAUDE.md. If the user wants to skip it, write a one-line retro.md saying so."
