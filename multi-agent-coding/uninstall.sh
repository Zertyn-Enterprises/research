#!/usr/bin/env bash
# managed-by: multi-agent-coding
# uninstall.sh — undo exactly what $PREFIX/manifest.txt records, and nothing else.
#
# Files and links: removed only when they are still ours. JSON: only our hook entries
# (their command contains the prefix), only our deny/ask entries, and .statusLine only
# when it still points at our script. Everything else is reported and left alone.
#
# It writes no new .bak files: the newest <file>.bak-* stays the one the install made,
# which is what --restore-backups puts back. Look first with --dry-run.
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
usage: bash uninstall.sh [--dry-run] [--yes] [--restore-backups] [--prefix DIR] [--help]

Reads \$PREFIX/manifest.txt and removes only what this kit installed:
  file, link            deleted when still ours (our marker, a link into the kit,
                        or anywhere inside the install prefix)
  settings:hook         only hook entries whose command contains the prefix
  settings:permissions  only the deny/ask entries this kit ships
  settings:statusLine   only when it still points at our statusline script
  codex:hook            our PreToolUse entry in \$HOME/.codex/hooks.json
  grok:hook             our own file under \$HOME/.grok/hooks
  git:hooksPath         global core.hooksPath, only when it still points at the kit
  codex:cap             left alone (a raised byte cap harms nothing); reported

Options:
  --dry-run           print what would be removed, change nothing
  --yes, -y           do not ask for confirmation
  --restore-backups   after removing, restore the newest <file>.bak-* for every path
                      in the manifest (this discards later edits to those files)
  --prefix DIR        install prefix to read the manifest from
                      (default: \$MULTI_AGENT_CODING_HOME, else \$HOME/.multi-agent-coding)
  --help, -h          this text

Exit codes: 0 ok · 1 error · 2 usage.
USAGE
}

ASSUME_YES=0
RESTORE=0

while [ $# -gt 0 ]; do
  case "$1" in
    --help|-h)          usage; exit 0 ;;
    --dry-run)          KIT_DRY_RUN=1 ;;
    --yes|-y)           ASSUME_YES=1 ;;
    --restore-backups)  RESTORE=1 ;;
    --prefix)           shift; [ $# -gt 0 ] && [ -n "$1" ] || kit_usage_die "--prefix needs a non-empty directory"; KIT_PREFIX="$1" ;;
    --prefix=*)         KIT_PREFIX="${1#--prefix=}"; [ -n "$KIT_PREFIX" ] || kit_usage_die "--prefix needs a non-empty directory" ;;
    *)                  usage >&2; kit_usage_die "unknown option: $1" ;;
  esac
  shift
done

kit_init

if [ ! -f "$KIT_MANIFEST" ]; then
  kit_say "no manifest at $KIT_MANIFEST — this kit installed nothing here, nothing to do"
  exit 0
fi

REMOVED=0
LEFT=0

# Never create a new backup during an uninstall: the install-time .bak must stay the
# newest one, or --restore-backups would restore the state we are removing.
while IFS= read -r p; do
  [ -n "$p" ] || continue
  KIT_BACKED_UP="$KIT_BACKED_UP
$p"
done <<EOF
$(awk -F'\t' '{ print $2 }' "$KIT_MANIFEST")
EOF

kit_say "=== manifest: $KIT_MANIFEST"
cat "$KIT_MANIFEST"
kit_say ""
if [ "$KIT_DRY_RUN" = "1" ]; then
  kit_say "(dry run: nothing will be removed)"
elif [ "$ASSUME_YES" != "1" ]; then
  if [ ! -t 0 ]; then
    kit_die "no terminal to confirm on — re-run with --yes (or --dry-run to look first)"
  fi
  printf 'remove these entries? [y/N] '
  ans=""
  read -r ans || ans=""
  case "$ans" in
    y|Y|yes|YES) : ;;
    *) kit_say "aborted — nothing was removed"; exit 0 ;;
  esac
fi

manifest_paths_of_kind() { # manifest_paths_of_kind <kind>
  awk -F'\t' -v k="$1" '$1 == k { print $2 }' "$KIT_MANIFEST"
}

