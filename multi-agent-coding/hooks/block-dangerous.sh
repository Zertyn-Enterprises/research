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
# Both payload spellings are accepted, and `command` may be a string or an argv
# array:
#   {"tool_name":"Bash","tool_input":{"command":"…"}}                Claude Code, Codex
#   {"toolName":"run_terminal_command","toolInput":{"command":"…"}}  Grok Build
#
# Strategy:
#   1. Neutralize heredoc bodies and quoted strings (they are DATA, not argv).
#   2. Full-command patterns for things dangerous only in composition
#      (remote script piped to a shell, a write onto a raw device).
#   3. Per-segment argv-HEAD matching for everything else: a rule fires only when
#      the dangerous binary is what the segment actually RUNS, so a commit message
#      or an echo that merely mentions it stays data.
# Confirm-first families (installs, sudo, deploys, publishes) are NOT here —
# they live in config/permissions.json, which prompts instead of blocking.
#
# Exit 2 = block, with the reason on stderr for the agent to read.
# Exit 0 = allow, silently. Those two are the contract all three CLIs share.
set -uo pipefail

# Branches that move by PR only. Space-separated. An empty — or whitespace-only —
# value falls back to the default instead of silently disabling the protection.
PROTECTED_BRANCHES=$(printf '%s' "${MAC_PROTECTED_BRANCHES:-}" | tr '\t\n\r' '   ' | sed -E 's/  +/ /g; s/^ //; s/ $//')
[ -z "$PROTECTED_BRANCHES" ] && PROTECTED_BRANCHES="main master"

# Recursion budget. The hook re-runs itself on text piped into a shell; the depth
# rides in the environment so nested payloads cannot spin the machine. Beyond the
# limit it fails OPEN with a note — a hook that hangs protects nothing.
MAC_HOOK_DEPTH="${MAC_HOOK_DEPTH:-0}"
case "$MAC_HOOK_DEPTH" in ''|*[!0-9]*) MAC_HOOK_DEPTH=0 ;; esac

INPUT=$(cat 2>/dev/null || true)
[ -z "$INPUT" ] && exit 0

