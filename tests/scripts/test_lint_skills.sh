#!/usr/bin/env bash
source "$(dirname "$0")/../helpers.sh"

lint() { bash "$PLUGIN_ROOT/scripts/lint-skills.sh" "$1" 2>&1; }

new_project; p="$CLAUDE_PROJECT_DIR"
mkdir -p "$p/skills/good" "$p/skills/bad" "$p/skills/vague" "$p/agents"

cat >"$p/skills/good/SKILL.md" <<'EOF'
---
name: good
description: Does a clearly described thing for the project. Use when the user asks for the thing. Do not use for other things.
---
Body.
EOF
out="$(lint "$p")"; code=$?
assert_contains "a well-formed skill produces no errors" "$out" "0 error(s)"
[ "$code" -eq 0 ] && pass "exit code 0 when clean" || fail "exit code 0 when clean" "got $code"

printf 'no frontmatter here\n' >"$p/skills/bad/SKILL.md"
out="$(lint "$p")"; code=$?
assert_contains "missing frontmatter is an error" "$out" "ERROR skills/bad/SKILL.md: no YAML frontmatter"
[ "$code" -eq 1 ] && pass "exit code 1 on errors" || fail "exit code 1 on errors" "got $code"
rm "$p/skills/bad/SKILL.md"

cat >"$p/skills/vague/SKILL.md" <<'EOF'
---
name: vague
description: Helps with stuff in a general way for many different situations and needs.
---
EOF
out="$(lint "$p")"
assert_contains "description without 'use when' is an error" "$out" "doesn't say when to use it"
assert_contains "description without a negative example is a warning" "$out" "WARN  skills/vague/SKILL.md: description has no negative"

cat >"$p/skills/vague/SKILL.md" <<'EOF'
---
name: other-name
description: Does a clearly described thing for the project. Use when needed. Do not use otherwise.
---
EOF
out="$(lint "$p")"
assert_contains "name/directory mismatch is flagged" "$out" "doesn't match its directory"

{ printf -- '---\nname: vague\ndescription: Does a clearly described thing for the project. Use when needed. Do not use otherwise.\n---\n'; seq 1 520; } >"$p/skills/vague/SKILL.md"
assert_contains "bodies over 500 lines are an error" "$(lint "$p")" "keep bodies under 500"
rm -r "$p/skills/vague"

printf -- '---\nname: helper\ndescription: A helper agent that does one bounded job for the orchestrator.\n---\n' >"$p/agents/helper.md"
assert_contains "agent without a negative example is warned" "$(lint "$p")" "agent description doesn't say when not to use it"

printf '# Agents\n' >"$p/AGENTS.md"
assert_contains "AGENTS.md without CLAUDE.md is warned" "$(lint "$p")" "CLAUDE.md: missing"
printf '# Claude\n' >"$p/CLAUDE.md"
assert_contains "CLAUDE.md that doesn't import AGENTS.md is warned" "$(lint "$p")" "doesn't import it"
printf '@AGENTS.md\n' >"$p/CLAUDE.md"
out="$(lint "$p")"
if grep -q "CLAUDE.md" <<<"$out"; then fail "thin CLAUDE.md passes" "$out"; else pass "thin CLAUDE.md passes"; fi

mkdir -p "$p/node_modules/pkg/skills/x"
printf 'junk\n' >"$p/node_modules/pkg/skills/x/SKILL.md"
out="$(lint "$p")"
if grep -q node_modules <<<"$out"; then fail "node_modules is skipped" "$out"; else pass "node_modules is skipped"; fi

rm -rf "$p"
finish