is_ours_path() { # anything inside the prefix is ours by construction
  case "$1" in
    "$KIT_PREFIX"/*) return 0 ;;
  esac
  kit_is_ours "$1"
}

prune_parent() { # remove a directory we created, only when it is now empty
  local d
  d="$(dirname "$1")"
  case "$d" in
    "$HOME"|"$KIT_CLAUDE_DIR"|"$KIT_CODEX_DIR"|"$KIT_GROK_DIR"|"$HOME/.local/bin") return 0 ;;
  esac
  rmdir "$d" 2>/dev/null || true
}

remove_path() { # remove_path <path>
  local p="$1"
  if [ ! -e "$p" ] && [ ! -L "$p" ]; then
    kit_info "already gone: $p"
    return 0
  fi
  if ! is_ours_path "$p"; then
    kit_say "left alone: $p (not ours any more)"
    LEFT=$((LEFT + 1))
    return 0
  fi
  if [ "$KIT_DRY_RUN" = "1" ]; then
    kit_say "would remove $p"
    REMOVED=$((REMOVED + 1))
    return 0
  fi
  rm -f "$p"
  prune_parent "$p"
  kit_say "removed $p"
  REMOVED=$((REMOVED + 1))
}

drop_hooks_from() { # drop_hooks_from <json-file>
  local f="$1"
  if [ ! -f "$f" ]; then kit_info "already gone: $f"; return 0; fi
  if ! kit_have jq; then kit_warn "jq not found — left $f alone"; LEFT=$((LEFT + 1)); return 0; fi
  kit_json_apply "$f" --arg pfx "$KIT_PREFIX" "$KIT_JQ_DEL_HOOKS"
  if [ "$KIT_JSON_CHANGED" = "1" ]; then
    if [ "$KIT_DRY_RUN" = "1" ]; then kit_say "would remove our PreToolUse hook from $f"
    else kit_say "removed our PreToolUse hook from $f"; fi
    REMOVED=$((REMOVED + 1))
  else
    kit_info "no hook of ours left in $f"
  fi
}

# ---------------------------------------------------------------- settings.json hooks

while IFS= read -r p; do
  [ -n "$p" ] || continue
  drop_hooks_from "$p"
done <<EOF
$(manifest_paths_of_kind "settings:hook")
EOF

# ---------------------------------------------------------------- codex hooks.json

while IFS= read -r p; do
  [ -n "$p" ] || continue
  drop_hooks_from "$p"
  if [ -f "$p" ] && [ "$KIT_DRY_RUN" != "1" ] && kit_have jq; then
    if [ "$(jq 'keys | length' "$p" 2>/dev/null || printf '1\n')" = "0" ]; then
      rm -f "$p"
      prune_parent "$p"
      kit_say "removed $p (nothing but our hook was in it)"
    fi
  fi
done <<EOF
$(manifest_paths_of_kind "codex:hook")
EOF

# ---------------------------------------------------------------- grok hook file (all ours)

while IFS= read -r p; do
  [ -n "$p" ] || continue
  if [ ! -e "$p" ] && [ ! -L "$p" ]; then kit_info "already gone: $p"; continue; fi
  if [ "$KIT_DRY_RUN" = "1" ]; then
    kit_say "would remove $p"
  else
    rm -f "$p"
    prune_parent "$p"
    kit_say "removed $p"
  fi
  REMOVED=$((REMOVED + 1))
done <<EOF
$(manifest_paths_of_kind "grok:hook")
EOF

# ---------------------------------------------------------------- permissions

while IFS= read -r p; do
  [ -n "$p" ] || continue
  if [ ! -f "$p" ]; then kit_info "already gone: $p"; continue; fi
  if [ ! -f "$KIT_ROOT/config/permissions.json" ]; then
    kit_warn "missing package file: config/permissions.json — left the deny/ask lists in $p alone"
    LEFT=$((LEFT + 1))
    continue
  fi
  PFRAG="$(kit_fragment config/permissions.json)"
  kit_json_apply "$p" --argjson frag "$PFRAG" "$KIT_JQ_DEL_PERMS"
  if [ "$KIT_JSON_CHANGED" = "1" ]; then
    if [ "$KIT_DRY_RUN" = "1" ]; then kit_say "would subtract our deny/ask entries from $p"
    else kit_say "subtracted our deny/ask entries from $p"; fi
    kit_info "a rule you added yourself that we also ship goes with them — re-add it if you want it"
    REMOVED=$((REMOVED + 1))
  else
    kit_info "no deny/ask entry of ours left in $p"
  fi
done <<EOF
$(manifest_paths_of_kind "settings:permissions")
EOF

# ---------------------------------------------------------------- statusLine

while IFS= read -r p; do
  [ -n "$p" ] || continue
  if [ ! -f "$p" ]; then kit_info "already gone: $p"; continue; fi
  cur="$(jq -r '.statusLine.command // ""' "$p" 2>/dev/null || printf '\n')"
  case "$cur" in
    "$KIT_CLAUDE_DIR/statusline-command.sh"|"bash $KIT_CLAUDE_DIR/statusline-command.sh"|"$KIT_PREFIX"/*)
      kit_json_apply "$p" 'del(.statusLine)'
      if [ "$KIT_DRY_RUN" = "1" ]; then kit_say "would unset .statusLine in $p"
      else kit_say "unset .statusLine in $p"; fi
      REMOVED=$((REMOVED + 1)) ;;
    "")
      kit_info "no .statusLine in $p" ;;
    *)
      kit_say "left alone: .statusLine in $p is yours ($cur)"
      LEFT=$((LEFT + 1)) ;;
  esac
done <<EOF
$(manifest_paths_of_kind "settings:statusLine")
EOF

# ---------------------------------------------------------------- codex byte cap

while IFS= read -r p; do
  [ -n "$p" ] || continue
  kit_say "left alone: project_doc_max_bytes in $p (a raised cap harms nothing)"
  kit_info "revert it by hand, or with --restore-backups"
  LEFT=$((LEFT + 1))
done <<EOF
$(manifest_paths_of_kind "codex:cap")
EOF

# ---------------------------------------------------------------- global core.hooksPath

while IFS= read -r p; do
  [ -n "$p" ] || continue
  cur=""
  if kit_have git; then cur="$(git config --global --get core.hooksPath 2>/dev/null || true)"; fi
  if [ "$cur" = "$p" ]; then
    if [ "$KIT_DRY_RUN" = "1" ]; then
      kit_say "would run: git config --global --unset core.hooksPath"
    else
      git config --global --unset core.hooksPath
      kit_say "unset global core.hooksPath"
    fi
    REMOVED=$((REMOVED + 1))
  elif [ -z "$cur" ]; then
    kit_info "global core.hooksPath is already unset"
  else
    kit_say "left alone: global core.hooksPath is now $cur"
    LEFT=$((LEFT + 1))
  fi
done <<EOF
$(manifest_paths_of_kind "git:hooksPath")
EOF

# ---------------------------------------------------------------- files and links

for kind in file link; do
  while IFS= read -r p; do
    [ -n "$p" ] || continue
    remove_path "$p"
  done <<EOF
$(manifest_paths_of_kind "$kind")
EOF
done

# ---------------------------------------------------------------- backups

if [ "$RESTORE" = "1" ]; then
  kit_say ""
  kit_say "=== restore backups"
  while IFS= read -r p; do
    [ -n "$p" ] || continue
    newest=""
    for b in "$p".bak-*; do
      if [ -e "$b" ] || [ -L "$b" ]; then newest="$b"; fi
    done
    if [ -z "$newest" ]; then continue; fi
    if [ "$KIT_DRY_RUN" = "1" ]; then
      kit_say "would restore $p from $(basename "$newest")"
      continue
    fi
    rm -f "$p"
    mkdir -p "$(dirname "$p")"
    if [ -L "$newest" ]; then cp -P "$newest" "$p"; else cp -p "$newest" "$p"; fi
    kit_say "restored $p from $(basename "$newest")"
  done <<EOF
$(awk -F'\t' '$1 != "git:hooksPath" { print $2 }' "$KIT_MANIFEST" | sort -u)
EOF
fi

# ---------------------------------------------------------------- manifest and prefix

kit_say ""
if [ "$KIT_DRY_RUN" = "1" ]; then
  kit_say "would remove $KIT_MANIFEST"
  kit_say "dry run: $REMOVED entries would be removed, $LEFT left alone"
  exit 0
fi

rm -f "$KIT_MANIFEST"
find "$KIT_PREFIX" -depth -type d -exec rmdir {} \; 2>/dev/null || true
if [ -d "$KIT_PREFIX" ]; then
  kit_say "kept $KIT_PREFIX (it still holds files that are not in the manifest)"
fi
kit_say "removed $REMOVED entries, left $LEFT alone"
kit_info "restart your CLI sessions so the removed hooks and rules stop loading"
