#!/usr/bin/env bash
# managed-by: multi-agent-coding
# install.sh — install the kit into the agent CLIs found on this machine.
#
# Order of operations, always: check the package is complete, run doctor, print the plan,
# ask (unless --yes), then write. Nothing is written before the plan is on screen.
# Every write is recorded in $PREFIX/manifest.txt so uninstall.sh can undo exactly this.
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
usage: bash install.sh [--dry-run] [--yes] [--link] [--level N] [--only LIST]
                       [--prefix DIR] [--uninstall ...] [--help]

Levels (opt-in; with no --level and no --only all four are offered, one prompt each):
  1 rules           the rules file for every CLI found (Claude Code, Codex, Grok Build)
  2 safety          block-dangerous hook + permission deny/ask lists + gitleaks pre-commit
  3 claude-quality  statusline, test-author agent, two skills, agentsify and plan-init
  4 plan            the AGENTS.md and PLAN.md templates used by those two commands

Options:
  --dry-run      print every path that would be written or changed, write nothing
  --yes, -y      do not ask; install the selected levels
  --link         symlink into this checkout instead of copying (Codex AGENTS.md is
                 always a copy: Codex reads exactly one global file)
  --level N      install levels 1 through N (N is 1, 2, 3 or 4)
  --only LIST    install exactly these levels: comma separated names or numbers,
                 e.g. --only rules,safety or --only 2
  --prefix DIR   install prefix, must be inside \$HOME
                 (default: \$MULTI_AGENT_CODING_HOME, else \$HOME/.multi-agent-coding)
  --uninstall    hand over to uninstall.sh; --dry-run, --yes, --prefix and
                 --restore-backups are passed through (no level selection)
  --help, -h     this text

Environment:
  MULTI_AGENT_CODING_HOME   install prefix
  CLAUDE_CONFIG_DIR         honoured when set: used instead of \$HOME/.claude
  MAC_SKIP_PATH_DETECT=1    detect CLIs by config dir only, ignoring PATH

Exit codes: 0 ok · 1 error · 2 usage.
USAGE
}

ASSUME_YES=0
LEVEL_MAX=""
ONLY=""
DO_UNINSTALL=0
PASSTHRU=""

add_passthru() { PASSTHRU="$PASSTHRU$1
"; }

while [ $# -gt 0 ]; do
  case "$1" in
    --help|-h)    usage; exit 0 ;;
    --dry-run)    KIT_DRY_RUN=1; add_passthru "$1" ;;
    --yes|-y)     ASSUME_YES=1; add_passthru "$1" ;;
    --link)       KIT_LINK=1 ;;
    --level)      shift; [ $# -gt 0 ] || kit_usage_die "--level needs a number 1..4"; LEVEL_MAX="$1" ;;
    --level=*)    LEVEL_MAX="${1#--level=}" ;;
    --only)       shift; [ $# -gt 0 ] || kit_usage_die "--only needs a level list"; ONLY="$1" ;;
    --only=*)     ONLY="${1#--only=}" ;;
    --prefix)     shift; [ $# -gt 0 ] && [ -n "$1" ] || kit_usage_die "--prefix needs a non-empty directory"; KIT_PREFIX="$1"; add_passthru "--prefix=$1" ;;
    --prefix=*)   KIT_PREFIX="${1#--prefix=}"; [ -n "$KIT_PREFIX" ] || kit_usage_die "--prefix needs a non-empty directory"; add_passthru "$1" ;;
    --uninstall)  DO_UNINSTALL=1 ;;
    --restore-backups) RESTORE_SEEN=1; add_passthru "$1" ;;
    *)            usage >&2; kit_usage_die "unknown option: $1" ;;
  esac
  shift
done

if [ "${RESTORE_SEEN:-0}" = "1" ] && [ "$DO_UNINSTALL" != "1" ]; then
  kit_usage_die "--restore-backups only makes sense with --uninstall"
