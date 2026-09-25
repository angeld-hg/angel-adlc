#!/usr/bin/env bash
source "$(dirname "$0")/../helpers.sh"

new_project; p="$CLAUDE_PROJECT_DIR"
(cd "$p" && git init -q -b main .)
cat >"$p/package.json" <<'EOF'
{"name": "demo", "scripts": {"test": "vitest run", "dev": "vite --port 5173", "e2e": "playwright test"}, "devDependencies": {"@vitest/coverage-v8": "^2.0.0", "@playwright/test": "^1.50.0"}}
EOF
printf 'test:\n    npm test\n' >"$p/justfile"
printf 'import { defineConfig } from "vitest/config"\n' >"$p/vitest.config.ts"
mkdir -p "$p/.github/workflows" "$p/tests"
printf 'name: CI\non: push\njobs:\n  t:\n    steps:\n      - run: npm test\n' >"$p/.github/workflows/ci.yml"
printf 'SECRET=should-never-appear\n' >"$p/.env"

out="$(bash "$PLUGIN_ROOT/scripts/probe-env.sh" "$p" 2>&1)"
assert_contains "names the repo" "$out" "# Environment probe: $(basename "$p")"
assert_contains "detects the Node stack" "$out" '`package.json`: Node.js'
assert_contains "lists package.json scripts" "$out" '`test`: vitest run'
assert_contains "lists just recipes" "$out" "test"
assert_contains "finds test config" "$out" "vitest.config.ts"
assert_contains "finds the test directory" "$out" "Test directories: tests"
assert_contains "summarises CI workflows" "$out" "ci.yml"
assert_contains "notes the dev server command" "$out" "npm run dev"
assert_contains "lists env files" "$out" "Env files present (contents not read): .env"
if grep -q "should-never-appear" <<<"$out"; then
  fail "never prints .env contents" "$out"
else
  pass "never prints .env contents"
fi
assert_contains "has a CLI table" "$out" "| CLI | Installed | Version | Repo needs it |"
assert_contains "detects coverage tooling" "$out" "Coverage tooling: @vitest/coverage-v8"
assert_contains "detects an e2e harness" "$out" "E2E harness: @playwright/test"

rm -rf "$p"
finish
