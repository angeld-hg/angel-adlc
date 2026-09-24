# LEARNINGS

A running log of decisions, experiments and reversals while building `angel`. Newest first.
Each entry answers: what did we decide, why, and what would make us change it.

---

## 2026-09-24: v0.3.0, fixes from the gantt-chart-manager retro

First real feature through angel (hg-gaant-chart PR #1: 13 slices, 19 decisions, 3 verification
runs). The retro (`.adlc/gantt-chart-manager/retro.md` in that repo) found 10 friction points; the
user approved seven plugin edits, E1-E7. The verification-profile edit (E8) was local to that repo,
and the guardrail false positives belong to another plugin.

- **E1 planner: small slices, isolated e2e (F2, F3).** One new e2e spec per slice, quality-gate work
  split per spec. If two parallel slices both run e2e, the scaffold slice makes ports, DB path and
  output dir env-configurable. S13 had bundled three specs and stalled twice; parallel UI slices
  would have collided on ports.
- **E2 implementer: time-box, fix the class (F2, F6).** Every command is time-boxed (the watchdog
  kills a goldfish silent for 10 min). A review fix lists every sibling call site. CR7 was CR1's
  sibling and cost a whole extra review/verify round.
- **E3 implement skill: environment facts, e2e cap, stalls (F2, F3, F4).** "Nothing more" was
  relaxed: the elephant may pass per-slice environment facts (ports, DB path, which slices run
  alongside), never summaries. At most 2 e2e-running slices at once (load 26-45 flaked timing
  tests). A stalled slice is resumed once, then split.
- **E4 start: no duplicate goldfish (F1).** Check ListAgents before re-dispatching; plans take
  15-20 min. The elephant restarted a planner that was still working.
- **E5 reviewers save their own reports (F5).** The elephant was retyping ~8 reports of several
  thousand tokens each into `reviews/`. code-reviewer, drift-checker, spec-reviewer and verifier now
  have Write, the skills pass them a report path, and they return `Report: <path>`, <= 5 summary
  lines, `## Decisions needed` and the verdict.
  - **Enforcement:** new `reviewer-write-guard` PreToolUse hook, not an extension of
    elephant-guard (which is about the main session and is off outside opted-in repos). It keys
    on `agent_type`, which the v0.1.0 spike showed PreToolUse carries for subagent calls. It allows
    `.adlc/<slug>/reviews/<name>.md` in an existing feature folder (plus `evidence/` for the
    verifier, whose instructions already put throwaway scripts there) and denies everything else,
    in every repo. `..` segments are refused outright.
  - **Decisions stay in the final message.** The approved wording was "verdict line plus 5 lines",
    but `decide` and goldfish-gate need the `## Decisions needed` section, so it's copied over
    (usually "None."), as the planner already does.
  - **goldfish-gate** now checks that a `Report:` file exists, and for the verifier checks
    `## Evidence` and `VERDICT:` in that file, since the ship-gate reads it.
  - **Limitation:** writes through Bash (`tee`, `>`) are invisible to the hook, as with
    elephant-guard. Three of the four agents keep Bash for read-only commands; only their
    instructions stop them.
- **E6 discover: is `.adlc/` tracked? (F7).** `.adlc` was gitignored before S1 and the spec trail
  nearly didn't ship. Discover now checks `git check-ignore` and asks.
- **E7 ship: gh login check (F8).** `gh api user --jq .login` instead of `gh auth status`, which the
  HG guardrails plugin blocks.

