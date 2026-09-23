---
name: antipattern
description: Bans a code pattern in this repo so agents stop copying it. Writes an angel rule (.adlc/rules/<id>.md - regex, why, what to do instead) that a hook enforces on every agent write, and where the repo's own linter can express it (ESLint, ruff, semgrep, golangci-lint...), adds a native lint rule too so humans and CI get it. Use when a bad pattern bit you and you don't want any agent repeating it, when a reviewer tags a [rule-candidate], or during a retro ("/angel:antipattern no raw SQL in handlers"). Do not use for style a formatter already handles, for one-off bugs that aren't patterns, or for process rules (those belong in AGENTS.md or a hook).
argument-hint: "<description of the bad pattern> [example path:line]"
---

# Antipattern: stop agents copying a bad pattern

Agents learn from the code around them. One bad pattern that survives in the codebase gets copied
by every future agent that reads nearby files. This skill turns "we don't do that here" into
something enforced.

Input: `$ARGUMENTS`: what's wrong, and ideally an example location.

## 1. Pin down the pattern

Read the example (or find one with Grep). Then settle four things, asking the user with
AskUserQuestion wherever the input doesn't already answer them (recommended option first):
- **What exactly is banned:** the syntactic shape, e.g. `db.query(` called outside `src/repo/`.
- **Scope:** which paths it applies to, and legitimate exceptions (the one wrapper that's allowed
  to do it).
- **Instead:** the approved pattern, with a path to a good example in this repo.
- **Strictness:** `block` (the default: the write is refused) or `ask` (the user approves each
  occurrence).

## 2. Draft and test the regex

Write a POSIX extended regex (it runs through `grep -E`; `\b` word boundaries work). Test it
against the whole repo before saving anything, using a temporary rule:
1. Write the draft to `.adlc/rules/<id>.md` (format below).
2. Run `bash "${CLAUDE_PLUGIN_ROOT}/scripts/check-antipatterns.sh" --rule <id>`.
3. Check that it catches the known example, and read every other hit. False positives mean the
   regex or the `paths`/`exclude` globs need tightening; iterate until the hits are real.
4. Run `check-antipatterns.sh --validate`.

Show the user the final regex, the hit count, and up to 5 sample hits.

## 3. The rule file

`.adlc/rules/<id>.md` (the id is kebab-case and must match the file name):

```markdown
---
id: no-raw-sql-in-handlers
pattern: \bdb\.(query|execute)\(
paths: src/handlers/**
exclude: src/handlers/legacy/**
action: block
---
# No raw SQL in handlers

## Why
<the incident or reason, in 1-3 sentences. The hook shows this to the agent it blocks.>

## Instead
<the approved pattern and a path to a good example. The hook shows this too.>

## Origin
<YYYY-MM-DD>: added via /angel:antipattern after <incident>. Existing occurrences: <n> (see below).
```

Notes:
- The pattern is raw: no YAML escaping. Quote it with single quotes if it contains ` #`.
- In `paths`, `*` also matches `/`.

From now on, the `antipattern-guard` hook refuses any Edit/Write, from the elephant or any goldfish,
that **adds** a match. Edits that leave an existing match alone are allowed, so legacy code stays
editable.

## 4. Native linter (hybrid)

Detect the repo's linter from `.adlc/verification.md` or the config files:

| Linter | Config | Typical encoding |
|---|---|---|
| ESLint | `eslint.config.*`, `.eslintrc*` | `no-restricted-syntax` (AST selector), `no-restricted-imports`, `no-restricted-properties` |
| ruff | `pyproject.toml [tool.ruff]`, `ruff.toml` | `flake8-tidy-imports.banned-api` (TID251) |
| semgrep | `.semgrep.yml`, `.semgrep/` | a `pattern:` rule, which can express most shapes |
| golangci-lint | `.golangci.yml` | `forbidigo` |
| RuboCop | `.rubocop.yml` | a `Style`/custom cop, or semgrep |

If the linter can express the rule well (AST-based is better than regex):
1. Draft the native config change and show it to the user with AskUserQuestion: add it / angel rule only.
2. On "add it", dispatch `angel:implementer` with the rule file path and the drafted change. The
   elephant can't edit config files.
3. Run the linter to confirm the rule fires on the known example.
4. Add a line to the rule file: `Native: <linter> <rule name> in <config file>`.

If the linter can't express it, or there's no linter, the angel rule alone is fine. Say so in the Origin line.

## 5. Existing occurrences

The baseline scan found `<n>` existing matches. Ask the user (recommended first):
- **Clean up now:** start a chore feature with `/angel:start` whose spec is "remove all
  occurrences of <id>".
- **Grandfather them:** add the legacy paths to `exclude`.
- **Leave them:** the hook already allows edits that don't add new matches.

## 6. Record

Mention the new rule in the project's `LEARNINGS.md` if it has one (via implementer, or via
`.adlc/allow`), and in state.md's decision log if a feature is active. `/angel:check-pr` runs
`check-antipatterns.sh --diff` on every branch, which also catches matches written through Bash,
where the hook can't see them.
