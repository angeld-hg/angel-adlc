# angel: Elephant/Goldfish ADLC for Claude Code

A personal agentic development lifecycle plugin. You talk to **one** chat, the elephant. It takes a
feature from idea to PR by sending each bounded job to a fresh-context subagent (a goldfish).
- Every lasting choice comes to **you** as a multiple-choice prompt.
- Nothing ships without **evidence** that it works.
- Patterns you've banned can't be written by any agent.
- You get short plain-words digests and live progress updates, with everything named
  (`export-button`, not S1).
- Tests are end to end first and few, and each verification leaves something you can re-run.

```
You ⇄ ELEPHANT (/angel:start)       owns .adlc/<slug>/state.md, asks you every lasting choice
        ├─► repo-scout    → .adlc/verification.md       (first run: how is anything proven here?)
        ├─► spec-writer   → spec.md → spec-reviewer     (report only)
        ├─► planner       → plan.md → drift-checker     (report only, plan vs spec)
        ├─► implementer ×N                              one per slice, parallel when files don't overlap
        ├─► verifier      → evidence per AC             (report only; ship-gate needs VERIFIED)
        ├─► code-reviewer ∥ drift-checker               (report only, diff vs spec + plan)
        └─► ship → PR (you merge)

   any "Decisions needed" from any goldfish ─► /angel:decide ─► choice boxes ─► decisions.md
```

## Install

```bash
# from a clone of this repo
claude plugin marketplace add /path/to/angel-adlc
claude plugin install angel@angel-marketplace

# or, for development, load straight from the working tree
claude --plugin-dir /path/to/angel-adlc/plugins/angel
```

In a new repo, run `/angel:discover` (or just `/angel:start`, which runs it first), then
`/angel:make-claude-md` if there's no AGENTS.md.

## Commands

| Command | What it does |
|---|---|
| `/angel:start <idea>` | Run the whole pipeline with gates. No argument resumes the active feature. |
| `/angel:discover` | Probe the repo and machine: what the repo is, which CLIs and auth work, which commands really run, and **how to prove a change works here** → `.adlc/verification.md` |
| `/angel:spec` | Idea → reviewed `spec.md` (WHAT and WHY, testable ACs) |
| `/angel:plan` | Spec → `plan.md` (slices, file ownership, contracts, an evidence recipe per slice) + drift audit |
| `/angel:implement` | One implementer per named work item, in parallel waves where safe. Tells you in plain words what each one is doing and posts a short update at every milestone. |
| `/angel:verify` | The verifier proves every criterion end to end, captures screenshots, and leaves a re-runnable artifact (`rerun.sh`, results, coverage). Failures loop to implementers; unverifiable criteria become your decisions. |
| `/angel:review` | code-reviewer ∥ drift-checker on the diff. Fixes go to implementers, architecture calls come to you. |
| `/angel:check-pr` | Pre-push GO / NO-GO (tests, review, drift, verification, anti-patterns, open decisions), or blockers on an open PR |
| `/angel:ship` | Push and open a short PR: why, what changed, brief evidence, screenshots, detailed how to test (user-invoked only; never merges) |
| `/angel:decide` | Walk pending decisions as choice boxes, recommendation first, following up on new branches (grill-me style). `grill <topic>` interviews you. |
| `/angel:antipattern <what>` | Ban a code pattern: an angel rule every agent write is checked against, plus a native lint rule (ESLint, ruff, semgrep...) where possible |
| `/angel:doc-audit` | Lint script + doc-auditor: are AGENTS.md, CLAUDE.md and skills still true? |
| `/angel:make-claude-md` | Generate AGENTS.md + a thin CLAUDE.md for any repo |
| `/angel:retro` | Turn friction into skill, agent, hook, rule or doc edits; log them in LEARNINGS.md |

## Hooks

All are silent unless the repo has a `.adlc/` folder (created by `/angel:start` or `/angel:discover`),
except the reviewer checks in goldfish-gate and reviewer-write-guard, which only affect angel's reviewer agents.

| Hook | Event | What you'll see |
|---|---|---|
| session-start | SessionStart | A new session knows the active feature, phase, next step, pending decisions, banned patterns and whether a verification profile exists |
| elephant-guard | PreToolUse (Edit/Write) | The main chat is denied edits outside `.adlc/` and told to delegate to `implementer` |
| reviewer-write-guard | PreToolUse (Edit/Write) | spec-reviewer, drift-checker, code-reviewer and verifier can write only their own report in `.adlc/<slug>/reviews/` (the verifier also `evidence/`, including e2e artifacts and screenshots). Applies in every repo. |
| antipattern-guard | PreToolUse (Edit/Write) | **Any** agent adding a banned pattern is refused and told why and what to use instead. Existing occurrences don't block unrelated edits. |
| ship-gate | PreToolUse (Bash) | `gh pr create` is denied until the feature's verification says `VERIFIED`, or you've waived it |
| goldfish-gate | SubagentStop | A goldfish is sent back if its deliverable is missing (spec, plan or profile file; the "In plain words" digest; `## Decisions needed`; evidence; a `VERDICT:` line; an implementer's final milestone in progress.log) or if it labels things S1, D12 or AC3 instead of naming them |
| decision-gate | Stop | The elephant can't end its turn while decisions are pending. It has to ask you, or you defer them. |
| retro-nudge | Stop | Once per session, after a feature ships without a retro, you're asked to run `/angel:retro` |

**Escape hatches:**
- Add globs to `.adlc/allow` (for example `*.md`) to let the elephant edit those paths.
- Start Claude with `ANGEL_ALLOW_MAIN_EDITS=1` to turn the elephant-guard off for a session.
- Add a path to a rule's `exclude` to allow a legitimate exception.

## What lands in your repo

```
.adlc/
  verification.md         how to prove things work here (from /angel:discover)
  probe.md                raw environment facts
  rules/<id>.md           banned patterns: regex + why + instead
  allow                   optional: globs the elephant may edit
  ACTIVE                  slug of the feature in flight
  <slug>/
    state.md              phase, next step, dated decision log
    spec.md  plan.md      both open with an "In plain words" digest
    decisions.md          every lasting choice: options, recommendation, your answer
    reviews/              spec-review, plan-drift, verification, code-review, diff-drift, check-pr
    progress.log          implementer milestones, streamed to you as live updates
    evidence/e2e/<time>/  repeatable e2e artifact: rerun.sh, results, coverage.txt
    evidence/screenshots/ one per visible change, linked from the PR
    pr-body.md  retro.md
```

Commit it: the reasoning, decisions and evidence behind a feature then travel with its code.

## Develop

`just check` runs validate + lint + test. See [AGENTS.md](AGENTS.md) for layout and conventions,
[LEARNINGS.md](LEARNINGS.md) for why things are the way they are, and [docs/PLAN.md](docs/PLAN.md)
for the original design.
