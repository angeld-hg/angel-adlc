---
name: check-pr
description: Angel's PR gate with two modes, picked automatically. Pre-push (no PR yet) runs tests and lint plus parallel code-reviewer and drift-checker goldfish and returns GO / NO-GO. PR mode (PR open) summarises CI checks and unresolved review threads into a blocker list. Use before pushing or opening a PR, or to see what's blocking an open PR ("/angel:check-pr", "/angel:check-pr 123"). Do not use to fix the problems it finds (route them to /angel:review or an implementer), and never to merge.
argument-hint: "[PR number | branch] [--pre-push]"
---

# Check PR

Input: `$ARGUMENTS`

## Pick the mode

1. A PR number was given, or `gh pr view --json number,state` finds an **open** PR for the current
   branch: **PR mode**.
2. Otherwise, or with `--pre-push`: **pre-push mode**.

Say which mode you picked in your first line.

## Pre-push mode: "should I push this?"

Run these in parallel (one message):
- **Checks (you, read-only Bash):** the project's test and lint commands (`just test`, `just lint`;
  fall back to AGENTS.md). Capture pass/fail and the first failure.
- **`angel:code-reviewer`:** base branch (default `main`) and the feature folder, if there's an active one.
- **`angel:drift-checker`:** only if there's an active feature: folder path, `mode: diff`, base branch.

With an active feature, also give each reviewer a report path:
`.adlc/<slug>/reviews/check-pr-code-review.md` and `.adlc/<slug>/reviews/check-pr-drift.md` (add a
`-2`, `-3` suffix if they exist). They save their own reports there and return only a `Report:`
line, a short summary, Decisions needed and the verdict; fill the table from that and don't copy the
reports yourself. Without an active feature, pass no path: the reviewer returns its full report.

Also check these yourself (read-only):
- **Verification:** with an active feature, `reviews/verification.md` must exist, say
  `VERDICT: VERIFIED` (or state.md has `verification: waived`), and be newer than the last commit
  that touched source (`git log -1 --format=%ct -- . ':!.adlc'` vs the file's mtime). If it's stale
  or missing, the gate is red: run `/angel:verify`.
- **Anti-patterns:** if `.adlc/rules/` exists, run
  `bash "${CLAUDE_PLUGIN_ROOT}/scripts/check-antipatterns.sh" --diff <base>`. Any hit is red.
- no uncommitted changes
- no `TODO`/`FIXME`/`console.log`/`print(` added in the diff
- no secrets-looking strings added
- the branch is up to date with its base (`git fetch` + `git rev-list --count HEAD..origin/<base>`)

Output:

```
## check-pr (pre-push): <branch>
| Gate | Result |
|---|---|
| Tests | pass (212) / FAIL: <first failure> |
| Lint | ... |
| Code review | APPROVE / CHANGES_REQUESTED (<n> critical) |
| Drift | PROCEED / REVISE / n/a |
| Verification | VERIFIED (n/m criteria) / waived / STALE / MISSING / n/a |
| Anti-patterns | clean / <n> new violations / no rules |
| Open decisions | none / `export-feature-flag`, `excel-support` pending |
| Hygiene | ok / <issues> |

GO | NO-GO: <the one thing to fix first>
```

GO requires every gate green, or an issue the user has explicitly waived. If the reviewers returned
**Decisions needed**, the verdict is NO-GO until they're settled via `angel:decide`. Save the table to
`.adlc/<slug>/reviews/check-pr.md` when there's an active feature, and add a decision-log line.

## PR mode: "what's blocking this PR?"

Gather the data (read-only):
- `gh pr view <n> --json title,state,isDraft,mergeable,reviewDecision,baseRefName,headRefName,url`
- `gh pr checks <n>`: for failures, get the log tail with `gh run view <run-id> --log-failed`
  (last ~40 lines).
- Unresolved review threads:
  `gh api graphql -f query='query($o:String!,$r:String!,$n:Int!){repository(owner:$o,name:$r){pullRequest(number:$n){reviewThreads(first:100){nodes{isResolved path line comments(first:1){nodes{author{login} body}}}}}}}' -F o=<owner> -F r=<repo> -F n=<n>`
  (get owner/repo from `gh repo view --json owner,name`).

Output:

```
## check-pr (PR #<n>): <title>
Status: <draft?> · review: <APPROVED|CHANGES_REQUESTED|REVIEW_REQUIRED> · mergeable: <...>

### Blocking
1. CI `<check>` failing: <one-line cause from the log>
2. Unresolved thread by @<who> on `path:line`: "<gist>"

### Not blocking
- ...

Next step: <single most useful action>
```

Don't fix anything in this skill. Offer to route the failures to an implementer (via `/angel:review`
for code findings) as the next step.
