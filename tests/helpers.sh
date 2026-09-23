#!/usr/bin/env bash
# Tiny test harness for hook scripts: build a throwaway project, pipe a JSON
# payload into a hook, and assert on what it prints.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PLUGIN_ROOT="$REPO_ROOT/plugins/angel"
HOOKS="$PLUGIN_ROOT/hooks"
FAILS=0
PASSES=0

# new_project: make a fresh temp dir and export it as CLAUDE_PROJECT_DIR.
# Call it directly (not in $(...)), or the export is lost in the subshell.
new_project() {
  CLAUDE_PROJECT_DIR="$(mktemp -d "${TMPDIR:-/tmp}/angel-test.XXXXXX")"
  export CLAUDE_PROJECT_DIR
}

# with_feature <project> <slug> <phase> -> creates .adlc/<slug>/state.md and ACTIVE.
with_feature() {
  local p="$1" slug="$2" phase="$3"
  mkdir -p "$p/.adlc/$slug"
  printf '%s\n' "$slug" >"$p/.adlc/ACTIVE"
  cat >"$p/.adlc/$slug/state.md" <<EOF
---
feature: $slug
phase: $phase
updated: 2026-09-23
next: run /angel:plan
---

# $slug

## Decision log
- 2026-09-22: started from idea
- 2026-09-23: spec approved by user
EOF
}

# run_hook <script> <json> -> hook stdout (stderr discarded).
# Runs from the project root, like Claude Code does: cwd-sensitive bugs (such as
# unquoted globs expanding against real files) only show up there.
run_hook() {
  (cd "${CLAUDE_PROJECT_DIR:-.}" && printf '%s' "$2" | bash "$HOOKS/$1" 2>/dev/null)
}

pass() { PASSES=$((PASSES + 1)); printf '  ok   %s\n' "$1"; }
fail() { FAILS=$((FAILS + 1)); printf '  FAIL %s\n       %s\n' "$1" "$2"; }

assert_empty() {
  if [ -z "$2" ]; then pass "$1"; else fail "$1" "expected no output, got: $2"; fi
}

assert_contains() {
  if grep -qF -- "$3" <<<"$2"; then pass "$1"; else fail "$1" "expected output to contain '$3', got: $2"; fi
}

# assert_json <name> <output> <jq filter that must evaluate to true>
assert_json() {
  if [ -n "$2" ] && jq -e "$3" <<<"$2" >/dev/null 2>&1; then
    pass "$1"
  else
    fail "$1" "expected $3 to hold, got: ${2:-<no output>}"
  fi
}

finish() {
  printf '%s: %d passed, %d failed\n' "$(basename "$0")" "$PASSES" "$FAILS"
  [ "$FAILS" -eq 0 ]
}
