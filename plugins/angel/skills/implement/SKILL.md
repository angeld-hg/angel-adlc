---
name: implement
description: Phase 3 of the angel ADLC. Executes plan.md work item by work item by dispatching one implementer goldfish per named slice (several at once for parallel-safe ones), tells the user in plain words what each implementer is doing, streams their milestones from progress.log as small live updates, then checks each result itself before moving on. Use after the plan is approved, or when /angel:start reaches the implement phase. Do not use without an approved plan.md, or for a single tiny edit (just ask for it directly).
argument-hint: "[slug] [work item names, e.g. export-button csv-streaming]"
---

# Implement phase

Input: `$ARGUMENTS`: a slug (or empty for `.adlc/ACTIVE`) and optionally the work item names to run.

Precondition: `.adlc/<slug>/plan.md` exists and was approved. Work on a feature branch: if you're on
`main`, create `angel/<slug>` first (`git switch -c angel/<slug>`).

Everywhere below, refer to work items by their names from plan.md (`export-button`), never by
numbers or labels.

## 1. Schedule

Read the `## Slices` section of plan.md and group the work items into **waves**:
- A work item is ready when everything in its `Depends on` list is DONE.
- Ready items marked `Parallel: yes` whose file lists don't overlap run together in one wave.
- Everything else runs alone.
- At most 2 items that run e2e scenarios at the same time; load makes timing-based tests flaky.

Record the schedule in state.md's `next:` field ("first: export-button + csv-streaming, then:
export-permissions").

## 2. Tell the user what's about to happen

Before dispatching, post one short message, using each item's "In plain words" line from plan.md:

```
Starting 2 pieces of work in parallel:
- export-button: adds an Export button to the report page that downloads the report
- csv-streaming: makes large reports download without freezing the page
Next up after these: export-permissions. I'll post short updates as each one hits a milestone.
```

## 3. Start the progress stream, then dispatch

1. Create the log and start watching it with the Monitor tool, so each milestone line the
   implementers write reaches you as a notification:
   - command: `touch .adlc/<slug>/progress.log && tail -n 0 -F .adlc/<slug>/progress.log`
   - description: `progress for <slug>`
   - timeout_ms: 1800000. Re-arm it when it expires while the wave is still running; stop it with
     TaskStop when the wave is done.
2. Send **one message with one Agent call per work item** so they run concurrently. Each gets:
   - `subagent_type: angel:implementer`
   - the feature folder path and the work item's name. It reads its slice from plan.md.
   - per-item environment facts it can't know: which ports or DB path to use for e2e so that
     parallel items don't collide, and which other items are running. Never pass summaries of the
     spec or plan.

**Relaying progress:** implementers log `started`, `test-failing`, `passing`, `evidence`, then `done`
or `blocked`. When milestone lines arrive, give the user one short update per batch, one line per
item, in plain words:

```
export-button: the end-to-end test for the Export button is written and failing as expected (2 of 5)
csv-streaming: large-report download now works; capturing evidence (4 of 5)
```

Keep it to the milestone and what it means. Don't paste logs. A `blocked` line gets relayed
immediately, together with what you're going to do about it.

## 4. Check the work (don't trust, check)

When an implementer returns, for each report:
- `BLOCKED` with a design fork: follow `angel:decide` (it's the user's call), then re-dispatch with
  the decisions.md path. Other blockers usually mean re-planning (`/angel:plan`).
- `DONE`: check it yourself with read-only commands.
  - `git status` should show only the item's files changed.
  - The test command should pass (`just test`, or whatever AGENTS.md says).
  - The report should include the output of the item's **Evidence** recipe and its e2e scenario.
    If it doesn't, send it back.
  - Many new tests for one item, or tests of private helpers: send it back to collapse them into
    the scenario. The user wants few, high-signal tests.
- Files changed outside the item's ownership: flag it and ask the user whether to keep or revert.
- If `.adlc/rules/` has rules, run `bash "${CLAUDE_PLUGIN_ROOT}/scripts/check-antipatterns.sh" --diff <base>`.
  This catches banned patterns written through Bash, where the hook can't see them. Send any hits
  back to the implementer.

Log each item in state.md ("export-button DONE: 1 e2e scenario, evidence: download works"). Commit
per wave with a message naming the work items, unless the user prefers otherwise.

## 5. Stalls

If an implementer is killed by the watchdog, check `git status` for partial work and leftover
processes (stop any server or test runner it left behind), then resume the same agent once with
SendMessage. If it stalls again, split the item into smaller parts with disjoint files and dispatch
fresh agents. Record the split in state.md and tell the user in one line.

## 6. Next wave, then gate

Repeat until every work item is DONE. Then stop the progress monitor and give the user a digest:

```
All 3 pieces of work are done:
- export-button: Export button downloads the report (end-to-end test passes)
- csv-streaming: 50k-row reports download in under 2 seconds
- export-permissions: only editors see the button
Changed from the plan: <nothing | one line>
Next: verification. Continue?
```

Ask: continue to verification / stop. On continue, update state.md: `phase: verify`,
`next: run /angel:verify`.
