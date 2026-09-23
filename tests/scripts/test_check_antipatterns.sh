#!/usr/bin/env bash
source "$(dirname "$0")/../helpers.sh"

check() { (cd "$p" && bash "$PLUGIN_ROOT/scripts/check-antipatterns.sh" "$@" 2>&1); }

new_project; p="$CLAUDE_PROJECT_DIR"
(cd "$p" && git init -q -b main . && git config user.email t@t && git config user.name t)

assert_contains "no rules: says how to create one" "$(check)" "/angel:antipattern"

mkdir -p "$p/.adlc/rules" "$p/src/lib"
cat >"$p/.adlc/rules/no-direct-fetch.md" <<'EOF'
---
id: no-direct-fetch
pattern: \bfetch\(
paths: src/**
exclude: src/lib/http.ts
---
## Why
Skips auth.

## Instead
Use src/lib/http.ts.
EOF
printf 'import x\nconst a = fetch(u)\n' >"$p/src/old.ts"
printf 'export const get = (u) => fetch(u)\n' >"$p/src/lib/http.ts"
printf 'nothing to see\n' >"$p/src/clean.ts"
(cd "$p" && git add -A && git commit -qm base)

out="$(check)"; code=$?
assert_contains "full scan reports existing violations with path:line" "$out" "no-direct-fetch src/old.ts:2:"
if grep -q "http.ts" <<<"$out"; then fail "excluded files are not reported" "$out"; else pass "excluded files are not reported"; fi
if grep -q "rules/no-direct-fetch.md" <<<"$out"; then fail "rule files are not reported" "$out"; else pass "rule files are not reported"; fi
[ "$code" -eq 1 ] && pass "exit 1 when violations exist" || fail "exit 1 when violations exist" "got $code"

(cd "$p" && git switch -qc feature)
out="$(check --diff main)"; code=$?
assert_contains "diff mode with no changes is clean" "$out" "0 violation(s)"
[ "$code" -eq 0 ] && pass "exit 0 when clean" || fail "exit 0 when clean" "got $code"

printf 'nothing to see\nconst b = fetch(v)\n' >"$p/src/clean.ts"
printf 'fetch(1)\n' >"$p/src/new.ts"
out="$(check --diff main)"
assert_contains "diff mode catches uncommitted added lines with the right line number" "$out" "src/clean.ts:2:"
assert_contains "diff mode catches untracked files" "$out" "src/new.ts:1:"
if grep -q "src/old.ts" <<<"$out"; then fail "diff mode ignores pre-existing violations" "$out"; else pass "diff mode ignores pre-existing violations"; fi

assert_contains "validate passes a good rule" "$(check --validate)" "0 invalid"
printf -- '---\nid: wrong-name\npattern: (unclosed\naction: nope\n---\n' >"$p/.adlc/rules/bad.md"
out="$(check --validate)"; code=$?
assert_contains "validate flags id/file mismatch" "$out" "doesn't match file name"
assert_contains "validate flags an invalid regex" "$out" "not a valid extended regex"
assert_contains "validate flags a bad action" "$out" "action must be"
assert_contains "validate flags missing Why/Instead" "$out" "## Why"
[ "$code" -eq 1 ] && pass "validate exits 1 on invalid rules" || fail "validate exits 1 on invalid rules" "got $code"

out="$(check --rule no-direct-fetch)"
assert_contains "--rule restricts the scan to one rule" "$out" "across 1 rule(s)"

rm -rf "$p"
finish