fi

if [ "$DO_UNINSTALL" = "1" ]; then
  # uninstall.sh removes whatever the manifest lists; it has no level selection, so
  # accepting --level/--only/--link here would silently mean "everything".
  if [ -n "$LEVEL_MAX" ] || [ -n "$ONLY" ] || [ "${KIT_LINK:-0}" = "1" ]; then
    kit_usage_die "--uninstall takes no --level, --only or --link (it removes everything the manifest lists)"
  fi
  [ -f "$KIT_ROOT/uninstall.sh" ] || kit_die "missing package file: uninstall.sh"
  set --
  while IFS= read -r a; do
    [ -n "$a" ] || continue
    set -- "$@" "$a"
  done <<EOF
$PASSTHRU
EOF
  exec bash "$KIT_ROOT/uninstall.sh" "$@"
fi

kit_init

# ---------------------------------------------------------------- level selection

level_name() {
  case "$1" in
    1) printf 'rules\n' ;;
    2) printf 'safety\n' ;;
    3) printf 'claude-quality\n' ;;
    4) printf 'plan\n' ;;
    *) return 1 ;;
  esac
}

SELECTED=""
select_level() { # by name, no duplicates, always in level order
  case " $SELECTED " in *" $1 "*) return 0 ;; esac
  SELECTED="$SELECTED $1"
}
sel_has() { case " $SELECTED " in *" $1 "*) return 0 ;; esac; return 1; }

if [ -n "$LEVEL_MAX" ]; then
  case "$LEVEL_MAX" in
    1|2|3|4) : ;;
    *) kit_usage_die "--level takes 1, 2, 3 or 4 (got: $LEVEL_MAX)" ;;
  esac
  i=1
  while [ "$i" -le "$LEVEL_MAX" ]; do
    select_level "$(level_name "$i")"
    i=$((i + 1))
  done
fi

if [ -n "$ONLY" ]; then
  for tok in $(printf '%s\n' "$ONLY" | tr ',' ' '); do
    case "$tok" in
      1|2|3|4)                              select_level "$(level_name "$tok")" ;;
      rules|safety|claude-quality|plan)     select_level "$tok" ;;
      *) kit_usage_die "--only: unknown level '$tok' (use rules, safety, claude-quality, plan or 1..4)" ;;
    esac
  done
fi

if [ -z "$SELECTED" ]; then
  SELECTED=" rules safety claude-quality plan"
fi

# ---------------------------------------------------------------- package completeness

require_level_files() {
  case "$1" in
    rules) kit_require_pkg_file rules/core.md ;;
    safety)
      kit_require_pkg_file hooks/block-dangerous.sh
      kit_require_pkg_file config/hooks.json
      kit_require_pkg_file config/permissions.json
      kit_require_pkg_file githooks/pre-commit ;;
    claude-quality)
      kit_require_pkg_file claude/statusline-command.sh
      kit_require_pkg_file claude/agents/test-author.md
      kit_require_pkg_file claude/skills/context-init/SKILL.md
      kit_require_pkg_file claude/skills/techdebt/SKILL.md
      kit_require_pkg_file tools/agentsify
      kit_require_pkg_file tools/plan-init ;;
    plan)
      kit_require_pkg_file templates/AGENTS.md
      kit_require_pkg_file templates/PLAN.md ;;
  esac
}

for lv in $SELECTED; do require_level_files "$lv"; done

# ---------------------------------------------------------------- doctor

kit_say "=== doctor"
kit_say ""
if ! bash "$KIT_ROOT/doctor.sh" --prefix "$KIT_PREFIX"; then
  kit_die "doctor found a blocking problem (see above) — nothing was written"
fi
# jq is optional for the doctor but mandatory for the levels that edit JSON. Refuse
# here, before the first write, rather than install level 1 and die halfway.
if { sel_has safety || sel_has claude-quality; } && ! kit_have jq; then
  kit_die "jq is required for level 2 (safety) and level 3 (claude-quality) — install it (brew install jq / apt-get install jq) or choose --only rules,plan. Nothing was written."
