# managed-by: multi-agent-coding
# Shared helpers for install.sh, doctor.sh and uninstall.sh. Sourced, never executed.
#
# bash 3.2 compatible: no associative arrays, no mapfile, no ${var,,}, no sed -i.
# Every write goes through one of the kit_install_* / kit_json_* helpers, so --dry-run,
# backups, the manifest and the "never write outside HOME" rule hold in one place.
# A write whose result is byte-identical to what is already there is a no-op: that is
# what makes a second install change nothing at all.
#
# Callers set KIT_ROOT (package root) before sourcing, then call kit_init.

KIT_NAME="multi-agent-coding"
KIT_VERSION="0.1.0"
KIT_MARKER="managed-by: multi-agent-coding"
KIT_CODEX_CAP=131072

: "${KIT_ROOT:=}"
: "${KIT_DRY_RUN:=0}"
: "${KIT_LINK:=0}"
KIT_BACKED_UP=""
KIT_JSON_CHANGED=0

# ---------------------------------------------------------------- output

kit_say()  { printf '%s\n' "$*"; }
kit_info() { printf '  %s\n' "$*"; }
kit_warn() { printf 'WARNING: %s\n' "$*" >&2; }
kit_err()  { printf 'ERROR: %s\n' "$*" >&2; }
kit_die()  { kit_err "$*"; exit 1; }
kit_usage_die() { kit_err "$*"; exit 2; }

kit_ts() { date +%Y%m%d-%H%M%S; }

kit_have() { command -v "$1" >/dev/null 2>&1; }

# ---------------------------------------------------------------- environment

kit_os() {
  case "$(uname -s)" in
    Darwin) printf 'macOS\n' ;;
    Linux)
      if grep -qi microsoft /proc/version 2>/dev/null; then printf 'WSL2\n'; else printf 'Linux\n'; fi ;;
    *) uname -s ;;
  esac
}

kit_bash_version() { printf '%s\n' "${BASH_VERSION:-unknown}"; }

kit_bash_ok() { # bash 3.2 or newer
  local major="${BASH_VERSINFO[0]:-0}" minor="${BASH_VERSINFO[1]:-0}"
  if [ "$major" -gt 3 ]; then return 0; fi
  if [ "$major" -eq 3 ] && [ "$minor" -ge 2 ]; then return 0; fi
  return 1
}

