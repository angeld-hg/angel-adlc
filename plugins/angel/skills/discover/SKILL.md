---
name: discover
description: Maps the repo angel is running in and writes .adlc/verification.md - what the repo is, which CLIs and credentials are actually available, which commands really work, and the evidence recipes for proving a change works here - by running a deterministic probe script and then a repo-scout goldfish that tries the commands. Use the first time angel runs in a repo (/angel:start does this automatically), after tooling or CI changes, or when verification keeps failing for environment reasons ("/angel:discover"). Do not use to verify a specific feature (use /angel:verify) or to install or fix tooling.
argument-hint: "[--refresh]"
---

# Discover: what can we prove here?

Before building anything, find out how this repo proves that things work. The answer lives in
`.adlc/verification.md`. The planner cites it for every slice, implementers run it, the verifier
depends on it, and the ship-gate won't open a PR without the evidence it enables.

## 1. Check for an existing profile

If `.adlc/verification.md` exists and `--refresh` wasn't given, show its date and Gaps section and
ask the user: keep / refresh. Keep is the default when it's less than 30 days old.

Create `.adlc/` if it doesn't exist. This opts the repo into angel's hooks, so tell the user.

Check `git check-ignore -q .adlc/ACTIVE`. If `.adlc/` is ignored, ask the user with AskUserQuestion
whether to commit the ADLC artifacts (recommended: yes, so the spec, decisions and evidence travel
with the PR) or keep them local. On "commit", `git check-ignore -v .adlc/ACTIVE` names the rule that
matches. Have an implementer remove it (elephant-guard won't let you edit it yourself), or, if it
comes from a global gitignore, note in state.md that the artifacts need `git add -f`.

## 2. Probe (deterministic)

Run:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/probe-env.sh" > .adlc/probe.md
```

It records the stack, commands, installed CLIs (flagging missing ones the repo needs),
gh/docker/cloud auth status, test and CI infrastructure, and how the app runs. It never reads
secrets. Skim it for blockers the user must fix themselves, such as "docker daemon not running"
or "gh not authenticated".

## 3. Scout (goldfish)

Dispatch `angel:repo-scout` with:
- the repo root and the path `.adlc/probe.md`
- the verification-relevant tool families **you** have in this session, for example "browser
  automation (claude-in-chrome) available", "Linear MCP available", or "no browser tools". This is
  a fact about the session, not a summary, and the scout can't see your tool list.

The scout tries the commands under strict local-only rules and writes `.adlc/verification.md`.
(The goldfish-gate hook sends it back if the file or its `## Evidence recipes` section is missing.)

## 4. Review with the user

Show the scout's 5-line summary and the profile's **Gaps** section. For each gap, ask with
AskUserQuestion (recommended option first): close it now (it becomes a chore slice or a user
action, like starting docker) / accept it (criteria of that kind will need a manual check or a waiver) /
ignore. Record the answers in the profile's Gaps section.

If the Baseline section lists failures that already exist on the current branch, tell the user
plainly. The verifier will treat them as pre-existing, not as regressions.

## 5. Suggest the next step

- No AGENTS.md: suggest `/angel:make-claude-md`. The profile's Commands table is a great source for it.
- The profile shows recurring bad patterns the scout noticed: suggest `/angel:antipattern`.
- Otherwise: `/angel:start <idea>`.