COMMAND=""
if command -v jq >/dev/null 2>&1; then
  COMMAND=$(printf '%s' "$INPUT" | jq -r '
    (.tool_input.command // .toolInput.command // empty)
    | if type == "array" then map(tostring) | join(" ") else tostring end' 2>/dev/null) || true
fi
if [ -z "$COMMAND" ]; then
  # jq-less fallback: keys off "command" alone, so it covers both spellings. The
  # string body is walked as escapes, so an embedded \" does not end it early.
  COMMAND=$(printf '%s' "$INPUT" \
    | sed -nE 's/.*"command"[[:space:]]*:[[:space:]]*"((\\.|[^"\\])*)".*/\1/p' 2>/dev/null | head -1) || true
  if [ -z "$COMMAND" ]; then
    # …and the argv-array spelling: "command": ["rm","-rf","/"]
    COMMAND=$(printf '%s' "$INPUT" \
      | sed -nE 's/.*"command"[[:space:]]*:[[:space:]]*\[([^]]*)\].*/\1/p' 2>/dev/null | head -1 \
      | sed -E 's/"[[:space:]]*,[[:space:]]*"/ /g; s/^[[:space:]]*"//; s/"[[:space:]]*$//') || true
  fi
  # \" and \\ are the escapes a shell command actually carries through JSON.
  COMMAND=$(printf '%s' "$COMMAND" | awk '{ out=""; n=length($0); i=1
    while (i <= n) {
      c=substr($0, i, 1)
      if (c == "\\" && i < n) {
        d=substr($0, i+1, 1)
        if (d == "\"" || d == "\\") { out=out d; i+=2; continue }
      }
      out=out c; i++
    }
    print out }')
fi
# Fail OPEN: three CLIs, three payload shapes, and a matcher may hand us a call
# that carries no command at all. A payload we cannot read is not evidence of a
# dangerous command, and blocking every unknown shape would break the CLI.
[ -z "$COMMAND" ] && exit 0

block() { echo "BLOCKED: $1" >&2; exit 2; }

# ── Size guard, and the one place this hook fails CLOSED. Every rule below is a
#    regex sweep plus a per-segment loop; a few hundred `true &&` segments of
#    padding would outrun the CLI's 10 s hook timeout, and a hook that times out
#    is a hook that did not block. A command that big is not one anyone needs to
#    run in a single call.
SEG_TOTAL=$(printf '%s' "$COMMAND" | awk '{ s += gsub(/[|;&]/, "&") } END { print s + NR }' 2>/dev/null) || true
case "$SEG_TOTAL" in ''|*[!0-9]*) SEG_TOTAL=1 ;; esac
if [ "$SEG_TOTAL" -gt 200 ] || [ "${#COMMAND}" -gt 16000 ]; then
  block "command too long for the safety hook ($SEG_TOTAL segments) — split it (Git & Safety §2)"
fi

# Regex alternation over the protected branches. Only `.` is escaped: branch
# names are [A-Za-z0-9._/-] in practice and `.` is the metacharacter that occurs.
PROT_RE=""
for _b in $PROTECTED_BRANCHES; do
  _e=$(printf '%s' "$_b" | sed 's/\./\\./g')
  if [ -z "$PROT_RE" ]; then PROT_RE="$_e"; else PROT_RE="$PROT_RE|$_e"; fi
done

# An interpreter reached by name or by absolute path, optionally behind sudo/env:
#   sh · /bin/bash · env bash · /usr/bin/env bash · sudo bash
BIN_PATH='(/[^[:space:]|;&]*/)?'
SHELL_RE="(sudo[[:space:]]+)?(${BIN_PATH}env[[:space:]]+)?${BIN_PATH}(ba|z|da|k)?sh"
INTERP_RE="(sudo[[:space:]]+)?(${BIN_PATH}env[[:space:]]+)?${BIN_PATH}((ba|z|da|k)?sh|python[0-9.]*|node|ruby|perl|php)"

# Word boundaries, spelled the POSIX way: \b is a GNU extension BSD grep lacks.
W='(^|[^[:alnum:]_])'
WE='([^[:alnum:]_]|$)'

# Credential files that are never an ordinary read target. Matched as a PATH — the
# optional prefix has to end in `/` — so `grep "\.ssh" src/` is a search, not a read.
SECRET_RE='(^|[[:space:]])([^[:space:]]*/)?(\.ssh([/[:space:]]|$)|\.aws/credentials|\.netrc([[:space:]]|$)|\.kube/config|\.docker/config\.json|etc/shadow)'

rm_target_is_root() { # <argument> → 0 when it resolves to /, the home dir, or a bare system root
  local t
  # `//` and `/tmp//x` are the same path, and a trailing `*` or `.` does not
  # narrow the target either, so both are normalized away before comparing.
  t=$(printf '%s' "$1" | sed -E 's#/{2,}#/#g; s#\*+$##')
  printf '%s' "$t" | grep -qE '^(/|~|\$HOME|\$\{HOME\})/?\.{0,2}$' && return 0
  printf '%s' "$t" | grep -qE '^/(Users|home|etc|usr|var|bin|sbin|lib|opt|System|Library|Applications|boot|root)/?$'
}

rm_root_delete() { # <segment whose argv head is rm> → 0 when it recursively deletes / the home or a system root
  local rest tok
  # Recursive is the flag that makes it fatal; -f only silences the prompt, and
  # `rm -r /` is exactly as final as `rm -rf /`.
  printf '%s' "$1" | grep -qE '(^|[[:space:]])(-[[:alnum:]]*[rR][[:alnum:]]*|--recursive)([[:space:]]|$)' || return 1
  rest="${1#"${1%%[[:space:]]*}"}"   # drop the `rm` head; what follows is argv
  while [ -n "$rest" ]; do
    case "$rest" in
      [[:space:]]*) rest="${rest#?}"; continue ;;
    esac
    tok="${rest%%[[:space:]]*}"
    case "$tok" in
      -*) ;;
      *) rm_target_is_root "$tok" && return 0 ;;
    esac
    rest="${rest#"$tok"}"
  done
  return 1
}

