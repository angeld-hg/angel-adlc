#!/usr/bin/env bash
# PreToolUse (Edit|Write|MultiEdit|NotebookEdit): the elephant doesn't edit source.
#
# In a repo that has opted in (a .adlc/ folder exists), the main session may only
# write inside .adlc/. Source changes go through goldfish subagents, which keeps
# the elephant's context small enough to hold a whole feature.
#
# Allowed:
#   - any call made from inside a subagent (the payload carries agent_id)
#   - files outside the project (plan files, memory, scratchpads)
#   - files under .adlc/
#   - paths matching a glob in .adlc/allow (one per line, relative to the repo root)
#   - everything, when ANGEL_ALLOW_MAIN_EDITS=1
#
# Not covered: writes made through Bash (sed -i, heredocs, etc.). See LEARNINGS.md.

# shellcheck source=hooks/lib.sh
source "$(dirname "$0")/lib.sh"
angel_read_input

[ "${ANGEL_ALLOW_MAIN_EDITS:-}" = "1" ] && angel_allow

project="$(angel_project_dir)"
adlc="$(angel_adlc_dir)"
[ -d "$adlc" ] || angel_allow

[ -n "$(angel_field .agent_id)" ] && angel_allow

path="$(angel_field '.tool_input.file_path // .tool_input.notebook_path')"
[ -n "$path" ] || angel_allow
case "$path" in
  /*) ;;
  *) path="$project/$path" ;;
esac

path="$(angel_physical_path "$path")"
project="$(angel_physical_path "$project")"
adlc="$project/.adlc"

case "$path" in
  "$project"/*) ;;
  *) angel_allow ;;
esac
case "$path" in
  "$adlc"/*) angel_allow ;;
esac

rel="${path#"$project"/}"
if [ -f "$adlc/allow" ]; then
  while IFS= read -r glob || [ -n "$glob" ]; do
    glob="${glob%%#*}"
    glob="$(printf '%s' "$glob" | tr -d '[:space:]')"
    [ -n "$glob" ] || continue
    # shellcheck disable=SC2254 # the glob is meant to match as a pattern
    case "$rel" in
      $glob) angel_allow ;;
    esac
  done <"$adlc/allow"
fi

angel_deny "angel elephant-guard: the orchestrator doesn't edit source ($rel). Delegate this change to a goldfish: dispatch the \`implementer\` agent with the file paths and the slice or finding it addresses. For a one-off manual edit, add a glob to .adlc/allow or restart with ANGEL_ALLOW_MAIN_EDITS=1."
