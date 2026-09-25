#!/usr/bin/env bash
# managed-by: multi-agent-coding
#
# block-dangerous.sh — PreToolUse hard floor for shell commands.
#
# Wired as a PreToolUse hook in every CLI this kit supports. The matcher in the
# CLI's own config decides WHICH tool triggers it (Claude Code and Codex call it
# `Bash`; Grok Build maps that to `run_terminal_command`), so this script never
# looks at the tool name — it only inspects the command it was handed.
#
# Both payload spellings are accepted:
#   {"tool_name":"Bash","tool_input":{"command":"…"}}                Claude Code, Codex
#   {"toolName":"run_terminal_command","toolInput":{"command":"…"}}  Grok Build
#
# Strategy:
#   1. Neutralize heredoc bodies and quoted strings (they are DATA, not argv).
#   2. Full-command patterns for things dangerous only in composition
#      (remote script piped to a shell, push to a protected branch in any form).
#   3. Per-segment argv-HEAD matching for destructive binaries.
# Confirm-first families (installs, sudo, deploys, publishes) are NOT here —
# they live in config/permissions.json, which prompts instead of blocking.
#
# Exit 2 = block, with the reason on stderr for the agent to read.
# Exit 0 = allow, silently. Those two are the contract all three CLIs share.
set -uo pipefail

# Branches that move by PR only. Space-separated. An empty value falls back to
# the default instead of silently disabling the protection.
PROTECTED_BRANCHES="${MAC_PROTECTED_BRANCHES:-main master}"

INPUT=$(cat 2>/dev/null || true)
[ -z "$INPUT" ] && exit 0

COMMAND=""
if command -v jq >/dev/null 2>&1; then
  COMMAND=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // .toolInput.command // empty' 2>/dev/null) || true
fi
if [ -z "$COMMAND" ]; then
  # jq-less fallback: keys off "command" alone, so it covers both spellings.
  COMMAND=$(printf '%s' "$INPUT" | sed -n 's/.*"command"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' 2>/dev/null | head -1) || true
fi
# Fail OPEN: three CLIs, three payload shapes, and a matcher may hand us a call
# that carries no command at all. A payload we cannot read is not evidence of a
# dangerous command, and blocking every unknown shape would break the CLI.
[ -z "$COMMAND" ] && exit 0

block() { echo "BLOCKED: $1" >&2; exit 2; }

# Regex alternation over the protected branches. Only `.` is escaped: branch
# names are [A-Za-z0-9._/-] in practice and `.` is the metacharacter that occurs.
PROT_RE=""
for _b in $PROTECTED_BRANCHES; do
  _e=$(printf '%s' "$_b" | sed 's/\./\\./g')
  if [ -z "$PROT_RE" ]; then PROT_RE="$_e"; else PROT_RE="$PROT_RE|$_e"; fi
done

# ── Root/home delete. The target must be exactly / ~ ~/ $HOME ${HOME}, optionally
#    with a trailing wildcard — `rm -rf /tmp/build` or `rm -rf ~/proj/dist` is
#    ordinary work. Flags may be short or long, combined or separate (-rf, -fr,
#    -r -f, --recursive --force, -f --recursive). Checked on the command with
#    heredocs removed but quotes intact, so `rm -rf "/"` cannot hide in quotes.
RM_TARGET='["'"'"']?(/|~|~/|\$HOME|\$HOME/|\$\{HOME\}|\$\{HOME\}/)(\*|/\*)?["'"'"']?'
rm_root_delete() { # <text> → 0 when an rm with recursive+force flags targets / or the home dir
  local m
  # Wrappers count: `sh -c "rm -rf /"`, `` `rm -rf /` `` and `$(rm -rf /)` are the
  # same command. A quote is a delimiter only right after `-c`, so a quoted
  # sentence that merely mentions the command (`echo "rm -rf / is bad"`) is data.
  m=$(printf '%s' "$1" | grep -oE "(^|[[:space:];&|(\`]|-c[[:space:]]+[\"'])rm([[:space:]]+-[^[:space:]]+)+[[:space:]]+${RM_TARGET}([[:space:]]|\$|[;&|)\`])") || return 1
  printf '%s' "$m" | grep -qE '(^|[[:space:]])(-[[:alnum:]]*[rR][[:alnum:]]*|--recursive)([[:space:]]|$)' \
    && printf '%s' "$m" | grep -qE '(^|[[:space:]])(-[[:alnum:]]*[fF][[:alnum:]]*|--force)([[:space:]]|$)'
}

