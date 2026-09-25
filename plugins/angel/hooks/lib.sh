#!/usr/bin/env bash
# Shared helpers for angel hooks. Source this file; don't execute it.
#
# Every hook fails open: if jq is missing or the input is unreadable, the hook
# exits 0 and Claude Code carries on as if the hook weren't there. A broken
# hook should never brick a session.

set -uo pipefail

command -v jq >/dev/null 2>&1 || exit 0

ANGEL_INPUT=""

# Read the hook's JSON payload from stdin once; fields are pulled with angel_field.
angel_read_input() {
  ANGEL_INPUT="$(cat)"
  [ -n "$ANGEL_INPUT" ] || ANGEL_INPUT='{}'
}

# angel_field '.jq.path' -> value, or empty string when absent/null.
angel_field() {
  jq -r "$1 // empty" <<<"$ANGEL_INPUT" 2>/dev/null || true
}

# The project root. CLAUDE_PROJECT_DIR is set for hooks; cwd is the fallback.
angel_project_dir() {
  local d="${CLAUDE_PROJECT_DIR:-}"
  [ -n "$d" ] || d="$(angel_field .cwd)"
  [ -n "$d" ] || d="$PWD"
  printf '%s' "${d%/}"
}

angel_adlc_dir() {
  printf '%s/.adlc' "$(angel_project_dir)"
}

# Slug of the feature the elephant is driving, from .adlc/ACTIVE. Empty if none.
angel_active_slug() {
  local f
  f="$(angel_adlc_dir)/ACTIVE"
  if [ -f "$f" ]; then
    tr -d '[:space:]' <"$f"
  fi
}

# Absolute path of the active feature's folder. Empty if there's no active feature.
angel_feature_dir() {
  local slug
  slug="$(angel_active_slug)"
  if [ -n "$slug" ] && [ -d "$(angel_adlc_dir)/$slug" ]; then
    printf '%s/%s' "$(angel_adlc_dir)" "$slug"
  fi
}

# angel_frontmatter_value <file> <key> -> value of `key:` in the file's YAML frontmatter.
angel_frontmatter_value() {
  local file="$1" key="$2"
  [ -f "$file" ] || return 0
  awk -v k="$key" '
    /^---[[:space:]]*$/ { n++; if (n == 2) exit; next }
    n == 1 && $0 ~ "^" k ":" { sub("^" k ":[[:space:]]*", ""); print; exit }
  ' "$file"
}

# Resolve a path to its physical form (symlinks such as /tmp -> /private/tmp),
# even when the file itself doesn't exist yet. Falls back to the input.
angel_physical_path() {
  local p="$1" dir base
  dir="$(dirname "$p")"
  base="$(basename "$p")"
  while [ ! -d "$dir" ] && [ "$dir" != "/" ]; do
    base="$(basename "$dir")/$base"
    dir="$(dirname "$dir")"
  done
  if dir="$(cd "$dir" 2>/dev/null && pwd -P)"; then
    printf '%s/%s' "${dir%/}" "$base"
  else
    printf '%s' "$p"
  fi
}

# angel_id_labels <text> -> comma-separated id-style labels found in the text (S1, D12, AC3,
# CR7, E2, F8), or nothing. Labels like these are unreadable to the human steering the work
# ("what is D12?"), so goldfish must use short descriptive names instead. Text inside
# backticks and fenced code blocks is ignored, so real names such as `S3` can be quoted,
# and E2E / P95 don't match.
angel_id_labels() {
  printf '%s\n' "$1" \
    | awk '/^[[:space:]]*```/ { fence = !fence; next } !fence' \
    | sed 's/`[^`]*`//g' \
    | grep -oE '(^|[^A-Za-z0-9_./-])(AC|CR|S|D|E|F)[0-9]{1,3}([^A-Za-z0-9_]|$)' \
    | grep -oE '(AC|CR|S|D|E|F)[0-9]{1,3}' \
    | awk '!seen[$0]++' | head -n 8 | paste -sd, - | sed 's/,/, /g'
}

# --- Output helpers. Each one prints the JSON Claude Code expects and exits. ---

angel_allow() {
  exit 0
}

# PreToolUse: refuse the tool call and tell the model why.
angel_deny() {
  jq -n --arg r "$1" \
    '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "deny", permissionDecisionReason: $r}}'
  exit 0
}

# Stop / SubagentStop: keep the agent working, with $1 as its next instruction.
angel_block() {
  jq -n --arg r "$1" '{decision: "block", reason: $r}'
  exit 0
}

# SessionStart (and friends): inject text into the model's context.
angel_context() {
  jq -n --arg e "$1" --arg c "$2" \
    '{hookSpecificOutput: {hookEventName: $e, additionalContext: $c}}'
  exit 0
}