seg_head_strip() { # <segment> → the segment with `(` `{` `$(` backtick openers, wrappers, `sh -c` and VAR=value prefixes removed
  local s t rest drop_num=0 drop_file=0
  s=$(printf '%s' "$1" | sed -E 's/^[[:space:]({$`]+//; s/[[:space:])}`]+$//')
  while :; do
    t="${s%%[[:space:]]*}"
    [ "$t" = "$s" ] && break
    case "$t" in
      # drop the token itself (not "up to the first space": the separator may be a tab)
      sudo|command|nohup|time|exec|env|setsid|stdbuf|eval|builtin|-*|*=*)
        s="${s#"$t"}"; s="${s#"${s%%[![:space:]]*}"}" ;;
      # these carry a numeric argument of their own (`timeout 5 …`, `nice -n 19 …`)
      timeout|nice|ionice)
        drop_num=1; s="${s#"$t"}"; s="${s#"${s%%[![:space:]]*}"}" ;;
      # `script -q /dev/null <cmd>`: one file argument sits before the command
      script)
        drop_file=1; s="${s#"$t"}"; s="${s#"${s%%[![:space:]]*}"}" ;;
      # `sh -c <cmd>`: the real head is what follows -c (quotes were removed upstream)
      sh|bash|zsh|dash|ksh|*/sh|*/bash|*/zsh|*/dash|*/ksh)
        rest="${s#"$t"}"; rest="${rest#"${rest%%[![:space:]]*}"}"
        case "$rest" in
          -*c" "*|-*c"	"*) rest="${rest#-*c}"; s="${rest#"${rest%%[![:space:]]*}"}" ;;
          -*c) s="" ;;
          *) break ;;
        esac ;;
      *)
        if [ "$drop_file" = 1 ]; then
          drop_file=0
        elif [ "$drop_num" = 1 ]; then
          # a duration or priority argument, never a command name
          case "$t" in ''|*[!0-9.smhd]*) break ;; esac
        else
          break
        fi
        s="${s#"$t"}"; s="${s#"${s%%[![:space:]]*}"}" ;;
    esac
    # NOTE: sudo with flag-args (sudo -u root <cmd>) can still hide the head;
    # permissions.json asks on every Bash(sudo*) as the second layer.
  done
  printf '%s' "$s"
}