fi

HAS_CLAUDE=0; kit_has_claude && HAS_CLAUDE=1
HAS_CODEX=0;  kit_has_codex  && HAS_CODEX=1
HAS_GROK=0;   kit_has_grok   && HAS_GROK=1

if [ "$HAS_CLAUDE" = "0" ] && [ "$HAS_CODEX" = "0" ] && [ "$HAS_GROK" = "0" ]; then
  kit_die "no supported CLI found (Claude Code, Codex, Grok Build) — nothing was written.
Install one first, or create its config dir if it lives somewhere unusual."
fi

RULES_BYTES=0
if [ -f "$KIT_ROOT/rules/core.md" ]; then
  RULES_BYTES="$(wc -c < "$KIT_ROOT/rules/core.md" | tr -d ' ')"
fi

# ---------------------------------------------------------------- plan

plan_for_level() {
  case "$1" in
    rules)
      if [ "$HAS_CLAUDE" = "1" ]; then kit_info "$KIT_CLAUDE_DIR/rules/core.md"; fi
      if [ "$HAS_CODEX" = "1" ]; then
        kit_info "$KIT_CODEX_DIR/AGENTS.md (copy)"
        kit_info "$KIT_CODEX_DIR/config.toml (project_doc_max_bytes only)"
      fi
      if [ "$HAS_GROK" = "1" ]; then
        if [ "$HAS_CLAUDE" = "1" ]; then
          kit_info "nothing under $KIT_GROK_DIR — Grok Build reads the Claude rules dir"
        else
          kit_info "$KIT_GROK_DIR/rules/core.md"
        fi
      fi ;;
    safety)
      kit_info "$KIT_PREFIX/hooks/block-dangerous.sh"
      kit_info "$KIT_PREFIX/githooks/pre-commit"
      if [ "$HAS_CLAUDE" = "1" ]; then
        kit_info "$KIT_SETTINGS (.hooks.PreToolUse, .permissions.deny, .permissions.ask)"
      fi
      if [ "$HAS_CODEX" = "1" ]; then kit_info "$KIT_CODEX_DIR/hooks.json (.hooks.PreToolUse)"; fi
      if [ "$HAS_GROK" = "1" ]; then kit_info "$KIT_GROK_DIR/hooks/$KIT_NAME.json (whole file)"; fi
      kit_info "git config --global core.hooksPath (only when you have none)" ;;
    claude-quality)
      if [ "$HAS_CLAUDE" = "1" ]; then
        kit_info "$KIT_CLAUDE_DIR/statusline-command.sh"
        kit_info "$KIT_SETTINGS (.statusLine, only when absent or ours)"
        kit_info "$KIT_CLAUDE_DIR/agents/test-author.md"
        kit_info "$KIT_CLAUDE_DIR/skills/context-init/SKILL.md"
        kit_info "$KIT_CLAUDE_DIR/skills/techdebt/SKILL.md"
        kit_info "$KIT_PREFIX/tools/agentsify -> $HOME/.local/bin/agentsify"
        kit_info "$KIT_PREFIX/tools/plan-init -> $HOME/.local/bin/plan-init"
      else
        kit_info "skipped: Claude Code not found"
      fi ;;
    plan)
      kit_info "$KIT_PREFIX/templates/AGENTS.md"
      kit_info "$KIT_PREFIX/templates/PLAN.md" ;;
  esac
}

kit_say ""
kit_say "=== plan"
if [ "$KIT_DRY_RUN" = "1" ]; then kit_say "(dry run: nothing will be written)"; fi
if [ "$KIT_LINK" = "1" ]; then kit_say "(link mode: files are symlinked into $KIT_ROOT)"; fi
kit_say ""
for lv in $SELECTED; do
  kit_say "level $lv"
  plan_for_level "$lv"
