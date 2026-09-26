# managed-by: multi-agent-coding
# Shared test helpers. Source from tests/test-*.sh:
#   source "$(dirname "$0")/lib.sh"
# Exports KIT (package root) and a throwaway HOME so no test touches the real one.
# A skipped test never counts as green: t_done exits 3 when anything was skipped.

set -u

KIT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_HOME="$(mktemp -d "${TMPDIR:-/tmp}/mac-test.XXXXXX")"
export HOME="$TMP_HOME"
export MULTI_AGENT_CODING_HOME="$TMP_HOME/.multi-agent-coding"
unset CLAUDE_CONFIG_DIR
mkdir -p "$HOME"

_pass=0; _fail=0; _skip=0
_name="$(basename "${0:-test}")"

_cleanup() { rm -rf "$TMP_HOME"; }
trap _cleanup EXIT

t_ok()   { _pass=$((_pass + 1)); printf '  ok   %s\n' "$1"; }
t_bad()  { _fail=$((_fail + 1)); printf '  FAIL %s\n' "$1" >&2; [ $# -gt 1 ] && printf '       %s\n' "$2" >&2; }

t_assert() { # t_assert "description" cmd args...
  local d="$1"; shift
  if "$@" >/dev/null 2>&1; then t_ok "$d"; else t_bad "$d" "command failed: $*"; fi
}

t_assert_fail() { # passes when the command exits non-zero
  local d="$1"; shift
  if "$@" >/dev/null 2>&1; then t_bad "$d" "expected non-zero exit: $*"; else t_ok "$d"; fi
}

t_assert_eq() { # t_assert_eq "description" expected actual
  if [ "$2" = "$3" ]; then t_ok "$1"; else t_bad "$1" "expected [$2] got [$3]"; fi
}

t_assert_grep() { # t_assert_grep "description" pattern file
  if grep -Eq -- "$2" "$3" 2>/dev/null; then t_ok "$1"; else t_bad "$1" "pattern not found: $2 in $3"; fi
}

t_assert_not_grep() {
  if grep -Eq -- "$2" "$3" 2>/dev/null; then t_bad "$1" "pattern must not appear: $2 in $3"; else t_ok "$1"; fi
}

t_skip() { _skip=$((_skip + 1)); printf '  SKIP %s\n' "$1"; }

t_require() { # t_require binary — skip the whole file when a dependency is missing
  if ! command -v "$1" >/dev/null 2>&1; then
    t_skip "missing dependency: $1"
    t_done
  fi
}

t_done() {
  printf '%s: PASS %d FAIL %d SKIP %d\n' "$_name" "$_pass" "$_fail" "$_skip"
  if [ "$_fail" -gt 0 ]; then exit 1; fi
  if [ "$_skip" -gt 0 ]; then exit 3; fi
  if [ "$_pass" -eq 0 ]; then echo "  no assertions ran" >&2; exit 1; fi
  exit 0
}