# ── Neutralize heredoc bodies (data, not commands) ──
STRIPPED=$(printf '%s\n' "$COMMAND" | awk '
  skip { if ($0 == term || $0 == "\t" term) { skip=0 }; next }
  {
    line=$0
    if (match(line, /<<-?[[:space:]]*["'\'']?[A-Za-z_][A-Za-z_0-9]*["'\'']?/)) {
      # A `<<` inside a quoted string (`echo "cfg << eol"`) is text, not a heredoc:
      # an odd number of quotes before it means we are inside one.
      pre=substr(line, 1, RSTART-1)
      dq=gsub(/"/, "", pre); sq=gsub(/'\''/, "", pre)
      if (dq % 2 == 0 && sq % 2 == 0) {
        t=substr(line, RSTART, RLENGTH)
        gsub(/<<-?[[:space:]]*/, "", t); gsub(/["'\'']/ , "", t)
        term=t; skip=1
      }
    }
    print line
  }')

# ── Blank quoted strings: their contents are arguments, never argv heads ──
ANALYZED=$(printf '%s' "$STRIPPED" | sed -E "s/'[^']*'/QSTR/g" | sed -E 's/"[^"]*"/QSTR/g')

# ── Quote CHARACTERS removed (not blanked), so a quoted `main` is still main and
#    `psql -c 'DROP TABLE x'` still reads as DROP TABLE. A separator INSIDE quotes
#    (`-m "a; reboot later"`) is neutralized first, so the split on | ; & below
#    never turns quoted prose into a segment of its own.
UNQUOTED=$(printf '%s\n' "$STRIPPED" | awk -v sq="'" '
  { line = $0; out = ""; n = length(line)
    for (i = 1; i <= n; i++) {
      c = substr(line, i, 1)
      if (q == "") {
        if (c == "\"" || c == sq) { q = c; continue }
        out = out c
      } else {
        if (c == q) { q = ""; continue }
        if (c == "|" || c == ";" || c == "&" || c == ">") c = "_"
        out = out c
      }
    }
    print out }')

# ── Full-command patterns ──
# A remote payload piped into any interpreter, not only a shell, and not only as
# the next stage: `curl … | tee /tmp/a | bash` is the same act.
if printf '%s' "$ANALYZED" | grep -qE "(^|[|;&[:space:]])(curl|wget)[^;&]*\|[[:space:]]*${INTERP_RE}([[:space:]]|\$)"; then
  block "piping a remote script to an interpreter (Git & Safety §2)"
fi
# Text piped into a shell (`echo 'rm -rf /' | sh`): the payload is on the RAW text,
# so run the same checks on it as if it were the command itself. Only a shell that
# READS its stdin counts — bare, or with flags such as `-`, `-s`, `-x`. A shell given
# a script operand (`| bash lint.sh`, `| bash "$HOME/…/block-dangerous.sh"`) runs the
# file, not the text; that is how this kit's own smoke test is spelled.
if printf '%s' "$ANALYZED" | grep -qE "(^|[|;&[:space:]])(echo|printf|cat)[^|;&]*\|[[:space:]]*${SHELL_RE}([[:space:]]+-[^[:space:]]*)*[[:space:]]*(\$|[;&|)])"; then
  PIPED=$(printf '%s' "$STRIPPED" \
    | sed -E "s#^[[:space:]]*(echo|printf|cat)[[:space:]]+(-[a-zA-Z]+[[:space:]]+)*##; s#[[:space:]]*\|[[:space:]]*${SHELL_RE}([[:space:]].*)?\$##" \
    | sed -e "s/^['\"]//" -e "s/['\"]\$//" -e 's/\\n$//')
  if [ -n "$PIPED" ] && [ "$PIPED" != "$STRIPPED" ]; then
    if [ "$MAC_HOOK_DEPTH" -ge 3 ]; then
      echo "note: block-dangerous.sh recursion depth $MAC_HOOK_DEPTH reached; nested payload not analyzed" >&2
    else
      # Run this very hook on the piped text: one set of rules, no second copy.
      if command -v jq >/dev/null 2>&1; then
        payload=$(jq -cn --arg c "$PIPED" '{tool_name:"Bash",tool_input:{command:$c}}')
      else
        payload=$(printf '{"tool_name":"Bash","tool_input":{"command":"%s"}}' \
          "$(printf '%s' "$PIPED" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' | tr '\n' ' ')")
      fi
      printf '%s' "$payload" | MAC_HOOK_DEPTH=$((MAC_HOOK_DEPTH + 1)) bash "$0" >/dev/null 2>&1
      prc=$?
      # ONLY exit 2 is a verdict. Any other non-zero is the child failing (a
      # missing tool, a crash), and a broken child must not become a block.
      if [ "$prc" -eq 2 ]; then
        block "text piped into a shell that would run a blocked command (Git & Safety §2)"
      fi
    fi
  fi
fi
# A raw block device on the receiving end of a redirection is never a file write.
if printf '%s' "$UNQUOTED" | grep -qE '>>?\|?[[:space:]]*/dev/(sd|hd|vd|xvd|nvme|disk|mmcblk)'; then
  block "redirecting output onto a raw disk device (Git & Safety §2)"
fi

# ── Protected-branch push: judged per segment, with `git` at the argv head, on text
#    with heredocs removed and the quote CHARACTERS removed (not blanked). So a
#    quoted "main" is still main, while `echo "git push origin main"` is an echo.
if [ -n "$PROT_RE" ]; then
  while IFS= read -r pseg; do
    pseg=$(seg_head_strip "$pseg")
    [ -z "$pseg" ] && continue
    ptok="${pseg%%[[:space:]]*}"
    [ "${ptok##*/}" = "git" ] || continue
    # `-c key=value` and `-C dir` carry a separate value token; other flags do not.
    printf '%s' "$pseg" | grep -qE '^[^[:space:]]*git([[:space:]]+(-[cC][[:space:]]+[^[:space:]]+|-[^[:space:]]+))*[[:space:]]+push([[:space:]]|$)' || continue
    # a protected branch in ANY form: as branch, as force-prefixed refspec (`+main`),
    # as refspec destination (`HEAD:main`, `HEAD:refs/heads/main`), any remote.
    if printf '%s' "$pseg" | grep -qE '[[:space:]]push.*[[:space:]:+]('"$PROT_RE"')([[:space:]]|$|[)}`])' \
       || printf '%s' "$pseg" | grep -qE '[[:space:]]push.*refs/(heads|remotes/[^/[:space:]]+)/('"$PROT_RE"')([[:space:]]|$|[)}`])'; then
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

# ── Destructive data operations: only in a segment whose head is a database client
#    or a migration CLI. The SQL rides inside quotes (psql -c '…'), so quotes are
#    removed, not blanked; heredoc bodies are already gone, so writing a migration
#    FILE is allowed — it is what the message asks for. `grep -i 'drop table'
#    schema.sql` merely mentions it.
while IFS= read -r sseg; do
  sseg=$(seg_head_strip "$sseg")
  [ -z "$sseg" ] && continue
  stok="${sseg%%[[:space:]]*}"
  case "${stok##*/}" in
    psql|mysql|mariadb|sqlite3|sqlcmd|clickhouse-client|cockroach|duckdb|usql) ;;
    dropdb)
      block "destructive database operation — commit a migration file instead (Git & Safety §7)" ;;
    redis-cli)
      printf '%s' "$sseg" | grep -qiE "${W}(flushall|flushdb)${WE}" \
        && block "flushing a Redis database — commit a migration file instead (Git & Safety §7)"
      continue ;;
    mongo|mongosh)
      printf '%s' "$sseg" | grep -qE "${W}dropDatabase" \
        && block "destructive database operation — commit a migration file instead (Git & Safety §7)"
      continue ;;
    prisma|supabase|npx|pnpm|npm|yarn|bun|bunx)
      # `prisma migrate reset` and `supabase db reset` drop and recreate the whole
      # database, in any runner spelling (`npx …`, `pnpm …`).
      printf '%s' "$sseg" | grep -qE "${W}prisma[[:space:]]+migrate[[:space:]]+reset${WE}" \
        && block "a migration reset drops the database — a human applies it (Git & Safety §7)"
      case "${stok##*/}" in
        supabase) _re="${W}db[[:space:]]+reset${WE}" ;;
        *) _re="${W}supabase[[:space:]]+db[[:space:]]+reset${WE}" ;;
      esac
      printf '%s' "$sseg" | grep -qE "$_re" \
        && block "a migration reset drops the database — a human applies it (Git & Safety §7)"
      continue ;;
    *) continue ;;
  esac
  if printf '%s' "$sseg" | grep -qiE "${W}drop[[:space:]]+(table|database|schema)${WE}"; then
    block "destructive database operation — commit a migration file instead (Git & Safety §7)"
  fi
  if printf '%s' "$sseg" | grep -qiE "${W}truncate${WE}"; then
    block "mass data deletion — commit a migration file instead (Git & Safety §7)"
  fi
  # A DELETE with no WHERE at all, or one whose WHERE is `1`, empties the table.
  if printf '%s' "$sseg" | grep -qiE "${W}delete[[:space:]]+from${WE}"; then
    if ! printf '%s' "$sseg" | grep -qiE "${W}where${WE}"; then
      block "mass data deletion — commit a migration file instead (Git & Safety §7)"
    fi
    if printf '%s' "$sseg" | grep -qiE "${W}where[[:space:]]+1"; then
      block "mass data deletion — commit a migration file instead (Git & Safety §7)"
    fi
  fi
