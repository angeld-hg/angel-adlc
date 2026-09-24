---
name: spec
description: Phase 1 of the angel ADLC. Turns an idea into a reviewed .adlc/<slug>/spec.md (WHAT and WHY, testable acceptance criteria) by dispatching the spec-writer goldfish, relaying its open questions to the user, then dispatching spec-reviewer. Use when a feature needs requirements pinned down before planning, or when /angel:start reaches the spec phase. Do not use for technical design (use /angel:plan) or for bugs with an obvious fix.
argument-hint: "[idea or slug]"
---

# Spec phase

Input: `$ARGUMENTS`

Resolve the feature folder first: use the slug if one was given, otherwise `.adlc/ACTIVE`. If neither
exists and an idea was given, follow `angel:start` Step 1 to create the folder.

## 1. Draft

Dispatch `angel:spec-writer` with:
- the feature folder path
- the idea, verbatim from state.md or the user

Don't add your own interpretation of the idea. The spec-writer reads the code itself.

When it returns, confirm `spec.md` exists and has `## Acceptance Criteria`. The goldfish-gate hook sends
the goldfish back once, but a second early stop gets through. If the file is still missing, re-dispatch
once, then escalate to the user.

## 2. Resolve decisions

If the spec's `## Decisions needed` isn't "None.", follow `angel:decide` with `spec.md` as the
source: harvest the entries into decisions.md, ask with choice boxes (recommended first), and record
the answers. Then dispatch `angel:spec-writer` again with the folder path and the decisions.md path.
Repeat until no decisions remain pending (at most two rounds, then ask the user whether to continue).

## 3. Review

Dispatch `angel:spec-reviewer` with the path to `spec.md` and the report path
`.adlc/<slug>/reviews/spec-review.md` (on a re-review, `spec-review-2.md`, and so on). It saves its
own report there and returns only a `Report:` line, a short summary, its Decisions needed and the
verdict. Don't copy the report yourself; confirm the file exists.

- Decisions needed in the review: follow `angel:decide` first.
- `VERDICT: REVISE`: dispatch spec-writer once with the review path (and decisions.md), then re-review.
- `VERDICT: READY`: go to the gate.

## 4. Gate

Tell the user in 5 lines or fewer: the goal, AC count, non-goals, and anything the reviewer flagged
as "should fix". Ask: approve / revise / stop.

On approval, update state.md: `phase: plan`, `next: run /angel:plan`, plus a decision-log line.