Not done: the code-reviewer asking for the sibling list (part of F6's proposal, not in E2), and a
verify-alone rule for the verify skill (F4, left to the repo's verification profile).

---

## 2026-09-23: v0.2.0, decisions, verification and anti-patterns

Angel asked for four changes after reviewing v0.1.0.

### 1. `watchtower` renamed to `goldfish-gate`

The bootcamp calls it the "watchtower pattern", but the hook's job is narrower: it's the gate every
goldfish passes on its way out. The name now says what it guards, in the plugin's own vocabulary.
Older entries below use the new name.

### 2. Architecture calls go to the user as choice boxes

**Problem:** reviewers' findings all flowed into a fix loop, so an implementer (or the elephant)
quietly settled questions that were really the user's: API shape, schema, new dependencies, scope.

**Design:** every goldfish report is split into **fixes** (one right answer, sent to an implementer)
and **decisions** (reasonable engineers could differ, and the choice lasts, sent to the user).
- **One format everywhere.** spec-writer, planner, the four reviewers and the verifier all emit a
  `## Decisions needed` section with question, options, consequences and a recommendation. It
  maps one-to-one onto AskUserQuestion (recommended option first, `preview` for code shapes).
- **The `decide` skill** harvests those sections into `.adlc/<slug>/decisions.md` (D1, D2, ...),
  asks in batches of up to 4, follows new branches grill-me style, records answers, and routes the
  consequences (spec-writer, planner, implementer, or antipattern).
- **Enforcement at both ends.** `goldfish-gate` won't let a reviewer finish without the section
  (so "None." is an explicit statement, not an omission). The new **`decision-gate`** Stop hook
  won't let the elephant end its turn with `Status: pending` entries.

**Live result:** in a headless test with no AskUserQuestion, the elephant was told in the prompt
that it could defer D1 itself. The decision-gate fired, and the elephant **refused to defer on its
own authority**, quoting the hook ("Don't decide them yourself"), and asked in plain text instead.
The hook's wording mattered: it says deferral is only for when the *user* chose it.

### 3. Verification for correctness

**Problem:** "tests pass" isn't proof that a feature works, and angel knew nothing about the repo
it was dropped into: which CLIs exist and are authenticated, whether docker runs, how the app starts.

**Design, in three layers:**
- **`discover`** (once per repo). `scripts/probe-env.sh` gathers deterministic facts (stack,
  commands, installed and needed CLIs, gh/docker/cloud auth, test/CI/runtime infra; never `.env`
  contents). Then the **`repo-scout`** goldfish actually *tries* the commands under local-only
  safety rules and writes `.adlc/verification.md`. The key section is **Evidence recipes**: the
  strongest available proof per kind of change, as exact commands. **Gaps** become user decisions.
- **Per slice.** The planner gives every slice an `Evidence:` line from the recipes, and the
  implementer must run it before reporting DONE.
- **Per feature: `verify` phase + `verifier` goldfish** (read-only; code reading alone never counts).
  It proves each AC with a command and captured output, shows at least one check can fail, and runs
  a regression pass. FAILED loops to implementers. Unverifiable ACs become decisions (close the gap,
  verify manually, waive, or change the AC).
- **Hard gate: the `ship-gate` hook** denies `gh pr create` unless `reviews/verification.md` says
  `VERIFIED`, or state.md has `verification: waived`. A skill instruction could be skipped; a
  PreToolUse deny can't.
- **Honest caveat:** the waiver is a frontmatter field the elephant could set itself. The skill
  says it may only do so after the user waived every unverified AC through `decide`, but that's an
  instruction, not enforcement. A stricter version would check decisions.md for a matching
  decided waiver.
- **Live:** the ship-gate denied `gh pr create` with "no verification report for 'greet-cli' yet". ✅

### 4. Anti-pattern rules (hybrid)

**Problem:** agents copy the patterns around them, including bad ones. "We don't do that here"
in a doc doesn't stop an agent that just read three files doing exactly that.

**Design:** `/angel:antipattern` writes `.adlc/rules/<id>.md` (ERE regex, paths, exclude, action,
`## Why`, `## Instead`). Where the repo's own linter can express the rule (ESLint
`no-restricted-syntax`, ruff `banned-api`, semgrep, forbidigo), it also adds a native rule via an
implementer, so humans and CI are covered too.
- **`antipattern-guard`** (PreToolUse on Edit/Write) applies to **every** agent, elephant and
  goldfish. It denies writes that **add** a match, and the reason includes the rule's Why and
  Instead, so the agent immediately knows the right pattern.
- It counts matches in new vs old text, so touching legacy code that already contains the
  pattern isn't blocked. Without this, a rule on a common pattern would freeze whole files.
- `scripts/check-antipatterns.sh` does a full scan (baseline), `--diff` (added lines only, including
  untracked files) and `--validate`. check-pr and implement run `--diff`, which also catches banned
  code written through Bash and **partly closes the v0.1.0 "Bash writes" gap**.
- Reviewers tag `[rule-candidate]` when a bad pattern already appears elsewhere, and review turns
  that into a "ban it?" decision. Retro gained "anti-pattern rule" as a fix type.

**Bug found live:** unit tests passed, but in the live run both writes went through.
- **Cause:** `for g in $globs` word-splits *and pathname-expands*. Claude Code runs hooks from the
  repo root, so `src/**` expanded into the real filenames and never matched a new file.
- **Fix:** split with `IFS=, read -r -a`.
- **Lessons:**
  1. `run_hook` in tests now runs from the project root, like Claude Code does.
  2. A regression test first **failed against the old code** before it was trusted. The first
     draft of that test passed on the buggy code, because its globs matched no real files.
- After the fix, the live run blocked both the elephant and a subagent. ✅

### Rule migration, continued

| Rule | Started as | Now | Why |
|---|---|---|---|
| "Ask the user about architecture choices" | nothing (reviewers fed a fix loop) | report format + **goldfish-gate** + **decision-gate** + `decide` skill | Agents fill ambiguity with a choice. The gap must be made visible *and* un-skippable. |
| "Don't ship unverified work" | "tests green" in the implement skill | `verify` phase + **ship-gate** hook | Code review can't catch well-written code that does the wrong thing. |
| "Don't use pattern X here" | a line in AGENTS.md (at best) | `.adlc/rules/` + **antipattern-guard** + native lint rule | Agents weight nearby code over docs. Only a write-time check beats imitation. |

---

## 2026-09-23: v0.1.0, first build

### Architecture: Elephant/Goldfish over a linear skill chain

HG's `adlc` plugin runs phases as skills in the main session, with subagents for execution. `angel`
goes further: the main session **only orchestrates**. Every bounded job, including spec writing and
planning, runs in a fresh subagent.

- **Why:** the elephant's context is the scarce resource. If it writes code, a long feature fills it
  with diffs and test output, and it forgets the spec. Goldfish forget by design, so each one reads
  the artifacts cold. That also makes them honest reviewers.
- **Cost:** more round trips, and the elephant has to relay questions (the spec-writer can't talk to
  the user, so it returns open questions and the elephant asks them).

### Rule migration: CLAUDE.md -> skill -> hook

This is the assignment question: what started as prose and moved into skills, hooks or agents, and why.

| Rule | Started as | Now | Why it moved |
|---|---|---|---|
| "Orchestrator doesn't edit source" | a CLAUDE.md line | **`elephant-guard` hook** (PreToolUse deny) | Models drift under pressure ("it's just one line"). A rule that must always hold belongs in the harness, not the prompt. |
| "Specs need testable acceptance criteria" | agent instructions | agent instructions + **`goldfish-gate` hook** | The agent can still finish early. The hook re-injects the instruction if `spec.md` lacks `## Acceptance Criteria` (the bootcamp's "watchtower" pattern). |
| "Reviewers end with a verdict" | agent instructions | + `goldfish-gate` hook | The elephant gates on `VERDICT:` lines, and a missing verdict silently broke gating. |
| "Resume where you left off" | "read state.md first" in CLAUDE.md | **`session-start` hook** | Injected context is guaranteed; "remember to read X" isn't. |
| "Do a retro after shipping" | a bullet in the start skill | + **`retro-nudge` Stop hook** (once per session) | The end of a session is exactly when instructions are forgotten. |
| "Reviewers must not modify code" | instructions | **agent `tools:` allowlist** (no Write/Edit) | Tool restriction is enforcement for free. |
| Skill format rules (description says when/when-not, <500 lines) | bootcamp notes | **`scripts/lint-skills.sh`** | Deterministic, so a script does it. The judgement part (drift) stays with the `doc-auditor` agent. |

What stays in CLAUDE.md: only environment facts that nothing can enforce (reload plugins after edits,
the plugin conflict with HG `adlc`). Everything portable lives in AGENTS.md.

### Spike: can a hook tell the elephant from a goldfish?

Tested on Claude Code 2.1.280 with a logging plugin and `claude -p`. **Yes.** PreToolUse input
carries `agent_id` and `agent_type` only when a subagent makes the call. Main-session calls have neither.
SubagentStop input carries `agent_type` (plugin agents arrive as `angel:<name>`), `stop_hook_active`,
and `last_assistant_message`. So:
- `elephant-guard` allows any call with `agent_id`, and needs no marker files or transcript sniffing.
- `goldfish-gate` switches on `agent_type` (prefix stripped) and uses one hook entry with no matcher,
  rather than depending on how matchers treat the `angel:` namespace.
- `goldfish-gate` can check reviewer verdicts straight from `last_assistant_message`.

### Live hook test (`claude -p --plugin-dir`, scratch repo, HG `adlc` disabled)

- **session-start:** the new session named the active feature, its phase and next step without reading any files. ✅
- **elephant-guard:** the main chat's `Write src/greet.sh` was denied, and the file was unchanged. ✅
- **goldfish-gate:** fired on `angel:planner` (the goldfish mentioned the stop hook). But the test prompt
  told it *not* to write, so it stopped again, and `stop_hook_active` let the second stop through.
  - **Lesson:** the goldfish-gate is a strong nudge, not a wall. It re-injects once, by design, so it
    can't loop.
  - **Change made:** the `spec` and `plan` skills now have the elephant verify the artifact itself
    after each dispatch (re-dispatch once, then escalate). That's defence in depth.
- **retro-nudge:** with `phase: shipped` and no retro, the Stop hook kept the session going until
  `retro.md` was written. ✅

### Dogfood: `/angel:doc-audit` on this repo

The lint was clean (17 files), but the doc-auditor found 6 real issues in docs written an hour earlier.
The drift check is doing work the lint can't.
- **AGENTS.md said all hooks are silent without `.adlc/`**, but the goldfish-gate's verdict check isn't.
  Kept the behavior (check-pr and doc-audit gate on verdicts in any repo), fixed the doc, added a test.
- The artifact list was missing `pr-body.md`, and the `start` table listed `check` as a phase that no
  skill ever sets. Both fixed.
- A copied CLAUDE.md bullet (python3/uv) didn't apply to a bash-only repo. Removed.
- **Hook candidate, not done yet:** "hand goldfish paths, never summaries" is repeated in 4 places
  with no enforcement. It could become a PreToolUse hook on `Agent` that requires a `.adlc/` path in
  the prompt for `angel:` writers and drift-checker. It's the same move "don't edit source" made.
  Deferred until a real session shows the rule being broken.

### Smaller decisions

- **Artifacts are files in `.adlc/`, not Linear tickets.** Hooks can verify files; they can't easily
  verify ticket fields. Files also travel with the branch. Linear sync is a possible later addition.
- **Opt-in per repo via `.adlc/`.** Every hook is silent without it, so the plugin costs nothing
  elsewhere, and the guard never blocks work on this plugin's own repo.
- **The guard allows paths outside the project** (plan files, memory, scratchpads), because it
  protects the repo's source, not the machine.
- **Escape hatches:** `.adlc/allow` (globs, per repo) and `ANGEL_ALLOW_MAIN_EDITS=1` (per session).
  Strict by default, but not a cage.
- **Templates live inside the agent bodies** rather than in separate files. The agent is the only
  consumer, and it avoids path-resolution questions inside subagents.
- **Skills only, no `commands/`.** Plugin skills are already `/angel:<name>`. `ship` sets
  `disable-model-invocation: true` so only the user can trigger an outward-facing push.
- **Models:** opus for judgement-heavy goldfish (spec-writer, planner, reviewers, and implementer,
  per Angel's preference). Sonnet for doc-auditor.
- **Manifest folder:** the standard `.claude-plugin/`, not the `.claude_plugin/` used in HG's cache.
- **Plugin lives in `plugins/angel/`, not the repo root.** With the plugin at the root, `claude plugin
  validate` warned that the root CLAUDE.md "is not loaded as project context". That's correct: it's
  this repo's dev guide, not shipped context (bootcamp note: CLAUDE.md doesn't ship in a plugin).
  Splitting marketplace/repo from plugin gives a warning-free validate, and installs no longer copy
  tests and dev docs.

### Known gaps (v0.1.0; see v0.2.0 for what changed)

- **The guard doesn't cover Bash writes** (`sed -i`, `>` redirects). Closing it means parsing shell
  commands in a PreToolUse Bash hook, which is brittle. For now the elephant's skill instructions cover it.
- Parallel implementers share one working tree. Safe only because the planner assigns disjoint files.
  Worktree isolation is the next step if this bites.
- `lint-skills.sh` checks description *shape* (the presence of "Use when" / "Do not"), not quality.
