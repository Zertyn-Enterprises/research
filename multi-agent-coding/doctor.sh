#!/usr/bin/env bash
# managed-by: multi-agent-coding
# doctor.sh — report what this machine has and what install.sh would touch.
# Read-only: it never creates, moves or edits a single file.
set -euo pipefail

KIT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ ! -f "$KIT_ROOT/lib/kit.sh" ]; then
  printf 'ERROR: missing package file: lib/kit.sh (expected %s/lib/kit.sh)\n' "$KIT_ROOT" >&2
  exit 1
fi
# shellcheck source=lib/kit.sh
. "$KIT_ROOT/lib/kit.sh"

usage() {
  cat <<USAGE
usage: bash doctor.sh [--prefix DIR] [--help]

Reports: operating system (macOS / Linux / WSL2), bash version, required and optional
dependencies, which agent CLIs are installed, the rules file size, the Codex byte cap,
whether this kit is already installed, and every file install.sh would back up.

  --prefix DIR   inspect this install prefix instead of \$MULTI_AGENT_CODING_HOME
                 (default: \$HOME/.multi-agent-coding)
  --help, -h     this text

Environment:
  MULTI_AGENT_CODING_HOME   install prefix (default \$HOME/.multi-agent-coding)
  CLAUDE_CONFIG_DIR         honoured when set: used instead of \$HOME/.claude
  MAC_SKIP_PATH_DETECT=1    detect CLIs by config dir only, ignoring PATH

Exit codes: 0 ready · 1 a hard dependency is missing (bash >= 3.2, git, rules file) · 2 usage.
Writes nothing, ever.
USAGE
}

while [ $# -gt 0 ]; do
  case "$1" in
    --help|-h) usage; exit 0 ;;
    --prefix) shift; [ $# -gt 0 ] || kit_usage_die "--prefix needs a directory"; KIT_PREFIX="$1" ;;
    --prefix=*) KIT_PREFIX="${1#--prefix=}" ;;
    *) usage >&2; kit_usage_die "unknown option: $1" ;;
  esac
  shift
done

kit_init
kit_doctor_report