kit_init() { # resolve the install prefix and the per-CLI directories
  [ -n "$KIT_ROOT" ] || kit_die "KIT_ROOT is not set (internal error)"
  [ -n "${HOME:-}" ] || kit_die "HOME is not set"
  if [ -z "${KIT_PREFIX:-}" ]; then
    KIT_PREFIX="${MULTI_AGENT_CODING_HOME:-$HOME/.$KIT_NAME}"
  fi
  case "$KIT_PREFIX" in
    "$HOME"/*) : ;;
    *) kit_die "the install prefix must live inside HOME, got: $KIT_PREFIX" ;;
  esac
  KIT_CLAUDE_DIR="$HOME/.claude"
  KIT_CLAUDE_DIR_SOURCE="default"
  if [ -n "${CLAUDE_CONFIG_DIR:-}" ]; then
    KIT_CLAUDE_DIR="$CLAUDE_CONFIG_DIR"
    KIT_CLAUDE_DIR_SOURCE="CLAUDE_CONFIG_DIR"
  fi
  KIT_CODEX_DIR="$HOME/.codex"
  KIT_GROK_DIR="$HOME/.grok"
  KIT_SETTINGS="$KIT_CLAUDE_DIR/settings.json"
  KIT_MANIFEST="$KIT_PREFIX/manifest.txt"
}

# ---------------------------------------------------------------- detection
# A CLI counts as present when its binary is on PATH or its config dir exists.
# MAC_SKIP_PATH_DETECT=1 restricts detection to config dirs (sandboxes, test suite).

kit_cli_present() { # kit_cli_present <binary> <config-dir>
  if [ "${MAC_SKIP_PATH_DETECT:-0}" != "1" ] && kit_have "$1"; then return 0; fi
  [ -d "$2" ]
}

kit_has_claude() { kit_cli_present claude "$KIT_CLAUDE_DIR"; }
kit_has_codex()  { kit_cli_present codex  "$KIT_CODEX_DIR"; }
kit_has_grok()   { kit_cli_present grok   "$KIT_GROK_DIR"; }

kit_cli_state() { # kit_cli_state <binary> <config-dir> -> one human readable line
  local how=""
  if [ "${MAC_SKIP_PATH_DETECT:-0}" != "1" ] && kit_have "$1"; then how="binary on PATH"; fi
  if [ -d "$2" ]; then
    if [ -n "$how" ]; then how="$how + config dir"; else how="config dir $2"; fi
  fi
  if [ -n "$how" ]; then printf 'present (%s)\n' "$how"; else printf 'not found\n'; fi
}

# ---------------------------------------------------------------- ownership

kit_assert_in_home() {
  case "$1" in
    "$HOME"/*) return 0 ;;
    *) kit_die "refusing to write outside HOME: $1" ;;
  esac
}

kit_is_ours() { # our marker in the head of the file, or a link into the prefix/checkout
  local p="$1" t
  if [ -L "$p" ]; then
    t="$(readlink "$p")"
    case "$t" in
      "$KIT_PREFIX"/*|"$KIT_ROOT"/*) return 0 ;;
      *) return 1 ;;
    esac
  fi
  [ -f "$p" ] || return 1
  # 20 lines, not 1: an agent or skill file must open with its YAML frontmatter,
  # so its marker sits just below that block instead of on the first line.
  head -n 20 "$p" 2>/dev/null | grep -Fq -- "$KIT_MARKER"
}

kit_backup() { # back up a pre-existing file or link that is not ours
  local p="$1" b
  if [ ! -e "$p" ] && [ ! -L "$p" ]; then return 0; fi
  if kit_is_ours "$p"; then return 0; fi
  b="$p.bak-$(kit_ts)"
  if [ "$KIT_DRY_RUN" = "1" ]; then kit_say "would back up $p -> $(basename "$b")"; return 0; fi
  if [ -L "$p" ]; then cp -P "$p" "$b"; else cp -p "$p" "$b"; fi
  kit_say "backed up $p -> $(basename "$b")"
}

kit_backup_once() { # at most one backup per path per run (settings.json, config.toml)
  if printf '%s\n' "$KIT_BACKED_UP" | grep -Fqx -- "$1"; then return 0; fi
  KIT_BACKED_UP="$KIT_BACKED_UP
$1"
  kit_backup "$1"
}

# ---------------------------------------------------------------- manifest

kit_manifest_add() { # kit_manifest_add <kind> <path> — idempotent, never duplicates a line
  if [ "$KIT_DRY_RUN" = "1" ]; then return 0; fi
  local line
  line="$(printf '%s\t%s' "$1" "$2")"
  mkdir -p "$KIT_PREFIX"
  [ -f "$KIT_MANIFEST" ] || : > "$KIT_MANIFEST"
  if ! grep -Fqx -- "$line" "$KIT_MANIFEST"; then
    printf '%s\n' "$line" >> "$KIT_MANIFEST"
  fi
}

# ---------------------------------------------------------------- file writes

kit_mkdirp() {
  if [ "$KIT_DRY_RUN" = "1" ]; then return 0; fi
  mkdir -p "$1"
}

kit_require_pkg_file() { # fail loudly, naming the file, when the package is incomplete
  if [ ! -f "$KIT_ROOT/$1" ]; then
    kit_die "missing package file: $1 (expected $KIT_ROOT/$1) — incomplete checkout, nothing installed"
  fi
}

kit_install_file() { # kit_install_file <package-relative-src> <dest> [mode]
  local rel="$1" dest="$2" mode="${3:-}" src="$KIT_ROOT/$1"
  kit_assert_in_home "$dest"
  [ -f "$src" ] || kit_die "missing package file: $rel (expected $src)"
  if [ "$KIT_LINK" = "1" ]; then kit_install_link "$rel" "$dest"; return 0; fi
  if [ -f "$dest" ] && [ ! -L "$dest" ] && cmp -s "$src" "$dest"; then
    kit_manifest_add file "$dest"
    kit_info "unchanged $dest"
    return 0
  fi
  kit_backup "$dest"
  if [ "$KIT_DRY_RUN" = "1" ]; then kit_say "would write $dest"; return 0; fi
  kit_mkdirp "$(dirname "$dest")"
  rm -f "$dest"
  cp "$src" "$dest"
  if [ -n "$mode" ]; then chmod "$mode" "$dest"; fi
  kit_manifest_add file "$dest"
  kit_say "wrote $dest"
}

kit_install_link() { # kit_install_link <package-relative-src> <dest>
  local rel="$1" dest="$2" src="$KIT_ROOT/$1"
  [ -f "$src" ] || kit_die "missing package file: $rel (expected $src)"
  kit_link_to "$src" "$dest"
}

kit_link_to() { # kit_link_to <absolute-target> <dest>
  local target="$1" dest="$2"
  kit_assert_in_home "$dest"
  if [ -L "$dest" ] && [ "$(readlink "$dest")" = "$target" ]; then
    kit_manifest_add link "$dest"
    kit_info "unchanged $dest -> $target"
    return 0
  fi
  kit_backup "$dest"
  if [ "$KIT_DRY_RUN" = "1" ]; then kit_say "would link $dest -> $target"; return 0; fi
  kit_mkdirp "$(dirname "$dest")"
  rm -f "$dest"
  ln -sfn "$target" "$dest"
  kit_manifest_add link "$dest"
  kit_say "linked $dest -> $target"
}

kit_write_managed_json() { # kit_write_managed_json <dest> <json-text> — whole file is ours
  local dest="$1" body="$2" tmp
  kit_assert_in_home "$dest"
  if [ -f "$dest" ] && printf '%s\n' "$body" | cmp -s - "$dest"; then
    kit_info "unchanged $dest"
    return 0
  fi
  kit_backup "$dest"
  if [ "$KIT_DRY_RUN" = "1" ]; then kit_say "would write $dest"; return 0; fi
  kit_mkdirp "$(dirname "$dest")"
  tmp="$(mktemp "${TMPDIR:-/tmp}/mac.XXXXXX")"
  printf '%s\n' "$body" > "$tmp"
  mv "$tmp" "$dest"
  kit_say "wrote $dest"
}

# ---------------------------------------------------------------- JSON (jq)

kit_need_jq() {
  kit_have jq || kit_die "jq is required for this level (brew install jq / apt-get install jq)"
}

# kit_json_apply <file> <jq args...> : read (or {} when absent) -> transform -> validate
# -> compare -> back up once -> move into place. Sets KIT_JSON_CHANGED to 0 or 1.
kit_json_apply() {
  local f="$1"; shift
  kit_assert_in_home "$f"
  kit_need_jq
  local tmp rc=0
  KIT_JSON_CHANGED=0
  if [ -f "$f" ]; then
    jq -e . "$f" >/dev/null 2>&1 || kit_die "$f is not valid JSON — fix it or move it aside, then re-run"
  fi
  tmp="$(mktemp "${TMPDIR:-/tmp}/mac.XXXXXX")"
  if [ -f "$f" ]; then
    jq "$@" < "$f" > "$tmp" || rc=1
  else
    printf '%s\n' '{}' | jq "$@" > "$tmp" || rc=1
  fi
  if [ "$rc" -ne 0 ] || ! jq -e . "$tmp" >/dev/null 2>&1; then
    rm -f "$tmp"
    kit_die "failed to update $f (the jq transform produced nothing valid)"
  fi
  if [ -f "$f" ] && cmp -s "$tmp" "$f"; then
    rm -f "$tmp"
    return 0
  fi
  KIT_JSON_CHANGED=1
  if [ "$KIT_DRY_RUN" = "1" ]; then
    rm -f "$tmp"
    if [ -f "$f" ]; then kit_backup_once "$f"; else kit_say "would create $f"; fi
    return 0
  fi
  kit_mkdirp "$(dirname "$f")"
  kit_backup_once "$f"
  mv "$tmp" "$f"
}

kit_json_note() { # kit_json_note <file> <what> — one line, honest in every mode
  if [ "$KIT_JSON_CHANGED" != "1" ]; then kit_info "unchanged $2 in $1"; return 0; fi
  if [ "$KIT_DRY_RUN" = "1" ]; then kit_say "would set $2 in $1"; else kit_say "set $2 in $1"; fi
}

# Merge a {"<Event>":[{matcher,hooks:[...]}]} fragment under .hooks.
# Idempotent: a hook whose command string already exists in that event is skipped; a group
# with the same matcher is extended instead of duplicated. Foreign entries are never touched.
KIT_JQ_ADD_HOOKS='
def addhooks($arr; $g):
  ($arr | map(.hooks // []) | flatten | map(.command)) as $known
  | (($g.hooks // []) | map(select(.command as $c | ($known | index($c)) == null))) as $add
  | if ($add | length) == 0 then $arr
    else
      ([range(0; ($arr | length))] | map(. as $i | select($arr[$i].matcher == $g.matcher))) as $idx
      | if ($idx | length) > 0
        then ($idx[0]) as $i | ($arr | .[$i].hooks = ((.[$i].hooks // []) + $add))
        else $arr + [ ($g | .hooks = $add) ]
        end
    end;
reduce ($frag | to_entries[]) as $e (.;
  .hooks = (.hooks // {})
  | .hooks[$e.key] = (reduce ($e.value[]) as $g ((.hooks[$e.key] // []); addhooks(.; $g)))
)'

# Remove only hooks whose command contains $pfx. A group is dropped only when every hook
# in it was ours; an event is dropped only when it has no groups left.
KIT_JQ_DEL_HOOKS='
if (.hooks | type) == "object" then
  .hooks |= with_entries(
    .value |= map(
      . as $g
      | (($g.hooks // []) | map(select((.command // "") | contains($pfx) | not))) as $kept
      | if ($kept | length) == (($g.hooks // []) | length) then $g
        elif ($kept | length) == 0 then empty
        else ($g | .hooks = $kept) end
    )
  )
  | .hooks |= with_entries(select((.value | length) > 0))
  | if (.hooks | length) == 0 then del(.hooks) else . end
else . end'

# Union our deny/ask entries into .permissions. Order preserving, deduplicated,
# and it never reads or writes defaultMode or any other key.
KIT_JQ_ADD_PERMS='
reduce ("deny", "ask") as $k (.;
  if (($frag[$k] // []) | length) == 0 then .
  else
    .permissions = (.permissions // {})
    | .permissions[$k] = (reduce (($frag[$k] // [])[]) as $x
        ((.permissions[$k] // []); if index($x) then . else . + [$x] end))
  end)'

KIT_JQ_DEL_PERMS='
if (.permissions | type) == "object" then
  reduce ("deny", "ask") as $k (.;
    if (.permissions[$k] | type) == "array"
    then .permissions[$k] = (.permissions[$k] - ($frag[$k] // []))
         | (if (.permissions[$k] | length) == 0 then del(.permissions[$k]) else . end)
    else . end)
  | (if (.permissions | length) == 0 then del(.permissions) else . end)
else . end'

kit_fragment() { # kit_fragment <package-relative-json> — read it and substitute @PREFIX@
  local rel="$1" src="$KIT_ROOT/$1" out
  [ -f "$src" ] || kit_die "missing package file: $rel (expected $src)"
  kit_need_jq
  # Substitute with jq, not sed: a prefix containing `&`, `|`, `"` or `\` is a legal
  # $HOME and must land in the JSON verbatim, escaped as JSON, not as a sed pattern.
  out="$(jq -e --arg p "$KIT_PREFIX" '(.. | strings) |= gsub("@PREFIX@"; $p)' "$src" 2>/dev/null)" \
    || kit_die "$rel is not valid JSON"
  printf '%s' "$out"
}

# ---------------------------------------------------------------- Codex byte cap

kit_codex_cap_current() { # root-table value of project_doc_max_bytes, empty when absent
  [ -f "$1" ] || return 0
  awk '
    /^[[:space:]]*\[/ { exit }
    /^[[:space:]]*project_doc_max_bytes[[:space:]]*=/ {
      v = $0; sub(/^[^=]*=[[:space:]]*/, "", v); gsub(/_/, "", v); gsub(/[^0-9].*$/, "", v)
      print v; exit
    }' "$1"
}

