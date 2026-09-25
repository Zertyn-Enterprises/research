#!/usr/bin/env bash
# managed-by: multi-agent-coding
# Claude Code status line. Reads the hook JSON on stdin, prints exactly one line.
# Segments: cwd | git branch+state | session name | model | context bar | message
#           tokens | session tokens | session cost | agent badge | vim mode
#
# No `set -e` on purpose: a status line must degrade, never abort mid-render.
# A missing field drops its segment; the line is still printed.
set -uo pipefail

input=$(cat)

# --- ANSI 256-color attributes ---
reset='\033[0m'
bold='\033[1m'
fg_white='\033[38;5;255m'
fg_gray='\033[38;5;245m'
fg_blue='\033[38;5;69m'
fg_cyan='\033[38;5;80m'
fg_green='\033[38;5;114m'
fg_yellow='\033[38;5;221m'
fg_orange='\033[38;5;208m'
fg_red='\033[38;5;203m'
fg_purple='\033[38;5;141m'
fg_teal='\033[38;5;73m'
sep="${fg_gray}|${reset}"

# --- Plain fallback when jq is not installed: still one line, still exit 0 ---
if ! command -v jq >/dev/null 2>&1; then
    fb_cwd=$(printf '%s' "$input" |
      sed -n 's/.*"current_dir"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)
    [ -n "$fb_cwd" ] || fb_cwd="$PWD"
    printf '%s  %b  install jq for the full status line\n' "${fb_cwd##*/}" "$sep"
    exit 0
fi

# --- Extract every field in a single jq pass (per-render cost matters with many
# parallel sessions). The unit-separator delimiter is deliberate: a tab is
# IFS-whitespace, which collapses empty fields and shifts everything left. ---
FS=$(printf '\037')
IFS="$FS" read -r cwd model used_pct vim_mode agent_name session_name \
  msg_in msg_out msg_cache_w msg_cache_r sess_in sess_out cost_usd \
  < <(printf '%s' "$input" | jq -r '
  [ (.workspace.current_dir // .cwd // ""),
    (.model.display_name // ""),
    (.context_window.used_percentage // ""),
    (.vim.mode // ""),
    (.agent.name // ""),
    (.session_name // ""),
    (.context_window.current_usage.input_tokens // ""),
    (.context_window.current_usage.output_tokens // ""),
    (.context_window.current_usage.cache_creation_input_tokens // 0),
    (.context_window.current_usage.cache_read_input_tokens // 0),
    (.context_window.total_input_tokens // ""),
    (.context_window.total_output_tokens // ""),
    (.cost.total_cost_usd // "")
  ] | map(tostring) | join("\u001f")')

# --- Helpers ---
is_num() { case "${1:-}" in '' | *[!0-9]*) return 1 ;; *) return 0 ;; esac; }

fmt_tokens() { # 1234 -> 1.2k, 1200000 -> 1.2M
    local n="${1:-0}"
    is_num "$n" || { printf '0'; return; }
    if   [ "$n" -ge 1000000 ]; then awk -v n="$n" 'BEGIN { printf "%.1fM", n / 1000000 }'
    elif [ "$n" -ge 1000 ];    then awk -v n="$n" 'BEGIN { printf "%.1fk", n / 1000 }'
    else                            printf '%d' "$n"
    fi
}

# --- CWD: shorten $HOME to ~ ---
short_cwd="${cwd/#$HOME/~}"
[ -n "$short_cwd" ] || short_cwd="?"

# --- Git: branch, dirty marker, ahead/behind ---
git_part=""
if git_branch=$(GIT_OPTIONAL_LOCKS=0 git -C "$cwd" symbolic-ref --short HEAD 2>/dev/null); then
    upstream=$(GIT_OPTIONAL_LOCKS=0 git -C "$cwd" rev-parse --abbrev-ref '@{upstream}' 2>/dev/null)
    ahead_behind=""
    if [ -n "$upstream" ]; then
        ahead=$(GIT_OPTIONAL_LOCKS=0 git -C "$cwd" rev-list --count "${upstream}..HEAD" 2>/dev/null)
        behind=$(GIT_OPTIONAL_LOCKS=0 git -C "$cwd" rev-list --count "HEAD..${upstream}" 2>/dev/null)
        if is_num "${ahead:-}" && [ "$ahead" -gt 0 ]; then ahead_behind="${ahead_behind}+${ahead}"; fi
        if is_num "${behind:-}" && [ "$behind" -gt 0 ]; then ahead_behind="${ahead_behind}-${behind}"; fi
    fi

    dirty=$(GIT_OPTIONAL_LOCKS=0 git -C "$cwd" status --porcelain 2>/dev/null | head -1)
    if [ -n "$dirty" ]; then
        branch_color="$fg_yellow"
        dirty_marker="${fg_orange}*${reset}"
    else
        branch_color="$fg_green"
        dirty_marker=""
    fi

    git_part="${branch_color}${git_branch}${reset}${dirty_marker}"
    [ -n "$ahead_behind" ] && git_part="${git_part}${fg_gray}${ahead_behind}${reset}"
fi

# --- Context window usage bar ---
ctx_part=""
used_int="${used_pct%.*}"
if is_num "${used_int:-}"; then
    if   [ "$used_int" -ge 90 ]; then bar_color="$fg_red"
    elif [ "$used_int" -ge 75 ]; then bar_color="$fg_orange"
    elif [ "$used_int" -ge 50 ]; then bar_color="$fg_yellow"
    else                              bar_color="$fg_green"
    fi

    bar_width=8
    filled=$(( (used_int * bar_width + 50) / 100 ))
    [ "$filled" -gt "$bar_width" ] && filled="$bar_width"
    bar=""
    i=0
    while [ "$i" -lt "$filled" ]; do bar="${bar}#"; i=$((i + 1)); done
    while [ "$i" -lt "$bar_width" ]; do bar="${bar}."; i=$((i + 1)); done

    ctx_part="${bar_color}${bar}${reset} ${fg_gray}${used_int}%${reset}"
fi

# --- Per-message tokens: in, out, plus cache read/write when non-zero ---
msg_tok_part=""
if is_num "${msg_in:-}" && is_num "${msg_out:-}"; then
    msg_tok_part="${fg_gray}msg:${reset} ${fg_cyan}in $(fmt_tokens "$msg_in")${reset} ${fg_purple}out $(fmt_tokens "$msg_out")${reset}"
    if is_num "${msg_cache_r:-}" && [ "$msg_cache_r" -gt 0 ]; then
        msg_tok_part="${msg_tok_part} ${fg_gray}cr $(fmt_tokens "$msg_cache_r")${reset}"
    fi
    if is_num "${msg_cache_w:-}" && [ "$msg_cache_w" -gt 0 ]; then
        msg_tok_part="${msg_tok_part} ${fg_gray}cw $(fmt_tokens "$msg_cache_w")${reset}"
    fi
fi

# --- Session cumulative tokens ---
sess_tok_part=""
if is_num "${sess_in:-}" && is_num "${sess_out:-}"; then
    sess_tok_part="${fg_gray}ses:${reset} ${fg_white}$(fmt_tokens $((sess_in + sess_out)))${reset}"
fi

# --- Session cost, straight from the hook payload (no external ledger) ---
cost_part=""
if [ -n "$cost_usd" ]; then
    cost_fmt=$(awk -v c="$cost_usd" 'BEGIN { if (c + 0 > 0) printf "%.2f", c }' 2>/dev/null)
    [ -n "$cost_fmt" ] && cost_part="${fg_yellow}\$${cost_fmt}${reset}"
fi

# --- Agent badge, session name, vim mode ---
agent_part=""
[ -n "$agent_name" ] && agent_part="${fg_teal}[${agent_name}]${reset}"

session_part=""
[ -n "$session_name" ] && session_part="${fg_gray}\"${session_name}\"${reset}"

vim_part=""
case "$vim_mode" in
    '')      ;;
    NORMAL)  vim_part="${fg_cyan}NOR${reset}" ;;
    INSERT)  vim_part="${fg_purple}INS${reset}" ;;
    *)       vim_part="${fg_gray}${vim_mode}${reset}" ;;
esac

# --- Assemble: cwd always, every other segment only when it has content ---
line="${fg_blue}${bold}${short_cwd}${reset}"
for part in "$git_part" "$session_part" "${model:+${fg_teal}${model}${reset}}" \
            "$ctx_part" "$msg_tok_part" "$sess_tok_part" "$cost_part" \
            "$agent_part" "$vim_part"; do
    [ -n "$part" ] && line="${line}  ${sep}  ${part}"
done

printf '%b\n' "$line"
