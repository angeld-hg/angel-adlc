#!/usr/bin/env bash
# Run every tests/**/test_*.sh and fail if any of them fails.
set -uo pipefail

cd "$(dirname "$0")/.." || exit 1
status=0
for t in tests/hooks/test_*.sh tests/scripts/test_*.sh; do
  [ -f "$t" ] || continue
  printf '\n== %s\n' "$t"
  bash "$t" || status=1
done
exit "$status"
