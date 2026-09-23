# Design plan: `angel` v0.1.0

This is the plan agreed on 2026-09-23 before building. Where the build differs from the plan, the
difference is noted inline and explained in [LEARNINGS.md](../LEARNINGS.md).

## Context

The bootcamp assignment asks for a personal ADLC plugin with:
- lifecycle skills (spec, plan, implement, review, ship)
- at least one hook that visibly fires
- at least one subagent
- AGENTS.md and a skill that generates CLAUDE.md
- LEARNINGS.md
- a passing `claude plugin validate`

It follows the Elephant/Goldfish model: one orchestrating chat, with fresh-context subagents for
bounded jobs.

**Decisions made with Angel:**
- The plugin is named `angel`.
- The elephant is kept out of source edits by a hook, not just by instructions.
- Artifacts are files under `.adlc/`.
- `doc-audit` does both a drift check and a quality lint.
- `check-pr` has both a pre-push mode and an open-PR mode.

## Components

- **Skills (10):**
  - pipeline: `start` (orchestrator), `spec`, `plan`, `implement`, `review`, `ship`
  - utilities: `check-pr`, `doc-audit`, `make-claude-md`, `retro`
- **Agents (7):** `spec-writer`, `planner`, `implementer` (writers); `spec-reviewer`, `drift-checker`,
  `code-reviewer`, `doc-auditor` (read-only).
- **Hooks (4):** SessionStart `session-start` (elephant memory), PreToolUse `elephant-guard`,
  SubagentStop `goldfish-gate`, Stop `retro-nudge`.
- **State:** `.adlc/ACTIVE` plus `.adlc/<slug>/{state,spec,plan}.md`, `reviews/`, `retro.md`.

## Build order

1. Scaffold, manifests, docs and justfile. Validate passes.
2. Hooks + fixture tests, plus a spike on telling subagent calls from main-session calls.
   *Result: `agent_id`/`agent_type` are present only for subagent calls.*
3. Agents plus `start`, `spec` and `plan`.
4. `implement`, `review` and `ship`.
5. `check-pr`, `doc-audit` (+ `lint-skills.sh`), `make-claude-md` and `retro`.
6. Dogfood on a toy repo, run `doc-audit` on this plugin, and write up LEARNINGS.

**Deviations from the plan:**
- Templates are embedded in the agent bodies instead of `skills/*/`.
- The plugin moved from the repo root into `plugins/angel/`, so the repo's own CLAUDE.md doesn't trip `claude plugin validate`.
- The goldfish-gate also enforces reviewer `VERDICT:` lines.
- The guard gained `.adlc/allow` globs and ignores paths outside the project.

## Verification

- `just check` runs validate + lint + test.
- A live run with `claude --plugin-dir plugins/angel --debug` in a scratch repo, confirming each hook fires.
- Disable HG `adlc` in the scratch repo so the two SessionStart primers don't compete.

## Out of scope for v1

Worktree isolation for parallel implementers, Linear sync, a PostToolUse formatter, and covering
Bash writes in the guard.

## v0.2.0 additions (2026-09-23)

Requested by Angel after v0.1.0 (details and rationale in LEARNINGS.md):
1. `watchtower` renamed to `goldfish-gate`.
2. **Decisions go to the user:**
   - every goldfish report has a `## Decisions needed` section
   - the `decide` skill asks them as AskUserQuestion choice boxes and records them in `decisions.md`
   - the `decision-gate` Stop hook blocks the elephant from ending a turn with decisions pending
3. **Verification:**
   - `discover` (`probe-env.sh` + `repo-scout` → `.adlc/verification.md`)
   - per-slice evidence recipes
   - a `verify` phase with a `verifier` goldfish
   - the `ship-gate` hook (hard gate on `gh pr create`)
4. **Anti-patterns (hybrid):**
   - `antipattern` skill → `.adlc/rules/<id>.md`, plus a native lint rule where possible
   - `antipattern-guard` hook on every agent write
   - `check-antipatterns.sh` (scan / diff / validate)
