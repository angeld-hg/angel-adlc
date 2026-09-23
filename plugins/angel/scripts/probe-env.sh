#!/usr/bin/env bash
# Deterministic facts about the repo and the machine, for /angel:discover.
#
# Prints markdown: what the repo is made of, which commands it defines, which CLIs
# are installed (and which ones the repo seems to need), whether they're
# authenticated or running, and what test/CI/runtime infrastructure exists.
#
# Read-only and local: it never reads .env contents, never deploys, never
# pushes. Every external command runs under a short timeout.
#
# Usage: probe-env.sh [repo root]   (default: the git top level, or cwd)

set -uo pipefail

root="${1:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
cd "$root" || exit 1
root="$(pwd)"

# Run a command with a timeout (macOS has no `timeout`; perl does).
t() {
  local secs="$1"
  shift
  perl -e 'alarm shift; exec @ARGV or exit 127' "$secs" "$@"
}
have() { command -v "$1" >/dev/null 2>&1; }
exists() { [ -e "$1" ]; }
first_line() { head -n 1 | cut -c1-80; }

echo "# Environment probe: $(basename "$root")"
echo
echo "Generated $(date '+%Y-%m-%d %H:%M') by probe-env.sh. Facts only; judgement is the repo-scout's job."

# ---------------------------------------------------------------- repo
echo
echo "## Repo"
if git rev-parse --git-dir >/dev/null 2>&1; then
  echo "- Remote: $(git remote get-url origin 2>/dev/null || echo 'none')"
  echo "- Current branch: $(git branch --show-current 2>/dev/null)"
  default="$(git symbolic-ref --quiet refs/remotes/origin/HEAD 2>/dev/null | sed 's|refs/remotes/origin/||')"
  echo "- Default branch: ${default:-unknown (no origin/HEAD)}"
  echo "- Commits: $(git rev-list --count HEAD 2>/dev/null || echo 0); last: $(git log -1 --format='%cs %s' 2>/dev/null | cut -c1-80)"
else
  echo "- Not a git repository"
fi
echo "- Top-level: $(find . -mindepth 1 -maxdepth 1 ! -name '.git' ! -name 'node_modules' ! -name '.venv' | sed 's|^\./||' | sort | tr '\n' ' ')"
echo "- Files by extension (tracked, top 8):"
git ls-files 2>/dev/null | sed -n 's/.*\.\([A-Za-z0-9]*\)$/\1/p' | sort | uniq -c | sort -rn | head -n 8 \
  | awk '{ printf "  - .%s: %s\n", $2, $1 }'
for doc in README.md AGENTS.md CLAUDE.md CONTRIBUTING.md; do
  exists "$doc" && echo "- Has $doc ($(wc -l <"$doc" | tr -d ' ') lines)"
done