done <<EOF
$(printf '%s\n' "$UNQUOTED" | tr '|;&' '\n\n\n')
EOF

# ── Writes to a real env file: redirection (with or without a space, `>|` too),
#    tee, cp, mv — in any directory. `.env.example` / `.env.sample` /
#    `.env.template` are documentation and stay open, as target AND as source.
ENV_FILE='([^[:space:]]*/)?\.env(\.[A-Za-z0-9_.-]+)?'
ENV_END='([[:space:]]|$|[;&|)])'
env_target_hit() { # <text> <ere-with-ENV_FILE> → 0 when a matched target is a REAL env file
  # The exemption is per matched target, not per command: `cp secrets .env` writes
  # .env even when an example file appears in the same segment.
  local hit
  hit=$(printf '%s' "$1" | grep -oE "$2") || return 1
  printf '%s\n' "$hit" | grep -vE '\.env\.(example|sample|template)'"$ENV_END" | grep -q .
}
# Judged on the quote-stripped text (a `>` inside quotes was neutralized above): an
# unquoted `>` followed by `.env` or `".env"` is a redirection, while a commit
# message that says "> .env" is a string.
if env_target_hit "$UNQUOTED" ">>?\|?[[:space:]]*${ENV_FILE}${ENV_END}"; then
  block "direct write to a .env file — use the platform's env vars (Git & Safety §1)"