# ── Neutralize heredoc bodies (data, not commands) ──
STRIPPED=$(printf '%s\n' "$COMMAND" | awk '
  skip { if ($0 == term || $0 == "\t" term) { skip=0 }; next }
  {
    line=$0
    if (match(line, /<<-?[[:space:]]*["'\'']?[A-Za-z_][A-Za-z_0-9]*["'\'']?/)) {
      t=substr(line, RSTART, RLENGTH)
      gsub(/<<-?[[:space:]]*/, "", t); gsub(/["'\'']/ , "", t)
      term=t; skip=1
    }
    print line
  }')

if rm_root_delete "$STRIPPED"; then
  block "recursive force delete of / or ~ (Git & Safety §2)"
fi

# ── Blank quoted strings: their contents are arguments, never argv heads ──
ANALYZED=$(printf '%s' "$STRIPPED" | sed -E "s/'[^']*'/QSTR/g" | sed -E 's/"[^"]*"/QSTR/g')

# ── Full-command patterns ──
# A remote payload piped into any interpreter, not only a shell.
if printf '%s' "$ANALYZED" | grep -qE '(^|[|;&[:space:]])(curl|wget)[^|;&]*\|[[:space:]]*(sudo[[:space:]]+)?(env[[:space:]]+)?((ba|z|da|k)?sh|python[0-9.]*|node|ruby|perl|php)([[:space:]]|$)'; then
  block "piping a remote script to an interpreter (Git & Safety §2)"
fi

# ── Protected-branch push: judged per segment, with `git` at the argv head, on text
#    with heredocs removed and the quote CHARACTERS removed (not blanked). So a
#    quoted "main" is still main, while `echo "git push origin main"` is an echo.
if [ -n "$PROT_RE" ]; then
  UNQUOTED=$(printf '%s' "$STRIPPED" | sed -e "s/'//g" -e 's/"//g')
  while IFS= read -r pseg; do
    # ltrim spaces and the subshell/group openers `(` `{`, so `(git push …)` is a git
    pseg=$(printf '%s' "$pseg" | sed -E 's/^[[:space:]({]+//')
    [ -z "$pseg" ] && continue
    while :; do   # same wrapper / env-assignment stripping as the argv-head loop below
      ptok="${pseg%%[[:space:]]*}"
      [ "$ptok" = "$pseg" ] && break
      case "$ptok" in
        sudo|command|nohup|time|exec|env|-*|*=*) pseg="${pseg#* }"; pseg="${pseg#"${pseg%%[![:space:]]*}"}" ;;
        *) break ;;
      esac
    done
    ptok="${pseg%%[[:space:]]*}"
    [ "${ptok##*/}" = "git" ] || continue
    printf '%s' "$pseg" | grep -qE '^[^[:space:]]*git([[:space:]]+-C[[:space:]]+[^[:space:]]+)?([[:space:]]+-[^[:space:]]+)*[[:space:]]+push([[:space:]]|$)' || continue
    # a protected branch in ANY form: as branch, as refspec destination (`HEAD:main`,
    # `HEAD:refs/heads/main`), any remote.
    if printf '%s' "$pseg" | grep -qE '[[:space:]]push.*[[:space:]:]('"$PROT_RE"')([[:space:]]|$|[)}])' \
       || printf '%s' "$pseg" | grep -qE '[[:space:]]push.*refs/(heads|remotes/[^/[:space:]]+)/('"$PROT_RE"')([[:space:]]|$|[)}])'; then
      block "push to a protected branch ($PROTECTED_BRANCHES), any remote or refspec form — it moves by PR only (Git & Safety §3)"
    fi
    # bare `git push` (no explicit target): dangerous only when the branch IS protected
    if ! printf '%s' "$pseg" | grep -qE '[[:space:]]push([[:space:]]+-[^[:space:]]+)*[[:space:]]+[^-[:space:]]'; then
      CWD=""
      if command -v jq >/dev/null 2>&1; then
        CWD=$(printf '%s' "$INPUT" | jq -r '.cwd // empty' 2>/dev/null) || true
      fi
      BR=$(git -C "${CWD:-.}" rev-parse --abbrev-ref HEAD 2>/dev/null) || BR=""
      if [ -n "$BR" ]; then
        for _b in $PROTECTED_BRANCHES; do
          if [ "$BR" = "$_b" ]; then
            block "bare 'git push' while on $BR — a protected branch moves by PR only (Git & Safety §3)"
          fi
        done
      fi
    fi
  done <<EOF
$(printf '%s\n' "$UNQUOTED" | tr '|;&' '\n\n\n')
EOF
fi

# SQL rides inside quotes (psql -c '…'), so these two run on the RAW command.
if printf '%s' "$COMMAND" | grep -qiE '\bdrop[[:space:]]+(table|database|schema)\b'; then
  block "destructive database operation — commit a migration file instead (Git & Safety §7)"
fi
if printf '%s' "$COMMAND" | grep -qiE '\bdelete[[:space:]]+from\b[^|;&]*\bwhere[[:space:]]+1\b'; then
  block "mass data deletion — commit a migration file instead (Git & Safety §7)"
fi

case "$ANALYZED" in
  *"> .env"*|*">> .env"*|*"> .env."*|*">> .env."*)
    block "direct write to a .env file — use the platform's env vars (Git & Safety §1)" ;;
