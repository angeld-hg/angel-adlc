---
name: decide
description: Puts architecture-level and scope choices in front of the user as multiple-choice prompts (AskUserQuestion), in the spirit of grill-me. Collects every "Decisions needed" entry from goldfish reports into .adlc/<slug>/decisions.md, asks them with the recommended option first, follows up when an answer opens a new question, records each answer, and routes the consequences back to the right goldfish. Use whenever a spec-writer, planner, reviewer, verifier or implementer report contains decisions, when the decision-gate hook fires, or to walk through pending decisions ("/angel:decide"). Do not use for mechanical fixes that have one right answer (route those to an implementer), and never to answer the questions yourself.
argument-hint: "[report path | 'grill' <topic>]"
---

# Decide: the user makes the calls that last

Goldfish surface choices; they don't make them. The elephant doesn't make them either. Your job
is to present each choice clearly enough that the user can decide in seconds, then make sure
the decision sticks.

Input: `$ARGUMENTS`: a report path to harvest from, `grill <topic>` for an interview, or empty
for everything pending.

## 1. Harvest into decisions.md

Read the source (the report path, or the latest files in `.adlc/<slug>/reviews/`, plus `spec.md`
and `plan.md`) and copy every entry under a `## Decisions needed` heading into
`.adlc/<slug>/decisions.md`. Skip entries that are already there, and skip "None.".

```markdown
# Decisions: <slug>

## <decision-name>: <question>
- Status: pending
- Raised by: <agent> (<report path>)
- Context: <from the report>
- Options:
  - <option name> - <consequence>
  - <option name> - <consequence>
- Recommendation: <option name>, because <reason>
```

Give each decision a short kebab-case **name** that says what it's about (`csv-streaming`,
`export-feature-flag`), unique within the feature. Never number them (D1, D2...): the user has to
know what a decision is from its name alone, especially when they come back to it later. The
`decision-gate` hook refuses to let your turn end while any entry says `Status: pending`.

**Is it really a decision?** If exactly one option is defensible, it's a fix: send it to an
implementer and tell the user in one line. If you're unsure, ask; asking is cheap.

## 2. Ask with choice boxes

Use AskUserQuestion. Batch up to 4 independent decisions per call. Ask dependent ones one at a
time, because the answer changes the next question. For each:
- `question`: the decision's question, ending with "?", plus one clause of context.
- `header`: 12 characters max, e.g. "Data model", "Scope", "Dependency".
- `options`: 2-4 options, **recommended first** with " (Recommended)" appended to its label. Each
  `description` states the consequence: what changes, what it costs, and what it rules out.
- Use `preview` when the options are code shapes, API signatures, schemas or layouts. Show the
  actual snippet for each option, so the user compares concrete things.
- Never add an "Other" option; the user always gets a free-text choice.

## 3. Follow the branches (grill-me style)

After each answer, ask yourself: does this open a new question? For example, "Stream the CSV"
opens "What happens if the client disconnects mid-stream?". If so, add it as a new pending
decision and ask it next. Keep going until the decision tree for this batch is settled. Stop
when the remaining questions are details a goldfish can decide safely.

**`grill <topic>` mode:** with no report, interview the user about the topic one question at a
time, recommendation first, walking the design tree until you both understand it the same way.
Record each answer as a decided entry.

## 4. Record

Update each entry:

```markdown
- Status: decided
- Decision: <option name>, by user, <YYYY-MM-DD>. <their note, if any>
```

If the user explicitly postpones one, use `Status: deferred` with their reason. Append one line
per decision to state.md's decision log ("csv-streaming decided: stream it (user)").

## 5. Route the consequences

Each decision goes back to whoever owns the affected artifact. Pass the decisions.md path and the
names, never a paraphrase:

| Decision changes | Send to |
|---|---|
| requirements, scope, criteria | `angel:spec-writer` (second pass) |
| design, slices, contracts | `angel:planner` (revision pass) |
| code already written | `angel:implementer` (one per affected slice) |
| "ban this pattern" (rule candidates) | follow `angel:antipattern` |
| waive verification for some criteria | record it, then set `verification: waived` in state.md only if the user waived **every** unverified criterion |

Then re-run the review that raised the decision, so it can confirm the new state.
