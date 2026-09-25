---
name: retro
description: End-of-feature retrospective for the angel ADLC. Reads the feature's state log and reviews, writes .adlc/<slug>/retro.md, proposes concrete edits to skills, agents, hooks and CLAUDE.md for the gaps it finds, and records decisions in LEARNINGS.md. Use after a feature ships, when the retro-nudge hook asks for it, or at the end of a long session ("/angel:retro"). Do not use mid-feature to fix a failing phase (re-run that phase instead).
argument-hint: "[slug]"
---

# Retro

Input: `$ARGUMENTS` (a slug, or empty for `.adlc/ACTIVE`)

The goal is to make the next feature cheaper. Every friction point should become one of:
- a skill edit (a procedure was unclear)
- an agent edit (a goldfish did the wrong job)
- a hook (a rule got ignored and has to be enforced)
- an anti-pattern rule (an agent copied a bad pattern from existing code; ban it with `/angel:antipattern`)
- a verification-profile update (evidence was hard to get; refresh with `/angel:discover` or close a gap)
- an AGENTS.md or CLAUDE.md line (a fact about the repo was missing)
- nothing (a one-off)

## 1. Gather evidence (read the files, don't recall)

- `state.md` decision log: revise loops, escalations, waivers, blocked slices.
- `reviews/*.md`: which findings recurred across rounds.
- This session: places where you, the elephant, hit the guard, had to correct a goldfish, or the user
  corrected you.

## 2. Write retro.md

```markdown
# Retro: <slug>

## What went well
- ...

## Friction
| What happened | Root cause | Fix type | Proposed change |
|---|---|---|---|
| planner marked `export-button` and `csv-streaming` parallel but they shared utils.ts | parallel-safety not checked | agent | planner: list shared helpers under Contracts |

## Numbers
Revise loops: spec <n>, plan <n>, review <n>. Work items: <n> (<n> in parallel). Waivers: <n>.
```

Give every friction row and every proposed edit a short descriptive name (`parallel-port-collision`,
`planner-small-slices`), never F1 or E3: the user reviews these later and has to know what each one
is from its name.

## 3. Propose edits

For each row whose fix type isn't "nothing", draft the exact edit (file + before/after snippet).
Show them to the user and ask which to apply. The angel plugin's own files live outside this repo,
so for plugin changes, give the user the diff to apply in the plugin repo.

## 4. Record

Append a dated entry to the project's `LEARNINGS.md`, creating it if needed. In an angel repo, this
needs `LEARNINGS.md` in `.adlc/allow`, or write it via an implementer. Log the approved changes and
why. Update state.md's decision log: "retro done".
