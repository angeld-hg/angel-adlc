#!/usr/bin/env bash
# PreToolUse (Edit|Write|MultiEdit|NotebookEdit): reviewers write their report and nothing else.
#
# code-reviewer, drift-checker, spec-reviewer and verifier have the Write tool so they
# can save their own report instead of the elephant copying it out of their final
# message. They judge the work; they never change it. So a write from one of them is
# allowed only when the target is
#   .adlc/<slug>/reviews/<name>.md      (all four; <slug> must be an existing feature folder)
#   .adlc/<slug>/evidence/<name>        (verifier only: its throwaway scripts and fixtures)
# Everything else they try to write is denied.
#
# The caller is identified by `agent_type` in the payload, which Claude Code sets only
# for calls made inside a subagent (see LEARNINGS.md, "can a hook tell the elephant from
# a goldfish?"). Calls without it (the main session) and other agents pass straight
# through; elephant-guard and antipattern-guard handle those.
#
# Unlike most angel hooks this one also applies in repos without .adlc/, like the
# goldfish-gate's report checks: it only ever affects these four agents, which are
# read-only everywhere. It doesn't let them create .adlc/ either.
#
# Not covered: writes made through Bash (tee, >, sed -i). Three of the four have Bash
# for read-only commands; their instructions forbid writing with it, but no hook sees it.

# shellcheck source=hooks/lib.sh
source "$(dirname "$0")/lib.sh"
angel_read_input

agent="$(angel_field .agent_type)"
agent="${agent##*:}" # plugin agents arrive namespaced, e.g. "angel:code-reviewer"
case "$agent" in
  code-reviewer | drift-checker | spec-reviewer | verifier) ;;
  *) angel_allow ;;
esac

path="$(angel_field '.tool_input.file_path // .tool_input.notebook_path')"
[ -n "$path" ] || angel_allow # nothing to write to; let the tool report its own error

allowed=".adlc/<slug>/reviews/<name>.md"
[ "$agent" = "verifier" ] && allowed="$allowed (or a throwaway script under .adlc/<slug>/evidence/)"
deny() {
  angel_deny "angel reviewer-write-guard: $agent may only write its own report, to $allowed inside an existing feature folder: the report path the orchestrator gave you. It can't write $1. You don't change the work you judge: put the finding or the suggested change in your report instead."
}

project="$(angel_project_dir)"
case "$path" in
  /*) ;;
  *) path="$project/$path" ;;
esac
# Refuse '.' and '..' segments outright rather than trusting how they'd resolve.
case "/$path/" in
  */../* | */./*) deny "$path" ;;
esac

path="$(angel_physical_path "$path")"
project="$(angel_physical_path "$project")"
case "$path" in
  "$project"/.adlc/*) rel="${path#"$project"/.adlc/}" ;;
  *) deny "$path" ;;
esac

# rel must be exactly <slug>/<folder>/<file>.
IFS=/ read -r -a parts <<<"$rel"
[ "${#parts[@]}" -eq 3 ] || deny ".adlc/$rel"
slug="${parts[0]}" folder="${parts[1]}" file="${parts[2]}"
[ -n "$slug" ] && [ -n "$file" ] && [ -d "$project/.adlc/$slug" ] || deny ".adlc/$rel"

case "$folder" in
  reviews)
    case "$file" in
      *.md) angel_allow ;;
    esac
    ;;
  evidence)
    [ "$agent" = "verifier" ] && angel_allow
    ;;
esac
deny ".adlc/$rel"