# ---------------------------------------------------------------- stack
echo
echo "## Stack (manifests found)"
needs=() # CLIs the repo implies
found_any=0
manifest() { # <file> <label> <cli...>
  local f="$1" label="$2"
  shift 2
  if exists "$f"; then
    echo "- \`$f\`: $label"
    needs+=("$@")
    found_any=1
  fi
}
manifest package.json "Node.js" node
manifest pnpm-lock.yaml "pnpm" pnpm
manifest yarn.lock "Yarn" yarn
manifest bun.lockb "Bun" bun
manifest package-lock.json "npm" npm
manifest pyproject.toml "Python (pyproject)" python3
manifest uv.lock "uv" uv
manifest poetry.lock "Poetry" poetry
manifest requirements.txt "Python (pip)" python3
manifest go.mod "Go" go
manifest Cargo.toml "Rust" cargo
manifest pom.xml "Java (Maven)" mvn
manifest build.gradle "Java/Kotlin (Gradle)" gradle
manifest build.gradle.kts "Kotlin (Gradle)" gradle
manifest Gemfile "Ruby" ruby bundle
manifest composer.json "PHP" php composer
manifest mix.exs "Elixir" mix
ls ./*.csproj ./*.sln >/dev/null 2>&1 && { echo "- .NET project/solution"; needs+=(dotnet); found_any=1; }
manifest justfile "just recipes" just
exists justfile || manifest Justfile "just recipes" just
manifest Makefile "make targets" make
manifest Dockerfile "container image" docker
manifest docker-compose.yml "compose services" docker
manifest docker-compose.yaml "compose services" docker
manifest compose.yaml "compose services" docker
ls ./*.tf >/dev/null 2>&1 && { echo "- Terraform files"; needs+=(terraform); found_any=1; }
[ -d terraform ] || [ -d infra ] && echo "- Infra directory: $(ls -d terraform infra 2>/dev/null | tr '\n' ' ')"
[ "$found_any" -eq 1 ] || echo "- No recognised manifests"

# ---------------------------------------------------------------- commands
echo
echo "## Commands the repo defines"
if exists justfile || exists Justfile; then
  echo "### just"
  if have just; then
    t 10 just --list --unsorted 2>/dev/null | sed 1d | sed 's/^/    /'
  else
    echo "- justfile exists but \`just\` isn't installed"
  fi
fi
if exists package.json && have jq; then
  echo "### package.json scripts"
  jq -r '.scripts // {} | to_entries[] | "- `\(.key)`: \(.value)"' package.json 2>/dev/null | cut -c1-140
fi
if exists Makefile; then
  echo "### make targets"
  grep -E '^[A-Za-z0-9_.-]+:([^=]|$)' Makefile | cut -d: -f1 | sort -u | head -n 25 | sed 's/^/- /'
fi
if exists pyproject.toml; then
  echo "### pyproject"
  grep -nE '^\[(project\.scripts|tool\.(poe|pytest|ruff|mypy|hatch|poetry\.scripts|taskipy)[^]]*)\]' pyproject.toml | sed 's/^/- line /'
fi

# ---------------------------------------------------------------- CLIs
echo
echo "## CLIs"
echo "| CLI | Installed | Version | Repo needs it |"
echo "|---|---|---|---|"
clis=(git gh just make node npm pnpm yarn bun npx python3 uv poetry pip go cargo java mvn gradle dotnet ruby bundle php
  docker kubectl helm terraform aws gcloud az psql mysql sqlite3 redis-cli curl jq playwright)
for c in "${clis[@]}"; do
  need=""
  for n in "${needs[@]:-}"; do [ "$n" = "$c" ] && need="yes"; done
  if have "$c"; then
    case "$c" in
      java) v="$(t 5 java -version 2>&1 | first_line)" ;;
      go) v="$(t 5 go version 2>/dev/null | first_line)" ;;
      aws | gcloud | az | kubectl | helm | terraform) v="$(t 5 "$c" version 2>/dev/null | first_line)" ;;
      *) v="$(t 5 "$c" --version 2>/dev/null | first_line)" ;;
    esac
    echo "| $c | yes | ${v:-?} | ${need:-} |"
  elif [ -n "$need" ]; then
    echo "| $c | **NO** | | **yes (missing)** |"
  fi
done

# ---------------------------------------------------------------- access
echo
echo "## Access and runtime status"
if have gh; then
  if t 8 gh auth status >/dev/null 2>&1; then echo "- gh: authenticated"; else echo "- gh: **not authenticated** (gh auth login)"; fi
fi
if have docker; then
  if t 8 docker info >/dev/null 2>&1; then echo "- docker: daemon running"; else echo "- docker: **daemon not running**"; fi
fi
have kubectl && echo "- kubectl context: $(t 5 kubectl config current-context 2>/dev/null || echo none)"
have aws && echo "- aws profile: ${AWS_PROFILE:-default} ($(t 5 aws configure list 2>/dev/null | awk '/access_key/ { print ($2 == "<not" ? "no credentials configured" : "credentials configured") }'))"
have gcloud && echo "- gcloud account: $(t 5 gcloud config get-value account 2>/dev/null || echo none)"
have az && { t 8 az account show >/dev/null 2>&1 && echo "- az: logged in" || echo "- az: not logged in"; }
env_files="$(find . -maxdepth 2 -name '.env*' ! -path './node_modules/*' 2>/dev/null | sed 's|^\./||' | tr '\n' ' ')"
[ -n "$env_files" ] && echo "- Env files present (contents not read): $env_files"

# ---------------------------------------------------------------- tests and verification infra
echo
echo "## Test and verification infrastructure"
for f in jest.config.js jest.config.ts vitest.config.ts vitest.config.js pytest.ini conftest.py tox.ini noxfile.py \
  playwright.config.ts playwright.config.js cypress.config.ts cypress.config.js .mocharc.json karma.conf.js \
  phpunit.xml .rspec; do
  exists "$f" && echo "- \`$f\`"
done
grep -q '\[tool.pytest' pyproject.toml 2>/dev/null && echo "- pytest configured in pyproject.toml"
test_dirs="$(find . -maxdepth 3 -type d \( -name test -o -name tests -o -name __tests__ -o -name spec -o -name e2e -o -name integration \) \
  ! -path './node_modules/*' ! -path './.git/*' ! -path './.venv/*' 2>/dev/null | sed 's|^\./||' | tr '\n' ' ')"
echo "- Test directories: ${test_dirs:-none found}"
n_tests="$(git ls-files 2>/dev/null | grep -cE '(^|/)(test_[^/]*|[^/]*_test\.[a-z]+|[^/]*\.(test|spec)\.[a-z]+)$' || true)"
echo "- Test files (by naming convention): ${n_tests:-0}"

# ---------------------------------------------------------------- CI
echo
echo "## CI"
if [ -d .github/workflows ]; then
  for w in .github/workflows/*.y*ml; do
    [ -f "$w" ] || continue
    echo "- \`$w\`: $(grep -m1 -E '^name:' "$w" | sed 's/^name:[[:space:]]*//') (runs: $(grep -E '^[[:space:]]+run:' "$w" | sed 's/^[[:space:]]*run:[[:space:]]*//' | head -n 4 | tr '\n' ';' | cut -c1-120))"
  done
