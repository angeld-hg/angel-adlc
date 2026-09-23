---
name: make-claude-md
description: Generates a portable AGENTS.md (the source of truth for any coding agent) and a thin CLAUDE.md that imports it, for any project, by detecting the stack, commands and conventions from the repo itself, then has doc-auditor verify the result. Use when setting up a repo for agentic work, when a project has no AGENTS.md/CLAUDE.md, or after installing the angel plugin ("/angel:make-claude-md"). Do not use to audit existing docs (use /angel:doc-audit), or to overwrite a hand-written CLAUDE.md without asking.
argument-hint: "[--force]"
---

# Make CLAUDE.md (and AGENTS.md)

Plugins can't ship a CLAUDE.md, so this skill writes one for the project you're in.
**AGENTS.md is the portable base** that Cursor, Codex and others read. CLAUDE.md is a thin layer that
imports it and adds only Claude-specific notes.

## 1. Check what exists

- If `AGENTS.md` or `CLAUDE.md` exists and `--force` wasn't given, show the user what's there and ask:
  merge into it / replace / stop. Default to merge: never discard hand-written rules silently.

## 2. Detect (read-only)

Gather facts; don't guess:
- **Stack:** manifest files (package.json, pyproject.toml, go.mod, Cargo.toml, pom.xml, *.csproj, Gemfile).
- **Commands:** `just --list`, package.json `scripts`, Makefile targets, and pyproject tool sections.
  Record the exact commands for install, test, lint, format, build and run.
- **Layout:** top-level dirs and what they hold (skim 1-2 files each). Note generated or vendored dirs
  that must not be edited.
- **Conventions:** test file naming and location, and the formatter or linter configs. Spot-check 2-3
  source files for naming and error handling.
- **Workflow:** CI config (.github/workflows), branch naming from `git log`, PR template.

## 3. Write AGENTS.md

Keep it under ~150 lines. Only write what an agent would get wrong without being told.

```markdown
# AGENTS.md

## Project
<One paragraph: what this is and who uses it.>

## Commands
- Install: `...`
- Test: `...` (single test: `...`)
- Lint / format: `...`
- Run: `...`

## Layout
- `src/` - ...
- `generated/` - do not edit, regenerate with `...`

## Conventions
- <only non-obvious, verified rules>

## Workflow
- Branches: `...`; PRs: <template/expectations>
```

## 4. Write CLAUDE.md

```markdown
@AGENTS.md

## Claude Code notes
- <Claude-specific only, e.g. "Use the angel plugin: /angel:start for features.">
```

Keep it under 30 lines. If you're tempted to add a rule here, ask whether it belongs in AGENTS.md
(any agent needs it), a skill (a procedure), or a hook (it must always happen).

## 5. Verify

Dispatch `angel:doc-auditor` with the repo root to check the new files against the repo. Apply any
drift fixes it finds, then show the user both files. In an angel repo, the elephant-guard hook blocks
the main session from writing these files: either add `AGENTS.md` and `CLAUDE.md` to `.adlc/allow`
with the user's OK, or dispatch `angel:implementer` to write them.