done
kit_say ""
kit_info "manifest: $KIT_MANIFEST"
kit_info "backups:  <file>.bak-YYYYmmdd-HHMMSS next to any file of yours we replace"
kit_say ""

ask_level() { # 0 = install, 1 = skip
  if [ "$ASSUME_YES" = "1" ] || [ "$KIT_DRY_RUN" = "1" ]; then return 0; fi
  if [ ! -t 0 ]; then
    kit_say "skipped level $1 (no terminal to ask on; use --yes or --only)"
    return 1
  fi
  printf 'install level %s? [y/N] ' "$1"
  local ans=""
  read -r ans || ans=""
  case "$ans" in
    y|Y|yes|YES) return 0 ;;
    *) kit_say "skipped level $1"; return 1 ;;
  esac
}

# ---------------------------------------------------------------- levels

do_rules() {
  local saved_link
  if [ "$HAS_CLAUDE" = "1" ]; then
    kit_install_file rules/core.md "$KIT_CLAUDE_DIR/rules/core.md"
  fi
  if [ "$HAS_CODEX" = "1" ]; then
    # Codex reads exactly one global file and follows no imports: always a copy.
    saved_link="$KIT_LINK"; KIT_LINK=0
    kit_install_file rules/core.md "$KIT_CODEX_DIR/AGENTS.md"
    KIT_LINK="$saved_link"
    kit_codex_cap "$KIT_CODEX_DIR/config.toml" "$RULES_BYTES"
  fi
  if [ "$HAS_GROK" = "1" ]; then
    if [ "$HAS_CLAUDE" = "1" ]; then
      kit_say "Grok Build reads the Claude rules dir; confirm with: grok inspect"
      kit_info "wrote nothing under $KIT_GROK_DIR — a second copy would load the rules twice"
    else
      kit_install_file rules/core.md "$KIT_GROK_DIR/rules/core.md"
    fi
  fi
}

do_safety() {
  kit_need_jq
  local hfrag pfrag
  kit_install_file hooks/block-dangerous.sh "$KIT_PREFIX/hooks/block-dangerous.sh" 755
  hfrag="$(kit_fragment config/hooks.json)"
  pfrag="$(kit_fragment config/permissions.json)"

  if [ "$HAS_CLAUDE" = "1" ]; then
    kit_json_apply "$KIT_SETTINGS" --argjson frag "$hfrag" "$KIT_JQ_ADD_HOOKS"
    kit_json_note "$KIT_SETTINGS" ".hooks.PreToolUse"
    kit_manifest_add "settings:hook" "$KIT_SETTINGS"
    kit_json_apply "$KIT_SETTINGS" --argjson frag "$pfrag" "$KIT_JQ_ADD_PERMS"
    kit_json_note "$KIT_SETTINGS" ".permissions deny/ask"
    kit_manifest_add "settings:permissions" "$KIT_SETTINGS"
  fi

  if [ "$HAS_CODEX" = "1" ]; then
    kit_json_apply "$KIT_CODEX_DIR/hooks.json" --argjson frag "$hfrag" "$KIT_JQ_ADD_HOOKS"
    kit_json_note "$KIT_CODEX_DIR/hooks.json" ".hooks.PreToolUse"
    kit_manifest_add "codex:hook" "$KIT_CODEX_DIR/hooks.json"
  fi

  if [ "$HAS_GROK" = "1" ]; then
    # The whole file is ours: Grok Build does dispatch hooks from its native config.
    local gfile gbody
    gfile="$KIT_GROK_DIR/hooks/$KIT_NAME.json"
    gbody="$(printf '%s' "$hfrag" | jq --sort-keys '{hooks: .}')"
    kit_write_managed_json "$gfile" "$gbody"
    kit_manifest_add "grok:hook" "$gfile"
  fi

  kit_install_file githooks/pre-commit "$KIT_PREFIX/githooks/pre-commit" 755
  kit_git_hooks_path "$KIT_PREFIX/githooks"
}

