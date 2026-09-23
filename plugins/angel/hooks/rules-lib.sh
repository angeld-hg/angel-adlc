#!/usr/bin/env bash
# Anti-pattern rule helpers, shared by hooks/antipattern-guard.sh and
# scripts/check-antipatterns.sh. Pure bash + awk + grep; no jq needed.
#
# A rule is one markdown file in <repo>/.adlc/rules/<id>.md:
#
#   ---
#   id: no-direct-fetch
#   pattern: \bfetch\(            # POSIX extended regex, raw (no YAML escaping)
#   paths: src/**/*.ts, lib/*.ts  # optional, comma-separated globs; default: every file
#   exclude: src/lib/http.ts      # optional, comma-separated globs
#   action: block                 # block (default) or ask
#   ---
#   ## Why
#   ## Instead
#
# Globs match against the repo-relative path. `*` also matches `/`, and `**/`
# is accepted as an alias, so `src/**/*.ts` and `src/*.ts` both match `src/a/b.ts`.

# rules_list <repo root> -> rule file paths, one per line (nothing if none).
rules_list() {
  local dir="$1/.adlc/rules" f
  [ -d "$dir" ] || return 0
  for f in "$dir"/*.md; do
    [ -f "$f" ] && printf '%s\n' "$f"
  done
}

# rule_value <file> <key> -> frontmatter value with surrounding quotes and trailing comment removed.
rule_value() {
  awk -v k="$2" '
    /^---[[:space:]]*$/ { n++; if (n == 2) exit; next }
    n == 1 && index($0, k ":") == 1 {
      v = substr($0, length(k) + 2)
      sub(/^[[:space:]]+/, "", v)
      sub(/[[:space:]]+#[^'"'"'"]*$/, "", v)
      sub(/[[:space:]]+$/, "", v)
      if (v ~ /^'"'"'.*'"'"'$/ || v ~ /^".*"$/) v = substr(v, 2, length(v) - 2)
      print v
      exit
    }
  ' "$1"
}

# rule_section <file> <heading> -> first non-empty paragraph under "## <heading>", joined to one line.
rule_section() {
  awk -v h="$2" '
    $0 ~ "^## " h "[[:space:]]*$" { on = 1; next }
    on && /^## / { exit }
    on && NF == 0 && got { exit }
    on && NF { printf "%s%s", (got ? " " : ""), $0; got = 1 }
  ' "$1"
}

# rule_glob_match <relative path> <comma-separated globs> -> exit 0 if any glob matches.
rule_glob_match() {
  local rel="$1" g
  local -a globs
  # read -a splits on commas without pathname expansion. An unquoted `for g in $globs`
  # would expand `src/**` against the cwd (hooks run from the repo root) and never match.
  IFS=',' read -r -a globs <<<"$2"
  for g in "${globs[@]}"; do
    g="$(printf '%s' "$g" | tr -d '[:space:]')"
    [ -n "$g" ] || continue
    g="${g//\*\*\//}"
    g="${g//\*\*/*}"
    # shellcheck disable=SC2254 # $g is intentionally a pattern
    case "$rel" in
      $g) return 0 ;;
    esac
  done
  return 1
}

# rule_applies <rule file> <relative path> -> exit 0 if the rule covers this path.
rule_applies() {
  local paths exclude
  case "$2" in
    .adlc/*) return 1 ;; # rule files contain their own patterns
  esac
  paths="$(rule_value "$1" paths)"
  exclude="$(rule_value "$1" exclude)"
  if [ -n "$paths" ] && ! rule_glob_match "$2" "$paths"; then
    return 1
  fi
  if [ -n "$exclude" ] && rule_glob_match "$2" "$exclude"; then
    return 1
  fi
  return 0
}

# rule_count <pattern> <text> -> number of matching lines (0 if none).
rule_count() {
  local n
  n="$(printf '%s\n' "$2" | grep -cE -- "$1" 2>/dev/null)"
  printf '%s' "${n:-0}"
}

# rule_first_match <pattern> <text> -> the first matching line, trimmed to 120 chars.
rule_first_match() {
  printf '%s\n' "$2" | grep -m1 -E -- "$1" 2>/dev/null | sed -e 's/^[[:space:]]*//' | cut -c1-120
}

# rule_problems <rule file> -> prints a problem description, or nothing if the rule is valid.
rule_problems() {
  local id pattern action
  id="$(rule_value "$1" id)"
  pattern="$(rule_value "$1" pattern)"
  action="$(rule_value "$1" action)"
  [ -n "$id" ] || { echo "missing 'id'"; return; }
  [ "$id" = "$(basename "$1" .md)" ] || echo "id '$id' doesn't match file name $(basename "$1")"
  [ -n "$pattern" ] || { echo "missing 'pattern'"; return; }
  # grep exits 2 on an invalid regex; 0/1 mean it compiled.
  printf '' | grep -E -- "$pattern" >/dev/null 2>&1
  [ $? -eq 2 ] && echo "pattern is not a valid extended regex: $pattern"
  case "${action:-block}" in
    block | ask) ;;
    *) echo "action must be 'block' or 'ask', got '$action'" ;;
  esac
  [ -n "$(rule_section "$1" Why)" ] || echo "missing a '## Why' section"
  [ -n "$(rule_section "$1" Instead)" ] || echo "missing a '## Instead' section"
}