kit_codex_cap() { # kit_codex_cap <config.toml> <bytes-the-rules-file-needs>
  local f="$1" need="$2" cur tmp
  kit_assert_in_home "$f"
  cur="$(kit_codex_cap_current "$f")"
  if [ -n "$cur" ]; then
    case "$cur" in
      ''|*[!0-9]*)
        kit_warn "project_doc_max_bytes in $f is not a plain number — left alone"
        return 0 ;;
    esac
    if [ "$cur" -ge "$need" ]; then
      kit_info "project_doc_max_bytes is $cur (rules file needs $need) — unchanged"
      kit_manifest_add "codex:cap" "$f"
      return 0
    fi
  fi
  if [ "$KIT_DRY_RUN" = "1" ]; then
    if [ -z "$cur" ]; then kit_say "would set project_doc_max_bytes = $KIT_CODEX_CAP in $f (key absent)"
    else kit_say "would raise project_doc_max_bytes $cur -> $KIT_CODEX_CAP in $f"; fi
    return 0
  fi
  kit_mkdirp "$(dirname "$f")"
  kit_backup_once "$f"
  tmp="$(mktemp "${TMPDIR:-/tmp}/mac.XXXXXX")"
  if [ -z "$cur" ]; then
    # Root-table keys must come before any [table] header, so prepend ours.
    printf 'project_doc_max_bytes = %s\n' "$KIT_CODEX_CAP" > "$tmp"
    if [ -f "$f" ]; then cat "$f" >> "$tmp"; fi
  else
    awk -v val="$KIT_CODEX_CAP" '
      BEGIN { done = 0 }
      !done && /^[[:space:]]*\[/ { done = 1 }
      !done && /^[[:space:]]*project_doc_max_bytes[[:space:]]*=/ {
        print "project_doc_max_bytes = " val; done = 1; next }
      { print }' "$f" > "$tmp"
  fi
  mv "$tmp" "$f"
  kit_manifest_add "codex:cap" "$f"
  kit_say "set project_doc_max_bytes = $KIT_CODEX_CAP in $f"
}

