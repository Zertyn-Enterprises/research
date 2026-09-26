#!/usr/bin/env bash
# managed-by: multi-agent-coding
# doctor.sh: what it reports, and that it reports it without writing anything.
# Self-contained: it uses a fixture package, not the shipped content files.
source "$(dirname "$0")/lib.sh"

export MAC_SKIP_PATH_DETECT=1   # detect CLIs by config dir only: deterministic everywhere
unset XDG_CONFIG_HOME
t_require jq
t_require git

PKG="$TMP_HOME/pkg"
LOGS="$TMP_HOME/logs"
mkdir -p "$LOGS"

make_pkg() { # doctor needs only the library and the rules file
  mkdir -p "$PKG/lib" "$PKG/rules"
  cp "$KIT/doctor.sh" "$PKG/doctor.sh"
  cp "$KIT/lib/kit.sh" "$PKG/lib/kit.sh"
  printf '<!-- managed-by: multi-agent-coding -->\n# Core rules (fixture)\n' > "$PKG/rules/core.md"
}

new_home() {
  local name="$1"; shift
  HOME="$TMP_HOME/h-$name"
  export HOME
  MULTI_AGENT_CODING_HOME="$HOME/.multi-agent-coding"
  export MULTI_AGENT_CODING_HOME
  GIT_CONFIG_GLOBAL="$HOME/.gitconfig"
  export GIT_CONFIG_GLOBAL
  PREFIX="$MULTI_AGENT_CODING_HOME"
  mkdir -p "$HOME"
  local d
  for d in "$@"; do mkdir -p "$HOME/$d"; done
}

tree_hash() {
  local root="$1" p
  if [ ! -d "$root" ]; then printf 'absent\n'; return 0; fi
  {
    cd "$root" || return 1
    find . | LC_ALL=C sort | while IFS= read -r p; do
      if [ -L "$p" ]; then printf 'L %s %s\n' "$p" "$(readlink "$p")"
      elif [ -d "$p" ]; then printf 'D %s\n' "$p"
      else printf 'F %s %s\n' "$p" "$(shasum -a 256 "$p" | awk '{print $1}')"
      fi
    done
  } | shasum -a 256 | awk '{print $1}'
}

rc_of() { "$@" >/dev/null 2>&1; printf '%s\n' "$?"; }
run_log() { local log="$1"; shift; "$@" > "$log" 2>&1; printf '%s\n' "$?"; }

make_pkg
PKG="$(cd "$PKG" && pwd)"   # normalise: mktemp can hand back a doubled slash

# ---------------------------------------------------------------- usage

t_assert "doctor --help exits 0" bash "$PKG/doctor.sh" --help
t_assert_eq "doctor rejects an unknown flag with exit 2" "2" "$(rc_of bash "$PKG/doctor.sh" --nope)"
t_assert_eq "doctor rejects an empty --prefix with exit 2" "2" "$(rc_of bash "$PKG/doctor.sh" --prefix "")"
t_assert_eq "doctor rejects --prefix= with exit 2" "2" "$(rc_of bash "$PKG/doctor.sh" --prefix=)"
bash "$PKG/doctor.sh" --help > "$LOGS/help.log" 2>&1
t_assert_grep "the help says it writes nothing" "Writes nothing, ever" "$LOGS/help.log"
t_assert_grep "the help documents --prefix" "^  --prefix DIR" "$LOGS/help.log"
t_assert_grep "the help documents the exit codes" "Exit codes: 0 ready" "$LOGS/help.log"

# ---------------------------------------------------------------- a clean machine

new_home clean
rc="$(run_log "$LOGS/clean.log" bash "$PKG/doctor.sh")"
t_assert_eq "doctor on a clean HOME exits 0" "0" "$rc"
t_assert_grep "it reports the operating system" "^  os: (macOS|Linux|WSL2)$" "$LOGS/clean.log"
t_assert_grep "it reports the bash version" "^  bash: [0-9]" "$LOGS/clean.log"
t_assert_grep "it reports git" "^  git: /" "$LOGS/clean.log"
t_assert_grep "it reports jq" "^  jq: /" "$LOGS/clean.log"
t_assert_grep "it reports gitleaks either way" "^  gitleaks: " "$LOGS/clean.log"
t_assert_not_grep "it does not mention python3 (nothing in v0.1 uses it)" "python3" "$LOGS/clean.log"
t_assert_grep "it reports the global git hooks path" "^  global core.hooksPath: " "$LOGS/clean.log"
t_assert_grep "it reports the package path" "package: $PKG" "$LOGS/clean.log"
t_assert_grep "it reports the install prefix" "install prefix: $PREFIX" "$LOGS/clean.log"
t_assert_grep "it reports the rules file size" "rules/core.md: [0-9]+ bytes" "$LOGS/clean.log"
t_assert_grep "it says nothing is installed yet" "manifest: none" "$LOGS/clean.log"
t_assert_grep "it finds no Claude Code" "Claude Code: not found" "$LOGS/clean.log"
t_assert_grep "it finds no Codex" "Codex: not found" "$LOGS/clean.log"
t_assert_grep "it finds no Grok Build" "Grok Build: not found" "$LOGS/clean.log"
t_assert_grep "it notes that Kimi and GLM share the Claude dir" "Kimi and GLM" "$LOGS/clean.log"
t_assert_grep "it has nothing to back up" "nothing — no file of yours would be replaced" "$LOGS/clean.log"
t_assert_grep "it ends with a result line" "^result: ready$" "$LOGS/clean.log"
t_assert_eq "doctor wrote nothing at all" "absent" "$(tree_hash "$PREFIX")"

# ---------------------------------------------------------------- read-only

