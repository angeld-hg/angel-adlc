#!/usr/bin/env bash
# Deterministic checks for agent-facing docs. The judgement calls (drift, clarity)
# are left to the doc-auditor agent; this script only checks what a script can check.
#
# Usage: lint-skills.sh [root]   (default: current directory)
# Exit:  0 = no errors (warnings allowed), 1 = at least one error.

set -uo pipefail

root="${1:-.}"
root="${root%/}"
errors=0
warnings=0

err()  { errors=$((errors + 1));     printf 'ERROR %s: %s\n' "$1" "$2"; }
warn() { warnings=$((warnings + 1)); printf 'WARN  %s: %s\n' "$1" "$2"; }

# Print a file's frontmatter (between the first two --- lines), or nothing if absent.
frontmatter() {
  awk 'NR == 1 && !/^---[[:space:]]*$/ { exit } /^---[[:space:]]*$/ { n++; if (n == 2) exit; next } n == 1' "$1"
}

fm_value() { # <frontmatter text> <key>
  sed -n "s/^$2:[[:space:]]*//p" <<<"$1" | head -n 1 | sed -e 's/^"//' -e 's/"$//'
}

# Files to check: every SKILL.md, and markdown files directly inside an agents/ dir.
# Dependency and VCS dirs are skipped.
files=()
while IFS= read -r f; do
  files+=("$f")
done < <(find "$root" \( -name node_modules -o -name .git -o -name .venv -o -name vendor \) -prune -o \
  \( -name SKILL.md -o -path '*/agents/*.md' \) -type f -print | sort)

for f in "${files[@]}"; do
  rel="${f#"$root"/}"
  fm="$(frontmatter "$f")"
  if [ -z "$fm" ]; then
    err "$rel" "no YAML frontmatter (needs name + description between --- lines)"
    continue
  fi

  name="$(fm_value "$fm" name)"
  desc="$(fm_value "$fm" description)"
  [ -n "$name" ] || err "$rel" "frontmatter is missing 'name'"
  [ -n "$desc" ] || { err "$rel" "frontmatter is missing 'description'"; continue; }

  case "$f" in
    */SKILL.md)
      dir="$(basename "$(dirname "$f")")"
      if [ -n "$name" ] && [ "$name" != "$dir" ]; then
        warn "$rel" "name '$name' doesn't match its directory '$dir'"
      fi
      grep -qiE 'use (when|after|before|to|for|at)' <<<"$desc" \
        || err "$rel" "description doesn't say when to use it (e.g. 'Use when ...')"
      grep -qiE "(do not|don't|never) " <<<"$desc" \
        || warn "$rel" "description has no negative example (e.g. 'Do not use for ...')"
      ;;
    *)
      grep -qiE "(do not|don't|never) " <<<"$desc" \
        || warn "$rel" "agent description doesn't say when not to use it"
      ;;
  esac

  [ "${#desc}" -le 1024 ] || err "$rel" "description is ${#desc} chars (max 1024)"
  [ "${#desc}" -ge 60 ] || warn "$rel" "description is only ${#desc} chars; it's the router, so say what + when"

  lines="$(wc -l <"$f" | tr -d ' ')"
  [ "$lines" -le 500 ] || err "$rel" "$lines lines (keep bodies under 500; move detail to reference files or scripts)"
done

# CLAUDE.md should be a thin layer over AGENTS.md.
if [ -f "$root/CLAUDE.md" ]; then
  lines="$(wc -l <"$root/CLAUDE.md" | tr -d ' ')"
  [ "$lines" -le 200 ] || warn "CLAUDE.md" "$lines lines; move procedures into skills and shared facts into AGENTS.md"
  if [ -f "$root/AGENTS.md" ] && ! grep -qE '^@AGENTS\.md' "$root/CLAUDE.md"; then
    warn "CLAUDE.md" "AGENTS.md exists but CLAUDE.md doesn't import it (add '@AGENTS.md' at the top)"
  fi
elif [ -f "$root/AGENTS.md" ]; then
  warn "CLAUDE.md" "missing; Claude Code won't read AGENTS.md without it (create one containing '@AGENTS.md')"
fi

printf '\nlint-skills: %d file(s) checked, %d error(s), %d warning(s)\n' "${#files[@]}" "$errors" "$warnings"
[ "$errors" -eq 0 ]
