---
name: review
description: Phase 5 of the angel ADLC. Runs code-reviewer and drift-checker (mode diff) in parallel against the branch diff, saves both reports, routes fixes back to implementer goldfish, and puts architectural findings and rule candidates to the user as choices. Use after implementation, or whenever you want an independent review of the current branch against its spec and plan. Do not use to check an already-open PR's CI or comments (use /angel:check-pr) or with no changes on the branch.
argument-hint: "[slug] [base branch, default main]"
---

# Review phase

Input: `$ARGUMENTS`: a slug (or empty for `.adlc/ACTIVE`) and optionally the base branch (default `main`).

Precondition: the branch has commits or changes relative to the base. Check with `git diff <base>...HEAD --stat`.

## 1. Dispatch both reviewers at once

Pick the report paths first: `.adlc/<slug>/reviews/code-review.md` and
`.adlc/<slug>/reviews/diff-drift.md` (if a previous round exists, add a `-2`, `-3` suffix rather than
overwriting). Then, in **one message**, send two Agent calls:
- `angel:code-reviewer`: base branch + feature folder path + its report path + the path `${CLAUDE_PLUGIN_ROOT}/scripts/check-antipatterns.sh` (if `.adlc/rules/` exists).
- `angel:drift-checker`: feature folder path + `mode: diff` + base branch + its report path.

Neither edits code, and neither sees the other's output. That independence is deliberate.

Each one saves its own full report to the path you gave it and returns only a `Report:` line, a
short summary, its Decisions needed and the verdict. Don't copy reports into files yourself. Confirm
both files exist.

## 2. Triage: fixes, decisions, rule candidates

The final messages give you the verdicts, finding counts and decisions. If either reports any
findings, read just the findings lists in the saved reports, merge them into one list, ordered
Critical/high first, and sort each one:
- **Fix** (one right answer): route it to an implementer (step 3).
- **Decision** (anything under a report's `## Decisions needed`, or a finding where you see more
  than one defensible answer): follow `angel:decide`. The user chooses via choice boxes, and the
  answers are routed from there. Don't turn a decision into a fix by picking an option yourself.
- **`[rule-candidate]`**: the pattern already exists elsewhere, so agents will keep copying it.
  Add a decision: "Ban `<pattern>` with an angel rule?" (options: ban now via `angel:antipattern` /
  fix this occurrence only / ignore). Recommend banning when the reviewer found 2+ other occurrences.
- **Waive**: only with the user's say-so, recorded as a decided entry in decisions.md.

## 3. Fix loop

For each fix, dispatch `angel:implementer` with the feature folder, the report path, and the finding
id or `path:line`. Independent fixes in different files can go in parallel. Check the work as in
`angel:implement` step 3. Then re-run step 1, at most two rounds before escalating to the user.

If fixes changed behavior, re-run `angel:verify` too. The ship-gate reads the latest verification
report, and it must describe the code you're about to ship.

## 4. Gate

Pass means `VERDICT: APPROVE` + `VERDICT: PROCEED`, no pending decisions, and every remaining finding
explicitly waived by the user. Tell the user the outcome in 5 lines or fewer.

On pass, update state.md: `phase: ship`, `next: run /angel:check-pr then /angel:ship`.
