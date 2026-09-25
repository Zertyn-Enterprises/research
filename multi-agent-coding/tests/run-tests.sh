#!/usr/bin/env bash
# managed-by: multi-agent-coding
# Runs every tests/test-*.sh. Green means: at least one test ran, nothing failed, nothing skipped.
# Exit 1 on any failure, 3 when a test skipped (a skip is not a pass), 0 otherwise.
set -uo pipefail
cd "$(dirname "$0")"

ran=0; failed=0; skipped=0
for t in test-*.sh; do
  [ -f "$t" ] || continue
  ran=$((ran + 1))
  bash "$t"; rc=$?
  case $rc in
    0) ;;
    3) skipped=$((skipped + 1)) ;;
    *) failed=$((failed + 1)) ;;
  esac
done

echo "----"
echo "files: $ran  failed: $failed  skipped: $skipped"
[ "$ran" -gt 0 ] || { echo "no tests found" >&2; exit 1; }
[ "$failed" -eq 0 ] || exit 1
[ "$skipped" -eq 0 ] || { echo "not green: skipped tests (a skip is not a pass)"; exit 3; }
echo "ALL GREEN"