do_claude_quality() {
  if [ "$HAS_CLAUDE" != "1" ]; then
    kit_warn "Claude Code not found — level claude-quality skipped"
    return 0
  fi
  kit_need_jq
  local want cur
  kit_install_file claude/statusline-command.sh "$KIT_CLAUDE_DIR/statusline-command.sh" 755
  # Quoted: the command runs through a shell, and $HOME may contain spaces.
  want="bash \"$KIT_CLAUDE_DIR/statusline-command.sh\""
  cur=""
  if [ -f "$KIT_SETTINGS" ]; then
    cur="$(jq -r '.statusLine.command // ""' "$KIT_SETTINGS" 2>/dev/null || printf '')"
  fi
  if [ -z "$cur" ] || [ "$cur" = "$want" ] \
     || [ "$cur" = "$KIT_CLAUDE_DIR/statusline-command.sh" ] || [ "$cur" = "bash $KIT_CLAUDE_DIR/statusline-command.sh" ]; then
    kit_json_apply "$KIT_SETTINGS" --arg cmd "$want" \
      '.statusLine = {type: "command", command: $cmd, padding: 0}'
    kit_json_note "$KIT_SETTINGS" ".statusLine"
    kit_manifest_add "settings:statusLine" "$KIT_SETTINGS"
  else
    kit_say "left alone: .statusLine in $KIT_SETTINGS is yours ($cur)"
    kit_info "to use ours instead, point it at $want"
  fi
  kit_install_file claude/agents/test-author.md "$KIT_CLAUDE_DIR/agents/test-author.md"
  kit_install_file claude/skills/context-init/SKILL.md "$KIT_CLAUDE_DIR/skills/context-init/SKILL.md"
  kit_install_file claude/skills/techdebt/SKILL.md "$KIT_CLAUDE_DIR/skills/techdebt/SKILL.md"
  kit_install_file tools/agentsify "$KIT_PREFIX/tools/agentsify" 755
  kit_install_file tools/plan-init "$KIT_PREFIX/tools/plan-init" 755
  kit_link_to "$KIT_PREFIX/tools/agentsify" "$HOME/.local/bin/agentsify"
  kit_link_to "$KIT_PREFIX/tools/plan-init" "$HOME/.local/bin/plan-init"
  case ":$PATH:" in
    *":$HOME/.local/bin:"*) : ;;
    *) kit_warn "$HOME/.local/bin is not on PATH — add it to use agentsify and plan-init" ;;
  esac
}

do_plan() {
  kit_install_file templates/AGENTS.md "$KIT_PREFIX/templates/AGENTS.md"
  kit_install_file templates/PLAN.md "$KIT_PREFIX/templates/PLAN.md"
}

kit_say "=== install"
INSTALLED=""
for lv in $SELECTED; do
  kit_say ""
  kit_say "--- level $lv"
  if ! ask_level "$lv"; then continue; fi
  case "$lv" in
    rules)          do_rules ;;
    safety)         do_safety ;;
    claude-quality) do_claude_quality ;;
    plan)           do_plan ;;
  esac
  INSTALLED="$INSTALLED $lv"
done

kit_say ""
kit_say "=== done"
if [ -z "$INSTALLED" ]; then
  kit_say "nothing selected — no change"
  exit 0
fi
if [ "$KIT_DRY_RUN" = "1" ]; then
  kit_say "dry run: levels$INSTALLED were planned, nothing was written"
  exit 0
fi
kit_say "installed levels:$INSTALLED"
kit_info "manifest: $KIT_MANIFEST"
kit_info "restart your CLI sessions so the rules, hooks and permissions load"
kit_info "verify:   bash $KIT_ROOT/doctor.sh"
kit_info "undo:     bash $KIT_ROOT/uninstall.sh"
