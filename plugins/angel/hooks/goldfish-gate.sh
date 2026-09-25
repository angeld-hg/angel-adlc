#!/usr/bin/env bash
# SubagentStop: a goldfish can't finish without leaving what its job requires.
#
#   spec-writer    -> .adlc/<slug>/spec.md with "## In plain words" and "## Acceptance Criteria"
#   planner        -> .adlc/<slug>/plan.md with "## In plain words" and "## Slices"
#   implementer    -> its final milestone ("<name> done|blocked") in .adlc/<slug>/progress.log,
#                     which the elephant streams to the user as live updates
#   repo-scout     -> .adlc/verification.md with "## Evidence recipes"
#   spec-reviewer,
#   drift-checker,
#   code-reviewer,
#   doc-auditor    -> final message has a "## Decisions needed" section and a "VERDICT:" line
#   verifier       -> final message has "## Evidence", "## Decisions needed" and a "VERDICT:" line
#
# Names, not labels: specs, plans, saved reports and final messages may not use id-style
# labels (S1, D12, AC3, CR7...). The user can't tell what "D12" means; every concept gets a
# short descriptive name instead (see angel_id_labels in lib.sh).
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

# require_named <text> <where>: no id-style labels (S1, D12, AC3...), only real names.
require_named() {
  local labels
  labels="$(angel_id_labels "$1")"
  if [ -n "$labels" ]; then
    angel_block "angel goldfish-gate: $2 uses id labels ($labels). The person steering this work can't tell what those mean. Give every concept a short descriptive name instead (a criterion like \`csv-download\`, a slice like \`export-button\`, a decision like \`csv-streaming\`, a finding by what's wrong) and refer to it by that name everywhere. If one of these is a real product name, such as AWS S3, wrap it in backticks."
  fi
}

# require_plain_words <file>: specs and plans open with a digest a human can take in at a glance.
require_plain_words() {
  if ! grep -qE '^## In plain words' "$1"; then
    angel_block "angel goldfish-gate: $1 is missing its '## In plain words' section at the top: a short digest in everyday language (no jargon, no ids) so the user can take it in at a glance. Add it, then finish."
  fi
}

# require_progress_logged <feature dir>: an implementer's final milestone is in progress.log,
# which the elephant streams to the user as live updates.
require_progress_logged() {
  local name
  name="$(grep -m1 -E '^#+[[:space:]]*(Work item|Slice)[[:space:]]+[^:]+:[[:space:]]*(DONE|BLOCKED)' <<<"$msg" \
    | sed -E 's/^#+[[:space:]]*(Work item|Slice)[[:space:]]+//; s/:.*//' | tr -d '`*')"
  if [ -z "$name" ]; then
    angel_block "angel goldfish-gate: start your final report with '## Work item <name>: DONE' or '## Work item <name>: BLOCKED', using the work item's name from plan.md."
  fi
  if ! grep -qiE "[[:space:]]$name[[:space:]]+(done|blocked)" "$1/progress.log" 2>/dev/null; then
    angel_block "angel goldfish-gate: you haven't logged your final milestone. Append it to $1/progress.log (the user gets live updates from that file), e.g.: printf '%s %s done: %s\\n' \"\$(date +%H:%M)\" \"$name\" \"<one plain sentence about what now works>\" >> $1/progress.log"
  fi
}

case "$agent" in
  spec-writer | planner)
    feature="$(angel_feature_dir)"
    # No active feature means the agent was used outside /angel:start; nothing to check.
    [ -n "$feature" ] || angel_allow
    if [ "$agent" = "spec-writer" ]; then
      artifact="$feature/spec.md"
      require_artifact "$artifact" "## Acceptance Criteria" \
        "The spec needs testable acceptance criteria before planning can start."
    else
      artifact="$feature/plan.md"
      require_artifact "$artifact" "## Slices" \
        "The plan needs vertical slices, each with the files it owns, before implementation can start."
    fi
    require_plain_words "$artifact"
    require_named "$(cat "$artifact")" "$artifact"
    require_named "$msg" "your final message"
    ;;
  implementer)
    require_named "$msg" "your final report"
    feature="$(angel_feature_dir)"
    [ -n "$feature" ] || angel_allow
    require_progress_logged "$feature"
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
    require_named "$msg" "your final message"
    [ -z "$saved" ] || require_named "$(cat "$saved")" "your saved report ($saved)"
    ;;
  verifier)
    require_saved_report
    require_named "$msg" "your final message"
    [ -z "$saved" ] || require_named "$(cat "$saved")" "your saved report ($saved)"
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
