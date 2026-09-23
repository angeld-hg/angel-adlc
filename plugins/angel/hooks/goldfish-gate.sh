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

# require_report_sections <heading>... : each must appear as a markdown heading in the final message.
require_report_sections() {
  local h missing=""
  for h in "$@"; do
    grep -qiE "^#+[[:space:]]*$h" <<<"$msg" || missing="$missing '## $h'"
  done
  if [ -n "$missing" ]; then
    angel_block "angel goldfish-gate: your final report is missing:$missing. Use the output format in your agent instructions. Write 'None.' under 'Decisions needed' if there are no choices for the user."
  fi
}

require_verdict() {
  if ! grep -qE '^[[:space:]*_#]*VERDICT:' <<<"$msg"; then
    angel_block "angel goldfish-gate: end your report with a line of the form 'VERDICT: <value>' (see your agent instructions for the allowed values) so the orchestrator can gate on it."
  fi
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
    require_report_sections "Decisions needed"
    require_verdict
    ;;
  verifier)
    require_report_sections "Evidence" "Decisions needed"
    require_verdict
    ;;
esac

angel_allow
