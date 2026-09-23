#!/usr/bin/env bash
# PreToolUse (Edit|Write|MultiEdit|NotebookEdit): stop any agent, elephant or goldfish,
# from writing code that matches a banned pattern in .adlc/rules/.
#
# Agents copy the patterns they see. When a repo has decided a pattern is bad,
# this hook refuses writes that *add* it and tells the agent what to do instead.
# Only new occurrences count: an edit that leaves an existing violation alone
# (the match appears as often in the new text as in the old) is allowed, so
# legacy code can still be touched.
#
# Rules are created with /angel:antipattern. Format: see hooks/rules-lib.sh.

# shellcheck source=hooks/lib.sh
source "$(dirname "$0")/lib.sh"
# shellcheck source=hooks/rules-lib.sh
source "$(dirname "$0")/rules-lib.sh"
angel_read_input

project="$(angel_project_dir)"
rules="$(rules_list "$project")"
[ -n "$rules" ] || angel_allow

path="$(angel_field '.tool_input.file_path // .tool_input.notebook_path')"
[ -n "$path" ] || angel_allow
case "$path" in
  /*) ;;
  *) path="$project/$path" ;;
esac
path="$(angel_physical_path "$path")"
project_phys="$(angel_physical_path "$project")"
case "$path" in
  "$project_phys"/*) rel="${path#"$project_phys"/}" ;;
  *) angel_allow ;; # outside the repo: not this repo's rules
esac

# new = text being written; old = text it replaces (to count only added occurrences).
tool="$(angel_field .tool_name)"
case "$tool" in
  Write)
    new="$(angel_field .tool_input.content)"
    old="$(cat "$path" 2>/dev/null || true)"
    ;;
  Edit)
    new="$(angel_field .tool_input.new_string)"
    old="$(angel_field .tool_input.old_string)"
    ;;
  MultiEdit)
    new="$(jq -r '[.tool_input.edits[]?.new_string] | join("\n")' <<<"$ANGEL_INPUT" 2>/dev/null)"
    old="$(jq -r '[.tool_input.edits[]?.old_string] | join("\n")' <<<"$ANGEL_INPUT" 2>/dev/null)"
    ;;
  NotebookEdit)
    new="$(angel_field .tool_input.new_source)"
    old=""
    ;;
  *) angel_allow ;;
esac
[ -n "$new" ] || angel_allow

blocked=""
asked=""
while IFS= read -r rule; do
  rule_applies "$rule" "$rel" || continue
  pattern="$(rule_value "$rule" pattern)"
  [ -n "$pattern" ] || continue
  added=$(($(rule_count "$pattern" "$new") - $(rule_count "$pattern" "$old")))
  [ "$added" -gt 0 ] || continue

  id="$(rule_value "$rule" id)"
  msg="- [$id] matched: \`$(rule_first_match "$pattern" "$new")\`
  Why: $(rule_section "$rule" Why)
  Instead: $(rule_section "$rule" Instead)"
  if [ "$(rule_value "$rule" action)" = "ask" ]; then
    asked="$asked
$msg"
  else
    blocked="$blocked
$msg"
  fi
done <<<"$rules"

footer="Rules live in .adlc/rules/ (see the file for details). Rewrite the change using the 'Instead' pattern. If this is a legitimate exception, ask the user to add the path to the rule's 'exclude' list."

if [ -n "$blocked" ]; then
  angel_deny "angel antipattern-guard: this change to $rel adds a banned pattern.$blocked

$footer"
fi
if [ -n "$asked" ]; then
  jq -n --arg r "angel antipattern-guard: this change to $rel adds a discouraged pattern.$asked

$footer" \
    '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "ask", permissionDecisionReason: $r}}'
  exit 0
fi
angel_allow