fi
for f in .gitlab-ci.yml azure-pipelines.yml .circleci/config.yml Jenkinsfile bitbucket-pipelines.yml; do
  exists "$f" && echo "- \`$f\`"
done
exists .pre-commit-config.yaml && echo "- pre-commit hooks configured"

# ---------------------------------------------------------------- running the app
echo
echo "## Running the app"
for f in docker-compose.yml docker-compose.yaml compose.yaml; do
  if exists "$f"; then
    echo "- Compose services ($f): $(grep -E '^  [A-Za-z0-9_-]+:$' "$f" | tr -d ' :' | tr '\n' ' ')"
    echo "- Published ports: $(grep -oE '"?[0-9]{2,5}:[0-9]{2,5}"?' "$f" | tr -d '"' | tr '\n' ' ')"
  fi
done
exists Procfile && echo "- Procfile: $(tr '\n' ';' <Procfile | cut -c1-120)"
if exists package.json && have jq; then
  for s in dev start serve preview; do
    v="$(jq -r --arg s "$s" '.scripts[$s] // empty' package.json 2>/dev/null)"
    [ -n "$v" ] && echo "- npm run $s: \`$v\`"
  done
fi
ports="$(git grep -hoE '(PORT|port)[^0-9]{1,10}[0-9]{4,5}' 2>/dev/null | grep -oE '[0-9]{4,5}' | sort | uniq -c | sort -rn | head -n 3 | awk '{ print $2 }' | tr '\n' ' ')"
[ -n "$ports" ] && echo "- Ports mentioned in code: $ports"
echo
echo "_End of probe._"
