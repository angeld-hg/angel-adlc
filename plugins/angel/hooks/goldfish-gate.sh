#!/usr/bin/env bash
# SubagentStop: a goldfish can't finish without leaving what its job requires.
#
#   spec-writer    -> .adlc/<slug>/spec.md with "## Acceptance Criteria"
#   planner        -> .adlc/<slug>/plan.md with "## Slices"
#   repo-scout     -> .adlc/verification.md with "## Evidence recipes"
#   spec-reviewer,
#   drift-checker,
#   code-reviewer,
#   doc-auditor    -> final message has a "## Decisions needed" section and a "VERDICT:" line
#   verifier       -> final message has "## Evidence", "## Decisions needed" and a "VERDICT:" line
#
# Saved reports: when the orchestrator gives a reviewer or the verifier a report path,
# it writes the full report there and its final message starts with "Report: <path>".
# Then the named file must exist and be non-empty, and the verifier's "## Evidence"
# section and VERDICT line are checked in that file (the ship-gate reads it) instead
# of the message. "Decisions needed" and "VERDICT:" still have to be in the final
# message, because that's all the orchestrator reads.
#
# The "Decisions needed" section is how architecture-level findings reach the user
# as choices (see skills/decide) instead of being settled silently by an agent.
#
# If a requirement isn't met, the hook blocks the stop and re-injects the
# instruction, so the subagent keeps working. stop_hook_active guards against
# loops: a goldfish is sent back at most once per stop attempt chain, and the
# elephant's skills double-check the artifact afterwards.

# shellcheck source=hooks/lib.sh
source "$(dirname "$0")/lib.sh"
angel_read_input

[ "$(angel_field .stop_hook_active)" = "true" ] && angel_allow

agent="$(angel_field .agent_type)"
agent="${agent##*:}" # plugin agents arrive namespaced, e.g. "angel:planner"
msg="$(angel_field .last_assistant_message)"

# require_artifact <file> <heading> <agent-facing instruction>
require_artifact() {
  local file="$1" heading="$2" what="$3"
  if [ ! -s "$file" ]; then
    angel_block "angel goldfish-gate: you haven't written $file yet. $what Write it now, then finish."
  fi
  if ! grep -qF "$heading" "$file"; then
    angel_block "angel goldfish-gate: $file is missing the '$heading' section. $what Add it, then finish."
  fi
}

# require_sections <text> <where> <heading>... : each must appear as a markdown heading in <text>.
require_sections() {
  local text="$1" where="$2" h missing=""
  shift 2
  for h in "$@"; do
    grep -qiE "^#+[[:space:]]*$h" <<<"$text" || missing="$missing '## $h'"
  done
  if [ -n "$missing" ]; then
    angel_block "angel goldfish-gate: $where is missing:$missing. Use the output format in your agent instructions. Write 'None.' under 'Decisions needed' if there are no choices for the user."
  fi
}

# require_verdict <text> <where>
require_verdict() {
  if ! grep -qE '^[[:space:]*_#]*VERDICT:' <<<"$1"; then
    angel_block "angel goldfish-gate: end $2 with a line of the form 'VERDICT: <value>' (see your agent instructions for the allowed values) so the orchestrator can gate on it."
  fi
}

# The path from a "Report: <path>" line in the final message (markdown bold and
# backticks allowed), or empty when the goldfish didn't save a report itself.
report_path() {
  grep -m1 -E '^[[:space:]*_]*Report:' <<<"$msg" \
    | sed -E 's/^[^:]*:[[:space:]]*//' | tr -d '`*' | sed -E 's/^[[:space:]_]+//; s/[[:space:]_]+$//'
}

# Sets $saved to the saved report's absolute path (empty if none was named) and
# sends the goldfish back if that file is missing. Not for use in $(...): angel_block
# has to exit the hook itself.
require_saved_report() {
  local p
  saved=""
  p="$(report_path)"
  [ -n "$p" ] || return 0
  case "$p" in
    /*) ;;
    *) p="$(angel_project_dir)/$p" ;;
  esac
  if [ ! -s "$p" ]; then
    angel_block "angel goldfish-gate: your final message says your report is at $p, but that file is missing or empty. Write your full report there, then finish with the short final message from your agent instructions."
  fi
  saved="$p"
}

case "$agent" in
  spec-writer | planner)
    feature="$(angel_feature_dir)"
    # No active feature means the agent was used outside /angel:start; nothing to check.
    [ -n "$feature" ] || angel_allow
    if [ "$agent" = "spec-writer" ]; then
      require_artifact "$feature/spec.md" "## Acceptance Criteria" \
        "The spec needs testable acceptance criteria before planning can start."
    else
      require_artifact "$feature/plan.md" "## Slices" \
        "The plan needs vertical slices, each with the files it owns, before implementation can start."
    fi
    ;;
  repo-scout)
    [ -d "$(angel_adlc_dir)" ] || angel_allow
    require_artifact "$(angel_adlc_dir)/verification.md" "## Evidence recipes" \
      "The verification profile must say how to prove a change works in this repo."
    ;;
  spec-reviewer | drift-checker | code-reviewer | doc-auditor)
    require_saved_report
    require_sections "$msg" "your final report" "Decisions needed"
    require_verdict "$msg" "your report"
    ;;
  verifier)
    require_saved_report
    if [ -n "$saved" ]; then
      require_sections "$(cat "$saved")" "your saved report ($saved)" "Evidence"
      require_verdict "$(cat "$saved")" "your saved report ($saved)"
      require_sections "$msg" "your final message" "Decisions needed"
    else
      require_sections "$msg" "your final report" "Evidence" "Decisions needed"
    fi
    require_verdict "$msg" "your report"
    ;;
esac

angel_allow
