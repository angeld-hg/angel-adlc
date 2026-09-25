---
name: ship
description: Phase 6 of the angel ADLC. Pushes the feature branch and opens a GitHub PR with a short description (why, what changed, brief evidence, screenshots of visible changes, detailed how-to-test), then marks the feature shipped. Only runs when the user invokes /angel:ship. Never merges. Do not use before /angel:verify is VERIFIED (the ship-gate hook enforces this), /angel:review has passed, and /angel:check-pr says GO.
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
- gh is authenticated: `gh api user --jq .login` prints a login. Prefer this over `gh auth status`,
  which some guardrail hooks block.

## 2. Draft the PR description (short)

The user wants PR descriptions light: a reviewer should get it in 30 seconds. Read `spec.md`,
`plan.md` and `reviews/verification.md`, and write the body to `.adlc/<slug>/pr-body.md`:

```markdown
## Why
<1-2 sentences: the problem, in plain words.>

## What changed
- <one simple bullet per user-visible change, 3-5 at most; no file lists, no tables>

## Evidence it works
<2-3 lines: what was run and the result, e.g. "4 end-to-end scenarios pass (`just e2e`).
Re-run: `bash .adlc/<slug>/evidence/e2e/<timestamp>/rerun.sh`">

## Screenshots
<one image per visible change, captioned by what it shows; before/after side by side when there's
a "before". For CLI changes, a short fenced block of real output instead. Omit this section only if
nothing is visible.>

## How to test
1. **Set up:** <branch checkout, install, env vars, seed data: exact commands>
2. **Run it:** <exact command to start the app or tool, and where to open it>
3. **Try it:** <step by step: what to click, call or type>
4. **You should see:** <the expected result for each step, including one failure case>
5. **Automated:** <the e2e command, and how long it takes>
```

Rules:
- Leave out acceptance-criteria checklists, decisions made, how it was reviewed, and test logs.
  Those live in `.adlc/<slug>/` for anyone who wants them.
- Names, not labels: never S1, D12 or AC3 in a PR.
- "How to test" is the most detailed section. Someone new to the repo should be able to follow it.
- Title: plain words, under 60 characters, saying what the user gets ("Export reports as CSV").

## 3. Screenshots

The verifier saved screenshots under `.adlc/<slug>/evidence/screenshots/` (`<criterion-name>.png`,
plus `-before.png` where there's a before). If a visible change has no screenshot, ask the verifier
for one (or capture it with the browser tools) before shipping.

GitHub can only render images that live somewhere it can reach, so they go in the branch:
1. Make sure the screenshots are committed (`git add -f .adlc/<slug>/evidence/screenshots` if
   `.adlc/` is gitignored in this repo).
2. After pushing (step 4), reference each one by commit SHA so the link never breaks:
   `![<what it shows>](https://github.com/<owner>/<repo>/blob/<sha>/.adlc/<slug>/evidence/screenshots/<file>.png?raw=true)`
   (`<owner>/<repo>` from `gh repo view --json nameWithOwner --jq .nameWithOwner`, `<sha>` from
   `git rev-parse HEAD`). These render for anyone who can see the repo, including private repos.
3. If the repo isn't on GitHub, or images can't be linked, list the screenshot paths in the PR and
   tell the user they can drag them into the description on the web.

## 4. Confirm, then open the PR

Show the user the title and body (screenshots listed by file name) and ask for confirmation before
pushing. This is an outward-facing action. Then:

```bash
git push -u origin HEAD
# fill the screenshot links in pr-body.md with the pushed SHA, then:
gh pr create --title "<title>" --body-file .adlc/<slug>/pr-body.md [--draft]
```

## 5. Record

Update state.md: `phase: shipped`, `next: run /angel:retro; watch the PR with /angel:check-pr`, plus a
decision-log line with the PR URL. Give the user the PR link. **Never merge**: the user merges.
