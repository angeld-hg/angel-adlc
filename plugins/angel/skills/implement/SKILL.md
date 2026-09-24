---
name: implement
description: Phase 3 of the angel ADLC. Executes plan.md slice by slice by dispatching one implementer goldfish per slice (several at once for parallel-safe slices), then verifies each result itself before moving on. Use after the plan is approved, or when /angel:start reaches the implement phase. Do not use without an approved plan.md, or for a single tiny edit (just ask for it directly).
argument-hint: "[slug] [slice ids, e.g. S2 S3]"
---

# Implement phase

Input: `$ARGUMENTS`: a slug (or empty for `.adlc/ACTIVE`) and optionally the slice ids to run.

Precondition: `.adlc/<slug>/plan.md` exists and was approved. Work on a feature branch: if you're on
`main`, create `angel/<slug>` first (`git switch -c angel/<slug>`).

## 1. Schedule

Read the `## Slices` section of plan.md and group the slices into **waves**:
- A slice is ready when everything in its `Depends on` list is DONE.
- Ready slices marked `Parallel: yes` whose file lists don't overlap run together in one wave.
- Everything else runs alone.

Record the schedule in state.md's `next:` field ("wave 1: S1+S2, wave 2: S3").

## 2. Dispatch a wave

Send **one message with one Agent call per slice** so they run concurrently. Each gets:
- `subagent_type: angel:implementer`
- the feature folder path and the slice id. It reads its slice from plan.md. Also pass
  per-slice environment facts it can't know: which ports or DB path to use for e2e so that
  parallel slices don't collide, and which other slices are running. Never pass summaries of the
  spec or plan.

Run at most 2 slices that execute e2e at the same time; load makes timing-based tests flaky. If a
wave has more, split it.

## 3. Check the work (don't trust, check)

When the wave returns, for each report:
- `BLOCKED` with a design fork: follow `angel:decide` (it's the user's call), then re-dispatch with
  the decisions.md path. Other blockers usually mean re-planning (`/angel:plan`).
- `DONE`: check it yourself with read-only commands.
  - `git status` should show only the slice's files changed.
  - The test command should pass (`just test`, or whatever AGENTS.md says).
  - The report should include the output of the slice's **Evidence** recipe. If it doesn't, send it back.
- Files changed outside the slice's ownership: flag it and ask the user whether to keep or revert.
- If `.adlc/rules/` has rules, run `bash "${CLAUDE_PLUGIN_ROOT}/scripts/check-antipatterns.sh" --diff <base>`.
  This catches banned patterns written through Bash, where the hook can't see them. Send any hits
  back to the implementer.

Log each slice in state.md ("S1 DONE, 4 tests, evidence: curl 200"). Commit per wave with a message
naming the slices, unless the user prefers otherwise.

## 4. Stalls

If an implementer is killed by the watchdog, check `git status` for partial work and leftover
processes (stop any server or test runner it left behind), then resume the same agent once with
SendMessage. If it stalls again, split the slice into smaller parts with disjoint files and dispatch
fresh agents. Record the split in state.md.

## 5. Next wave, then gate

Repeat until every slice is DONE. Then tell the user: slices done, tests added, anything deviating
from the plan. Ask: continue to verification / stop.

On continue, update state.md: `phase: verify`, `next: run /angel:verify`.