esac

if printf '%s' "$ANALYZED" | grep -qE '(^|[|;&[:space:]])(cat|head|tail|less|more|bat|base64|strings|xxd|cp|scp)[[:space:]][^|;&]*(\.ssh/|/etc/shadow)'; then
  block "reading SSH keys or system credential files (Git & Safety §1)"
fi
# quoted-path variant: the path hides inside QSTR, so also check the raw command
if printf '%s' "$COMMAND" | grep -qE '(^|[|;&[:space:]])(cat|head|tail|less|more|bat|base64|strings|xxd|cp|scp)[[:space:]][^|;&]*\.ssh/'; then
  block "reading SSH keys (quoted path) (Git & Safety §1)"
fi

# ── Per-segment argv-head checks ──
# tr, not sed: a newline in a sed replacement is not portable across BSD/GNU.
SEGS=$(printf '%s\n' "$ANALYZED" | tr '|;&' '\n\n\n')
while IFS= read -r seg; do
  seg=$(printf '%s' "$seg" | sed -E 's/^[[:space:]({]+//')   # ltrim, incl. `(` and `{` openers
  [ -z "$seg" ] && continue
  # strip wrappers and env-assignment prefixes to reach the real head — judged
  # on the FIRST TOKEN only, so 'dd if=…' is never read as VAR=value
  while :; do
    head_tok="${seg%%[[:space:]]*}"
    [ "$head_tok" = "$seg" ] && break
    case "$head_tok" in
      sudo|command|nohup|time|exec|env) seg="${seg#* }"; seg="${seg#"${seg%%[![:space:]]*}"}" ;;
      -*)                               seg="${seg#* }"; seg="${seg#"${seg%%[![:space:]]*}"}" ;;
      *=*)                              seg="${seg#* }"; seg="${seg#"${seg%%[![:space:]]*}"}" ;;
      *) break ;;
    esac
    # NOTE: sudo with flag-args (sudo -u root <cmd>) can still hide the head;
    # permissions.json asks on every Bash(sudo*) as the second layer.
  done
  head_tok="${seg%%[[:space:]]*}"
  head_base="${head_tok##*/}"

  case "$head_base" in
    shutdown|reboot|halt|poweroff)
      block "system power command (Git & Safety §2)" ;;
    mkfs|mkfs.*|fdisk|parted)
      block "disk-destructive command: $head_base (Git & Safety §2)" ;;
    diskutil)
      case "$seg" in
        *erase*|*partition*|*reformat*|*deleteContainer*|*deleteVolume*)
          block "disk-destructive diskutil operation (Git & Safety §2)" ;;
      esac ;;
    dd)
      case "$seg" in
        *of=/dev/*) block "dd writing to a raw device (Git & Safety §2)" ;;
      esac ;;
    tccutil)
      block "modifying the system permission database (Git & Safety §2)" ;;
    rm)
      if rm_root_delete "$seg"; then
        block "recursive force delete of / or ~ (Git & Safety §2)"
      fi ;;
    chmod)
      if printf '%s' "$seg" | grep -qE '(-R|--recursive)' && printf '%s' "$seg" | grep -qE '[[:space:]]0?777([[:space:]]|$)'; then
        block "chmod -R 777 (Git & Safety §2)"
      fi ;;
  esac
done <<<"$SEGS"

exit 0
