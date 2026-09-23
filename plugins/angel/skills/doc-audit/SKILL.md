---
name: doc-audit
description: Audits agent-facing docs (AGENTS.md, CLAUDE.md, skills, agents) in two passes - a deterministic lint script (frontmatter, description quality, the 500-line limit, CLAUDE.md size) and a doc-auditor goldfish that checks every command, path and convention against the real repo. Use when agent docs may be stale, after a refactor or rename, before sharing a plugin, or periodically ("/angel:doc-audit"). Do not use for user-facing docs such as READMEs or API references, or to write a CLAUDE.md from scratch (use /angel:make-claude-md).
argument-hint: "[path, default repo root]"
---

# Doc audit

Input: `$ARGUMENTS` (a path to audit, default: the repo root)

## 1. Deterministic lint (script, not judgement)

Run:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/lint-skills.sh" <path>
```

It checks every `SKILL.md` and `agents/*.md` it finds, plus CLAUDE.md and AGENTS.md:
- Frontmatter present, with `name` and `description`.
- Skill descriptions that say when to use ("Use when" / "Use after" / "Use to" / "Use for") and when
  not to ("Do not" / "Don't").
- Bodies under 500 lines.
- CLAUDE.md under 200 lines, and importing AGENTS.md when both exist.

It exits non-zero when it finds errors. Keep its output for step 2.

## 2. Drift and quality review (goldfish)

Dispatch `angel:doc-auditor` with the repo root and the lint output pasted verbatim (lint output is
data, not a summary, so passing it is fine).

## 3. Report

Save the combined result to `.adlc/doc-audit-<YYYY-MM-DD>.md` if `.adlc/` exists; otherwise just show it.
Show the user the top 5 findings and the verdict.

Offer to apply the fixes. In an angel repo, doc files outside `.adlc/` are guarded, so either dispatch
`angel:implementer` with the report path, or have the user add `*.md` to `.adlc/allow`. Never apply
fixes without the user's go-ahead: these files steer every future session.
