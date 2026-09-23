# angel plugin - development recipes. Run `just` to list them.

plugin := "plugins/angel"

default:
    @just --list

# Run the hook and script fixture tests
test:
    bash tests/run.sh

# Lint skills, agents and CLAUDE.md/AGENTS.md across the repo (plugin included) with the doc-audit script, plus shellcheck if installed
lint:
    bash {{plugin}}/scripts/lint-skills.sh .
    @if command -v shellcheck >/dev/null; then shellcheck -x {{plugin}}/hooks/*.sh {{plugin}}/scripts/*.sh tests/*.sh tests/*/*.sh; else echo "shellcheck not installed; skipping (brew install shellcheck)"; fi

# Validate the marketplace and plugin with Claude Code
validate:
    claude plugin validate .
    claude plugin validate {{plugin}}

# Everything that should pass before a commit
check: validate lint test

# Start Claude Code with the plugin loaded from the working tree (run /reload-plugins after edits)
dev *args:
    claude --plugin-dir "{{justfile_directory()}}/{{plugin}}" {{args}}
