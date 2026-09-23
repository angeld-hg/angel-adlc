# AGENTS.md

## Project

`angel` is a personal ADLC (agentic development lifecycle) plugin for Claude Code, built on the
**Elephant/Goldfish** model. One long-lived orchestrator chat (the elephant) holds the feature's
state and talks to the user. Fresh-context subagents (goldfish) do the bounded work: writing the
spec, planning, implementing slices, reviewing. Hooks enforce the split.

The repo root is a one-plugin marketplace (`.claude-plugin/marketplace.json`). The plugin itself
lives in `plugins/angel/`, so this repo's own AGENTS.md, CLAUDE.md, tests and docs never ship
with the plugin.

## Commands

- Test: `just test` (bash fixture tests for every hook and script under `tests/`)
- Lint: `just lint` (`lint-skills.sh` on the plugin and this repo, plus shellcheck if installed)
- Validate: `just validate` (`claude plugin validate` on the marketplace and the plugin)
- All of the above: `just check`, run before every commit
- Try it live: `just dev` from a scratch repo (`claude --plugin-dir <this repo>/plugins/angel`),
  then `/reload-plugins` after edits. Use `claude --debug` to see hooks fire.

Requires `bash`, `jq`, `just`, and `gh` (for check-pr/ship).

## Layout

- `.claude-plugin/marketplace.json`: the marketplace, pointing at `./plugins/angel`
- `plugins/angel/`: the plugin (paths below are relative to it)
  - `.claude-plugin/plugin.json`: the manifest
  - `skills/<name>/SKILL.md`: the elephant's playbooks. Each is invocable as `/angel:<name>`.
    - pipeline: `start` (the orchestrator), `discover`, `spec`, `plan`, `implement`, `verify`,
      `review`, `ship`
    - cross-cutting: `decide` (user choices via AskUserQuestion), `antipattern` (ban a pattern)
    - utilities: `check-pr`, `doc-audit`, `make-claude-md`, `retro`
  - `agents/*.md`: goldfish definitions.
    - writers: `spec-writer`, `planner`, `implementer`, `repo-scout`
    - read-only (no Write/Edit): `spec-reviewer`, `drift-checker`, `code-reviewer`, `doc-auditor`,
      `verifier`
  - `hooks/hooks.json` plus `hooks/*.sh`. All of them source `hooks/lib.sh`; the rule hooks also
    source `hooks/rules-lib.sh`.
    - SessionStart: `session-start` (elephant memory)
    - PreToolUse: `elephant-guard` and `antipattern-guard` (on Edit/Write), `ship-gate` (on Bash)
    - SubagentStop: `goldfish-gate`
    - Stop: `decision-gate`, `retro-nudge`
  - `scripts/`:
    - `lint-skills.sh`: doc-audit checks
    - `probe-env.sh`: discover's environment facts
    - `check-antipatterns.sh`: rule scan, diff and validate modes
- `tests/`: `run.sh`, `helpers.sh`, `hooks/test_*.sh`, `scripts/test_*.sh`
- `docs/PLAN.md`: the original design plan. `LEARNINGS.md`: the decision log (keep it current).

## Conventions

- **Hooks fail open.** A missing `jq` or bad input means exit 0, never a broken session. Every output
  goes through the `angel_*` emitters in `hooks/lib.sh`.
- **Hooks are silent outside opted-in repos.** A target repo opts in by having a `.adlc/` directory.
  One exception: the goldfish-gate's report checks (a `## Decisions needed` section and a `VERDICT:`
  line) apply to angel's reviewer agents everywhere. They only ever affect those agents, and
  `/angel:check-pr` and `/angel:doc-audit` gate on them even in repos without `.adlc/`.
- **Every hook behavior has a fixture test.** Add the test first (`tests/hooks/test_<hook>.sh`, built
  on `new_project` and `with_feature` from `tests/helpers.sh`), watch it fail, then change the hook.
  `run_hook` runs hooks from the project root, like Claude Code does. Keep it that way, because
  cwd-sensitive bugs only show up there.
- **Never word-split untrusted strings unquoted** in hooks (`for x in $var`). Bash also expands
  globs against the cwd. Split with `IFS=, read -r -a`.
- **Skill and agent descriptions are the router.** They say what, when to use, and when not to use,
  and `lint-skills.sh` enforces this. Keep bodies imperative and under 500 lines.
- Goldfish are always handed **paths and a mode, never summaries**.
- **Lasting choices go to the user.** Every goldfish report that can surface a choice has a
  `## Decisions needed` section. The elephant runs `decide` on it and never picks for the user.
- Agents reference each other as `angel:<agent>`. Hooks strip the `angel:` prefix from `agent_type`.
- Artifacts in target repos:
  - `.adlc/ACTIVE` holds the current slug.
  - Per feature, in `.adlc/<slug>/`: `state.md`, `spec.md`, `plan.md`, `decisions.md`,
    `reviews/` (including `verification.md`), `evidence/`, `pr-body.md`, `retro.md`.
  - Repo-wide, directly in `.adlc/`: `verification.md` (profile), `probe.md`, `rules/*.md`
    (anti-patterns), `allow` (guard globs), `doc-audit-<date>.md`.

## Workflow

- Record every design decision or reversal in `LEARNINGS.md` (dated, with the why).
- Bump `version` in both manifests when behavior changes.
