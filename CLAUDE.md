@AGENTS.md

## Claude Code notes

- After editing skills, agents or hooks, run `/reload-plugins` in any session using `just dev`, or
  the changes won't apply.
- HG's company `adlc` plugin also injects a pipeline at SessionStart. When dogfooding `angel` in a
  scratch repo, disable it there (`.claude/settings.local.json`:
  `{"enabledPlugins": {"adlc@hg-claude-code-plugin-marketplace": false}}`) so the two orchestrators
  don't compete.
