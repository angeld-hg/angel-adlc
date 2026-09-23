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

Dispatch `angel:drift-checker` with the feature folder path and `mode: plan`. **Do not summarise the
spec or plan for it.** It must read both cold; that independence is the whole value of the check.
Save its report to `.adlc/<slug>/reviews/plan-drift.md`.

- `REVISE`: dispatch planner once with the drift report path, then re-run drift-checker.
- `ESCALATE`: follow `angel:decide` on the report's Decisions needed. The answers may send you back
  to /angel:spec or to the planner.
- `PROCEED`: go to the gate.

## 3. Gate

Tell the user: the approach in one line, the slices (id + name + parallel? + how each will be
proven), AC coverage, the decisions made, and the top risk. Ask: approve / revise / stop.

On approval, update state.md: `phase: implement`, `next: run /angel:implement`, plus a decision-log line.