fi
while IFS= read -r eseg; do
  eseg=$(seg_head_strip "$eseg")
  [ -z "$eseg" ] && continue
  etok="${eseg%%[[:space:]]*}"
  case "${etok##*/}" in
    tee|cp|mv|install)
      # the write target is the LAST argument for cp/mv/install; any argument for tee
      if [ "${etok##*/}" = "tee" ]; then
        env_target_hit "$eseg" "[[:space:]]${ENV_FILE}${ENV_END}" \
          && block "direct write to a .env file — use the platform's env vars (Git & Safety §1)"
      else
        # copying FROM the committed example is the standard bootstrap, not a leak
        printf '%s' "$eseg" \
          | grep -qE "[[:space:]]([^[:space:]]*/)?\.env\.(example|sample|template)[[:space:]]+[^[:space:]]" \
          && continue
        env_target_hit "$eseg" "[[:space:]]${ENV_FILE}[[:space:]]*$" \
          && block "direct write to a .env file — use the platform's env vars (Git & Safety §1)"
      fi ;;
  esac
done <<EOF
$(printf '%s\n' "$UNQUOTED" | tr '|;&' '\n\n\n')
EOF

# ── Per-segment argv-head checks ──
# tr, not sed: a newline in a sed replacement is not portable across BSD/GNU.
# Quote CHARACTERS removed, not blanked: the head is judged after wrapper stripping,
# so `bash -c "shutdown -h now"` reaches `shutdown` while `echo "shutdown"` stays echo.
SEGS=$(printf '%s\n' "$UNQUOTED" | tr '|;&' '\n\n\n')
while IFS= read -r seg; do
  # wrappers and env-assignment prefixes stripped to reach the real head — judged
  # on the FIRST TOKEN only, so 'dd if=…' is never read as VAR=value
  seg=$(seg_head_strip "$seg")
  [ -z "$seg" ] && continue
  head_tok="${seg%%[[:space:]]*}"
  head_base="${head_tok##*/}"

  case "$head_base" in
    shutdown|reboot|halt|poweroff)
      block "system power command (Git & Safety §2)" ;;
    systemctl)
      printf '%s' "$seg" | grep -qE '(^|[[:space:]])(poweroff|reboot|halt)([[:space:]]|$)' \
        && block "system power command (Git & Safety §2)" ;;
    launchctl)
      printf '%s' "$seg" | grep -qE '(^|[[:space:]])reboot([[:space:]]|$)' \
        && block "system power command (Git & Safety §2)" ;;
    mkfs|mkfs.*|mke2fs|mkswap|newfs*|wipefs|sgdisk|shred|fdisk|parted)
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
        block "recursive delete of /, the home dir or a system root (Git & Safety §2)"
      fi ;;
    chmod)
      if printf '%s' "$seg" | grep -qE '(-R|--recursive)' \
         && printf '%s' "$seg" | grep -qE '(^|[[:space:]])(0?777|([ugoa]*[ao][ugoa]*)?[+=]rwx)([[:space:]]|$)'; then
        block "recursive chmod granting world write and execute (Git & Safety §2)"
      fi ;;
    cat|head|tail|less|more|bat|base64|strings|xxd|od|cp|scp|rsync|tar|grep|awk|sed)
      printf '%s' "$seg" | grep -qE "$SECRET_RE" \
        && block "reading or copying SSH keys / credential files (Git & Safety §1)" ;;
  esac
done <<<"$SEGS"

exit 0
