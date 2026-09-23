#!/usr/bin/env bash
# SessionStart: elephant memory.
#
# In a repo with .adlc/, remind the main session that it's the orchestrator and,
# if a feature is in flight, where it left off: phase, last decision, next step.
# Silent everywhere else, so the plugin costs nothing in unrelated repos.

# shellcheck source=hooks/lib.sh
source "$(dirname "$0")/lib.sh"
angel_read_input

adlc="$(angel_adlc_dir)"
[ -d "$adlc" ] || angel_allow

primer="## angel (Elephant/Goldfish ADLC)

You are the **elephant**: the one long-lived orchestrator. You hold the feature's state, talk to the user, and gate each phase. Goldfish subagents (spec-writer, planner, implementer, spec-reviewer, drift-checker, code-reviewer, doc-auditor) do the bounded work in fresh contexts.

- Don't edit source yourself; the elephant-guard hook blocks it. Write only under .adlc/, and delegate code changes to \`implementer\`.
- Hand goldfish **paths and a mode, never summaries**.
- Architecture-level choices belong to the user: record them in decisions.md and ask with AskUserQuestion (/angel:decide). Never settle them yourself.
- Pipeline: /angel:spec -> /angel:plan -> /angel:implement -> /angel:verify -> /angel:review -> /angel:check-pr -> /angel:ship, driven by /angel:start. Finish with /angel:retro."

# Repo-wide facts: verification profile and anti-pattern rules.
repo_facts=""
if [ -f "$adlc/verification.md" ]; then
  repo_facts="- Verification profile: .adlc/verification.md (how to prove changes work here; refresh with /angel:discover)"
else
  repo_facts="- No verification profile yet: run /angel:discover before building, so goldfish know how to prove their work."
fi
# shellcheck source=hooks/rules-lib.sh
source "$(dirname "$0")/rules-lib.sh"
rule_ids="$(rules_list "$(angel_project_dir)" | while IFS= read -r r; do basename "$r" .md; done | head -n 15 | tr '\n' ' ')"
if [ -n "$rule_ids" ]; then
  repo_facts="$repo_facts
- Banned patterns (.adlc/rules/, enforced on every write): $rule_ids"
fi

feature="$(angel_feature_dir)"
if [ -z "$feature" ]; then
  angel_context SessionStart "$primer

$repo_facts

No active feature. Start one with /angel:start <idea>."
fi

state="$feature/state.md"
slug="$(angel_active_slug)"
phase="$(angel_frontmatter_value "$state" phase)"
updated="$(angel_frontmatter_value "$state" updated)"
next="$(angel_frontmatter_value "$state" next)"
# The decision log is a list of "- YYYY-MM-DD: ..." lines; the last one is the freshest.
last_decision="$(grep -E '^- [0-9]{4}-[0-9]{2}-[0-9]{2}' "$state" 2>/dev/null | tail -n 1 || true)"

artifacts="$(cd "$feature" && find . -maxdepth 2 -type f -name '*.md' ! -name state.md | sed 's|^\./||' | sort | tr '\n' ' ')"
pending="$(grep -cE '^- Status:[[:space:]]*pending' "$feature/decisions.md" 2>/dev/null || true)"
pending_line=""
if [ "${pending:-0}" -gt 0 ]; then
  pending_line="
- **Pending user decisions: $pending** in .adlc/$slug/decisions.md. Ask these first (/angel:decide)."
fi

angel_context SessionStart "$primer

$repo_facts

### Active feature: \`$slug\`
- Phase: ${phase:-unknown} (updated ${updated:-unknown})
- Next step: ${next:-see .adlc/$slug/state.md}
- Last decision: ${last_decision:-none recorded}
- Artifacts: ${artifacts:-none yet}$pending_line

Say \"continue\" or run /angel:start to resume from here."