# ---------------------------------------------------------------- git hooks path

kit_git_hooks_path() { # kit_git_hooks_path <dir>
  local dir="$1" cur=""
  kit_have git || { kit_warn "git not found — skipped core.hooksPath"; return 0; }
  cur="$(git config --global --get core.hooksPath 2>/dev/null || true)"
  if [ -n "$cur" ] && [ "$cur" != "$dir" ]; then
    kit_say "left alone: global core.hooksPath is already $cur"
    kit_info "to chain, call $dir/pre-commit from $cur/pre-commit"
    return 0
  fi
  if [ "$KIT_DRY_RUN" = "1" ]; then
    if [ -z "$cur" ]; then kit_say "would run: git config --global core.hooksPath $dir"
    else kit_info "unchanged global core.hooksPath = $dir"; fi
    return 0
  fi
  if [ -z "$cur" ]; then
    git config --global core.hooksPath "$dir"
    kit_say "set global core.hooksPath = $dir"
  else
    kit_info "unchanged global core.hooksPath = $dir"
  fi
  kit_manifest_add "git:hooksPath" "$dir"
}

# ---------------------------------------------------------------- doctor report

kit_doctor_dep() { # kit_doctor_dep <binary> <required|levels|optional> [note]
  local b="$1" kind="$2" note="${3:-}"
  if kit_have "$b"; then
    kit_info "$b: $(command -v "$b")"
    return 0
  fi
  case "$kind" in
    required) kit_info "$b: MISSING (required) $note" ;;
    levels)   kit_info "$b: not installed — install.sh refuses the levels that need it $note" ;;
    *)        kit_info "$b: not installed (optional) $note" ;;
  esac
  return 1
}

