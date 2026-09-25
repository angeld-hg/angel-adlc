---
name: verify
description: Phase 4 of the angel ADLC. Proves each acceptance criterion actually works by dispatching the verifier goldfish, which runs tests, starts the app and exercises real behavior using the recipes in .adlc/verification.md, capturing commands and output as evidence. Failures loop back to implementers, and unverifiable criteria become user decisions. Leaves a repeatable e2e artifact and the screenshots the PR uses. The ship-gate hook blocks PR creation until this passes. Use after /angel:implement, or any time you want proof the current branch meets its spec ("/angel:verify"). Do not use for code-quality review (use /angel:review), or without a spec.md.
argument-hint: "[slug]"
---

# Verify phase: evidence, not assurances

Input: `$ARGUMENTS` (a slug, or empty for `.adlc/ACTIVE`)

**Preconditions:**
- `spec.md` exists and all slices are DONE.
- `.adlc/verification.md` exists. If it doesn't, run `angel:discover` first: without it the verifier
  doesn't know how to prove anything in this repo.

## 1. Dispatch the verifier

On a re-run, first move the old report to `.adlc/<slug>/reviews/verification-<n>.md`, so the
ship-gate always reads the latest.

Dispatch `angel:verifier` with the feature folder path and the report path
`.adlc/<slug>/reviews/verification.md`. On a re-run, also pass the previous report's (moved) path.
Don't tell it what the implementers said worked; its independence is the point.

The verifier saves its own full report there and returns only a `Report:` line, a short summary,
its Decisions needed and the verdict. Don't copy the report yourself. Confirm the file exists and
ends with the same `VERDICT:`; the ship-gate reads that file.

## 2. Act on the verdict

- **`VERIFIED`:** go to the gate.
- **`FAILED`:** for each FAILED criterion or regression, dispatch `angel:implementer` with the feature
  folder, the report path and the criterion name. Parallelise across independent slices. Then re-run step 1.
  After two failed rounds, stop and bring the evidence to the user.
- **`PARTIAL`:** some criteria can't be verified with what the repo has. Follow `angel:decide` on the
  report's Decisions needed. Typical options:
  - close the gap (a chore slice: add a harness or container)
  - verify manually (the user runs the steps; record what they saw in the report)
  - waive
  - change the criterion

  Only when the user has waived **every** unverified criterion, set `verification: waived` in state.md's
  frontmatter, with a decision-log line naming the criteria and the decisions.

## 3. Gate

Post a digest (10 lines or fewer, names not labels):

```
Verified: 3 of 3 checks work
- csv-download: end-to-end test downloads a real CSV (screenshot saved)
- export-permissions: viewers don't see the button (end-to-end test)
- empty-report-message: shown for empty reports (screenshot saved)
Re-run it yourself: bash .adlc/<slug>/evidence/e2e/<timestamp>/rerun.sh
Nothing else broke: full test suite passes
```

Include waivers, if any, by criterion name.

Update state.md: `phase: review`, `next: run /angel:review`, plus a decision-log line.

**Why this is a hard gate:** the `ship-gate` hook denies `gh pr create` in this repo until
`reviews/verification.md` says `VERDICT: VERIFIED`, or the user has waived verification. Code
review catches bad code; only verification catches code that is well written but doesn't do what
the spec says.
