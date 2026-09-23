---
name: ship
description: Phase 6 of the angel ADLC. Pushes the feature branch and opens a GitHub PR whose description is built from spec.md, plan.md and the review reports, then marks the feature shipped. Only runs when the user invokes /angel:ship. Never merges. Do not use before /angel:verify is VERIFIED (the ship-gate hook enforces this), /angel:review has passed, and /angel:check-pr says GO.
argument-hint: "[slug] [--draft]"
disable-model-invocation: true
---

# Ship phase

Input: `$ARGUMENTS`: a slug (or empty for `.adlc/ACTIVE`), optionally `--draft`.

## 1. Preconditions (stop if any fail)

- `reviews/verification.md` says `VERDICT: VERIFIED`, or state.md has `verification: waived`. The
  `ship-gate` hook will deny `gh pr create` otherwise. Don't try to work around it; run `/angel:verify`.
- No `Status: pending` entries in decisions.md.
- state.md shows review passed (`phase: ship`) and a `/angel:check-pr` run said GO. If check-pr
  hasn't run since the last commit, run it now in pre-push mode.
- Not on `main`. Working tree clean (`git status --porcelain` is empty).
- `gh auth status` succeeds.

## 2. Build the PR description

Read `spec.md`, `plan.md` and `reviews/*.md` and write the body to `.adlc/<slug>/pr-body.md`:

```markdown
## Why
<Problem from the spec, 2-3 sentences.>

## What changed
<One bullet per slice: what it delivers, not a file list.>

## Acceptance criteria
- [x] AC1 ... (covered by `test name`)

## Evidence it works
<One line per AC: how it was verified (e2e / integration / unit / manual) and the key command,
from reviews/verification.md. List waived ACs and the decision id.>

## Decisions made
<One line per decided entry in decisions.md: the question, then the choice.>

## How it was reviewed
- Code review: APPROVE (<n> findings fixed, <n> waived: reason)
- Drift check: PROCEED, <n>/<m> ACs covered

## How to test
<Commands, or manual steps.>
```

Show the title and body to the user and ask for confirmation before pushing. This is an outward-facing action.

## 3. Open the PR

```bash
git push -u origin HEAD
gh pr create --title "<title>" --body-file .adlc/<slug>/pr-body.md [--draft]
```

## 4. Record

Update state.md: `phase: shipped`, `next: run /angel:retro; watch the PR with /angel:check-pr`, plus a
decision-log line with the PR URL. Give the user the PR link. **Never merge**: the user merges.