kit_doctor_backup_candidates() { # destinations that exist and are not ours
  local p
  for p in \
    "$KIT_CLAUDE_DIR/rules/core.md" \
    "$KIT_CLAUDE_DIR/settings.json" \
    "$KIT_CLAUDE_DIR/statusline-command.sh" \
    "$KIT_CLAUDE_DIR/agents/test-author.md" \
    "$KIT_CLAUDE_DIR/skills/context-init/SKILL.md" \
    "$KIT_CLAUDE_DIR/skills/techdebt/SKILL.md" \
    "$KIT_CODEX_DIR/AGENTS.md" \
    "$KIT_CODEX_DIR/config.toml" \
    "$KIT_CODEX_DIR/hooks.json" \
    "$KIT_GROK_DIR/rules/core.md" \
    "$KIT_GROK_DIR/hooks/multi-agent-coding.json" \
    "$HOME/.local/bin/agentsify" \
    "$HOME/.local/bin/plan-init"
  do
    if [ -e "$p" ] || [ -L "$p" ]; then
      if ! kit_is_ours "$p"; then printf '%s\n' "$p"; fi
    fi
  done
}

kit_doctor_report() { # read-only; returns 1 when a hard dependency is missing
  local rc=0 n p rules_bytes
  kit_say "$KIT_NAME doctor v$KIT_VERSION — read-only, writes nothing"
  kit_say ""
  kit_say "system"
  kit_info "os: $(kit_os)"
  kit_info "bash: $(kit_bash_version)"
  if ! kit_bash_ok; then kit_info "bash: too old — 3.2 or newer required"; rc=1; fi
  kit_info "package: $KIT_ROOT"
  kit_info "install prefix: $KIT_PREFIX"
  kit_say ""
  kit_say "dependencies"
  kit_doctor_dep git required || rc=1
  kit_doctor_dep jq levels "(level 2 safety, level 3 claude-quality)" || true
  kit_doctor_dep gitleaks optional "— the pre-commit hook warns and passes without it" || true
  kit_doctor_dep python3 optional || true
  kit_say ""
  kit_say "CLIs"
  kit_info "Claude Code: $(kit_cli_state claude "$KIT_CLAUDE_DIR")"
  kit_info "  config dir: $KIT_CLAUDE_DIR ($KIT_CLAUDE_DIR_SOURCE)"
  if [ "$KIT_CLAUDE_DIR_SOURCE" = "CLAUDE_CONFIG_DIR" ]; then
    kit_warn "CLAUDE_CONFIG_DIR is set — using $KIT_CLAUDE_DIR instead of the default"
  fi
  kit_info "Codex: $(kit_cli_state codex "$KIT_CODEX_DIR")"
  kit_info "Grok Build: $(kit_cli_state grok "$KIT_GROK_DIR")"
  kit_info "note: Kimi and GLM are Claude Code with another endpoint — they share $KIT_CLAUDE_DIR"
  if kit_has_claude && kit_has_grok; then
    kit_info "note: Grok Build reads the Claude rules dir through [compat.claude], so level 1"
    kit_info "      writes nothing under $KIT_GROK_DIR. Confirm with: grok inspect"
  fi
  kit_say ""
  kit_say "rules file"
  if [ -f "$KIT_ROOT/rules/core.md" ]; then
    rules_bytes="$(wc -c < "$KIT_ROOT/rules/core.md" | tr -d ' ')"
    kit_info "rules/core.md: $rules_bytes bytes"
  else
    kit_info "rules/core.md: MISSING from the package"
    rc=1
  fi
  if [ -f "$KIT_CODEX_DIR/config.toml" ]; then
    n="$(kit_codex_cap_current "$KIT_CODEX_DIR/config.toml")"
    kit_info "codex project_doc_max_bytes: ${n:-absent (Codex default 32768)}"
  fi
  kit_say ""
  kit_say "install state"
  if [ -f "$KIT_MANIFEST" ]; then
    kit_info "manifest: $KIT_MANIFEST ($(wc -l < "$KIT_MANIFEST" | tr -d ' ') entries)"
  else
    kit_info "manifest: none — nothing installed yet"
  fi
  case ":$PATH:" in
    *":$HOME/.local/bin:"*) : ;;
    *) kit_info "note: $HOME/.local/bin is not on PATH (level 3 installs two commands there)" ;;
  esac
  kit_say ""
  kit_say "would back up on install"
  n=0
  while IFS= read -r p; do
    [ -n "$p" ] || continue
    kit_info "$p"
    n=$((n + 1))
  done <<EOF
$(kit_doctor_backup_candidates)
EOF
  if [ "$n" -eq 0 ]; then kit_info "nothing — no file of yours would be replaced"; fi
  kit_say ""
  if [ "$rc" -ne 0 ]; then kit_say "result: a hard dependency is missing (see MISSING above)"
  else kit_say "result: ready"; fi
  return $rc
}
