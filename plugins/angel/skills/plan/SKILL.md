---
name: plan
description: Phase 2 of the angel ADLC. Turns an approved spec.md into .adlc/<slug>/plan.md (vertical slices with file ownership, contracts and a test strategy) via the planner goldfish, then audits it against the spec with drift-checker in a fresh context. Use after the spec is approved, or when /angel:start reaches the plan phase. Do not use without an approved spec (run /angel:spec first) or for implementation.
argument-hint: "[slug]"
---

# Plan phase

Input: `$ARGUMENTS` (a slug, or empty for `.adlc/ACTIVE`)

Precondition: `.adlc/<slug>/spec.md` exists and state.md shows the spec was approved. If not, stop and
suggest `/angel:spec`.

## 1. Plan

Dispatch `angel:planner` with the feature folder path. Nothing else: the planner reads spec.md and
the code itself.

When it returns, confirm `plan.md` exists and has `## Slices` (the goldfish-gate only sends the planner
back once). If it's missing, re-dispatch once, then escalate.

If the plan's `## Decisions needed` isn't "None.", follow `angel:decide` with `plan.md` as the source.
The plan assumes the planner's recommendation. If the user picks a different option, dispatch the
planner again with the decisions.md path before the audit.

## 2. Divergence audit (fresh context)

Dispatch `angel:drift-checker` with the feature folder path, `mode: plan` and the report path
`.adlc/<slug>/reviews/plan-drift.md` (on a re-run, `plan-drift-2.md`, and so on). **Do not
summarise the spec or plan for it.** It must read both cold; that independence is the whole value of
the check. It saves its own report there and returns only a `Report:` line, a short summary, its
Decisions needed and the verdict. Don't copy the report yourself; confirm the file exists.

- `REVISE`: dispatch planner once with the drift report path, then re-run drift-checker.
- `ESCALATE`: follow `angel:decide` on the report's Decisions needed. The answers may send you back
  to /angel:spec or to the planner.
- `PROCEED`: go to the gate.

## 3. Gate

Post the **Plan ready** digest from `angel:start` ("How to talk to the user"): one line per work item
from the plan's plain-words table (name + what it does + what it runs alongside), how it will be
proven, the top risk, and what you need from the user. 10 lines or fewer, names not labels. Ask:
approve / revise / stop.

On approval, update state.md: `phase: implement`, `next: run /angel:implement`, plus a decision-log line.
