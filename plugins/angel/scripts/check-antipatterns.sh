#!/usr/bin/env bash
# Scan for anti-pattern rule violations from .adlc/rules/.
#
# Usage:
#   check-antipatterns.sh                 scan every tracked file (baseline / audit)
#   check-antipatterns.sh --diff [base]   scan only lines added since base (default main),
#                                         including uncommitted changes; catches writes that
#                                         bypassed the hook, e.g. via Bash
#   check-antipatterns.sh --validate      check that every rule file is well-formed
#   check-antipatterns.sh --rule <id> ... restrict any mode to one rule (repeatable)
#
# Output: one line per violation, "<rule-id> <path>:<line>: <text>", then a summary.
# Exit:   0 = clean, 1 = violations or invalid rules, 2 = usage error.

set -uo pipefail

# shellcheck source=hooks/rules-lib.sh
source "$(cd "$(dirname "$0")/../hooks" && pwd)/rules-lib.sh"

root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "$root" || exit 2

mode=scan
base=main
only=()
while [ $# -gt 0 ]; do
  case "$1" in
    --diff)
      mode=diff
      if [ $# -gt 1 ] && [ "${2#-}" = "$2" ]; then base="$2"; shift; fi
      ;;
    --validate) mode=validate ;;
    --rule) only+=("$2"); shift ;;
    -h | --help) sed -n '2,15p' "$0"; exit 0 ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
  shift
done

rules=()
while IFS= read -r r; do
  [ -n "$r" ] || continue
  if [ ${#only[@]} -gt 0 ]; then
    keep=0
    for id in "${only[@]}"; do [ "$(basename "$r" .md)" = "$id" ] && keep=1; done
    [ "$keep" -eq 1 ] || continue
  fi
  rules+=("$r")
done < <(rules_list "$root")

if [ ${#rules[@]} -eq 0 ]; then
  echo "No anti-pattern rules in .adlc/rules/ (create one with /angel:antipattern)."
  exit 0
fi

if [ "$mode" = validate ]; then
  bad=0
  for r in "${rules[@]}"; do
    problems="$(rule_problems "$r")"
    if [ -n "$problems" ]; then
      bad=$((bad + 1))
      while IFS= read -r p; do printf 'INVALID %s: %s\n' "${r#"$root"/}" "$p"; done <<<"$problems"
    fi
  done
  printf '\n%d rule(s), %d invalid\n' "${#rules[@]}" "$bad"
  [ "$bad" -eq 0 ]
  exit
fi

# Build a TSV of candidate lines: path<TAB>line<TAB>text
lines_file="$(mktemp "${TMPDIR:-/tmp}/angel-ap.XXXXXX")"
trap 'rm -f "$lines_file"' EXIT

if [ "$mode" = diff ]; then
  mb="$(git merge-base "$base" HEAD 2>/dev/null)" || { echo "can't find merge base with '$base'" >&2; exit 2; }
  git diff -U0 --no-color "$mb" | awk '
    /^\+\+\+ / { f = substr($0, 5); sub(/^b\//, "", f); next }
    /^@@ / { split($3, a, ","); ln = substr(a[1], 2) + 0; next }
    /^\+/ && f != "/dev/null" { print f "\t" ln "\t" substr($0, 2); ln++ }
  ' >"$lines_file"
  # Untracked files count as fully added.
  git ls-files --others --exclude-standard | while IFS= read -r f; do
    [ -f "$f" ] && awk -v f="$f" '{ print f "\t" NR "\t" $0 }' "$f"
  done >>"$lines_file"
else
  git ls-files 2>/dev/null | while IFS= read -r f; do
    [ -f "$f" ] && grep -Iq . "$f" 2>/dev/null && awk -v f="$f" '{ print f "\t" NR "\t" $0 }' "$f"
  done >"$lines_file"
fi

total=0
for r in "${rules[@]}"; do
  id="$(rule_value "$r" id)"
  pattern="$(rule_value "$r" pattern)"
  [ -n "$pattern" ] || continue
  count=0
  # grep the text column once for speed, then check each hit's path against the rule's globs.
  hits="$(cut -f3- "$lines_file" | grep -nE -- "$pattern" 2>/dev/null | cut -d: -f1)"
  [ -n "$hits" ] || continue
  while IFS=$'\t' read -r f ln text; do
    rule_applies "$r" "$f" || continue
    printf '%s %s:%s: %s\n' "$id" "$f" "$ln" "$(printf '%s' "$text" | sed 's/^[[:space:]]*//' | cut -c1-120)"
    count=$((count + 1))
  done < <(HITS="$hits" awk 'BEGIN { n = split(ENVIRON["HITS"], a, "\n"); for (i = 1; i <= n; i++) want[a[i]] = 1 } want[NR]' "$lines_file")
  total=$((total + count))
done

scope="tracked files"
[ "$mode" = diff ] && scope="lines added since $base"
printf '\n%d violation(s) across %d rule(s) in %s\n' "$total" "${#rules[@]}" "$scope"
[ "$total" -eq 0 ]
