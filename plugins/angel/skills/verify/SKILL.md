---
name: verify
description: Phase 4 of the angel ADLC. Proves each acceptance criterion actually works by dispatching the verifier goldfish, which runs tests, starts the app and exercises real behavior using the recipes in .adlc/verification.md, capturing commands and output as evidence. Failures loop back to implementers, and unverifiable ACs become user decisions. The ship-gate hook blocks PR creation until this passes. Use after /angel:implement, or any time you want proof the current branch meets its spec ("/angel:verify"). Do not use for code-quality review (use /angel:review), or without a spec.md.
argument-hint: "[slug]"
---

# Verify phase: evidence, not assurances

Input: `$ARGUMENTS` (a slug, or empty for `.adlc/ACTIVE`)

**Preconditions:**
- `spec.md` exists and all slices are DONE.
- `.adlc/verification.md` exists. If it doesn't, run `angel:discover` first: without it the verifier
  doesn't know how to prove anything in this repo.

## 1. Dispatch the verifier

Dispatch `angel:verifier` with the feature folder path. On a re-run, also pass the previous report
path. Don't tell it what the implementers said worked; its independence is the point.

Save its report to `.adlc/<slug>/reviews/verification.md`. On a re-run, move the old one to
`verification-<n>.md` first, so the ship-gate always reads the latest.

## 2. Act on the verdict

- **`VERIFIED`:** go to the gate.
- **`FAILED`:** for each FAILED AC or regression, dispatch `angel:implementer` with the feature
  folder, the report path and the AC id. Parallelise across independent slices. Then re-run step 1.
  After two failed rounds, stop and bring the evidence to the user.
- **`PARTIAL`:** some ACs can't be verified with what the repo has. Follow `angel:decide` on the
  report's Decisions needed. Typical options:
  - close the gap (a chore slice: add a harness or container)
  - verify manually (the user runs the steps; record what they saw in the report)
  - waive
  - change the AC

  Only when the user has waived **every** unverified AC, set `verification: waived` in state.md's
  frontmatter, with a decision-log line naming the ACs and the decision ids.

## 3. Gate

Tell the user: `<n>/<m>` ACs verified, how each was verified (e2e, integration or unit, in one
line), regressions (none / list), and any waivers.

Update state.md: `phase: review`, `next: run /angel:review`, plus a decision-log line.

**Why this is a hard gate:** the `ship-gate` hook denies `gh pr create` in this repo until
`reviews/verification.md` says `VERDICT: VERIFIED`, or the user has waived verification. Code
review catches bad code; only verification catches code that is well written but doesn't do what
the spec says.