new_home readonly .claude/rules .codex .grok
printf 'my own rules\n' > "$HOME/.claude/rules/core.md"
printf '{"model":"x"}\n' > "$HOME/.claude/settings.json"
printf 'project_doc_max_bytes = 4096\n' > "$HOME/.codex/config.toml"
mkdir -p "$PREFIX"
printf 'file\t%s\n' "$HOME/.claude/rules/core.md" > "$PREFIX/manifest.txt"
before="$(tree_hash "$HOME")"
rc="$(run_log "$LOGS/ro.log" bash "$PKG/doctor.sh")"
after="$(tree_hash "$HOME")"
t_assert_eq "doctor exits 0 with every CLI present" "0" "$rc"
t_assert_eq "doctor leaves HOME byte-identical" "$before" "$after"
t_assert_grep "it detects Claude Code by config dir" "Claude Code: present \(config dir" "$LOGS/ro.log"
t_assert_grep "it detects Codex by config dir" "Codex: present \(config dir" "$LOGS/ro.log"
t_assert_grep "it detects Grok Build by config dir" "Grok Build: present \(config dir" "$LOGS/ro.log"
t_assert_grep "it explains the Grok compat path" "Grok Build reads the Claude rules dir" "$LOGS/ro.log"
t_assert_grep "it points at grok inspect" "grok inspect" "$LOGS/ro.log"
t_assert_grep "it reports the current Codex byte cap" "codex project_doc_max_bytes: 4096" "$LOGS/ro.log"
t_assert_grep "it counts the manifest entries" "manifest: $PREFIX/manifest.txt \(1 entries\)" "$LOGS/ro.log"
t_assert_grep "it lists a foreign rules file as a backup candidate" \
  "^  $HOME/.claude/rules/core.md$" "$LOGS/ro.log"
t_assert_grep "it lists a foreign settings.json as a backup candidate" \
  "^  $HOME/.claude/settings.json$" "$LOGS/ro.log"
t_assert_grep "it lists a foreign config.toml as a backup candidate" \
  "^  $HOME/.codex/config.toml$" "$LOGS/ro.log"

# a file of ours is not a backup candidate
printf '<!-- managed-by: multi-agent-coding -->\nours\n' > "$HOME/.claude/rules/core.md"
rc="$(run_log "$LOGS/ro2.log" bash "$PKG/doctor.sh")"
t_assert_eq "doctor still exits 0" "0" "$rc"
t_assert_not_grep "a file of ours is not listed for backup" \
  "^  $HOME/.claude/rules/core.md$" "$LOGS/ro2.log"

# ---------------------------------------------------------------- CLAUDE_CONFIG_DIR

new_home altdir
mkdir -p "$HOME/.claude-alt"
CLAUDE_CONFIG_DIR="$HOME/.claude-alt"
export CLAUDE_CONFIG_DIR
rc="$(run_log "$LOGS/alt.log" bash "$PKG/doctor.sh")"
t_assert_eq "doctor exits 0 with CLAUDE_CONFIG_DIR set" "0" "$rc"
t_assert_grep "it warns about CLAUDE_CONFIG_DIR" "WARNING: CLAUDE_CONFIG_DIR is set" "$LOGS/alt.log"
t_assert_grep "it uses that directory" "config dir: $HOME/.claude-alt \(CLAUDE_CONFIG_DIR\)" "$LOGS/alt.log"
t_assert_grep "it detects Claude Code there" "Claude Code: present" "$LOGS/alt.log"
unset CLAUDE_CONFIG_DIR

# ---------------------------------------------------------------- --prefix

new_home prefixflag .claude
mkdir -p "$HOME/elsewhere"
printf 'file\t/x\nlink\t/y\n' > "$HOME/elsewhere/manifest.txt"
rc="$(run_log "$LOGS/prefix.log" bash "$PKG/doctor.sh" --prefix "$HOME/elsewhere")"
t_assert_eq "doctor --prefix exits 0" "0" "$rc"
t_assert_grep "doctor --prefix reads that manifest" "manifest: $HOME/elsewhere/manifest.txt \(2 entries\)" "$LOGS/prefix.log"
rc="$(run_log "$LOGS/prefix-bad.log" bash "$PKG/doctor.sh" --prefix /tmp/outside-home)"
t_assert_eq "a prefix outside HOME fails with exit 1" "1" "$rc"
t_assert_grep "it says the prefix must be inside HOME" "must live inside HOME" "$LOGS/prefix-bad.log"

# ---------------------------------------------------------------- incomplete package

BROKEN="$TMP_HOME/pkg-broken"
mkdir -p "$BROKEN"
cp -R "$PKG/lib" "$BROKEN/lib"
cp "$PKG/doctor.sh" "$BROKEN/doctor.sh"
new_home broken .claude
rc="$(run_log "$LOGS/broken.log" bash "$BROKEN/doctor.sh")"
t_assert_eq "doctor exits 1 when the rules file is missing" "1" "$rc"
t_assert_grep "it names the missing rules file" "rules/core.md: MISSING" "$LOGS/broken.log"
t_assert_grep "its result line says a dependency is missing" "^result: a hard dependency is missing" "$LOGS/broken.log"

NOLIB="$TMP_HOME/pkg-nolib"
mkdir -p "$NOLIB"
cp "$PKG/doctor.sh" "$NOLIB/doctor.sh"
rc="$(run_log "$LOGS/nolib.log" bash "$NOLIB/doctor.sh")"
t_assert_eq "doctor exits 1 without lib/kit.sh" "1" "$rc"
t_assert_grep "it names lib/kit.sh" "missing package file: lib/kit.sh" "$LOGS/nolib.log"

t_done
