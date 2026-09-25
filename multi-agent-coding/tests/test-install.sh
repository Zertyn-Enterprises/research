#!/usr/bin/env bash
# managed-by: multi-agent-coding
# install.sh / uninstall.sh / lib-kit.sh behaviour, against a self-contained fixture
# package so this file does not depend on the content of any other part of the kit.
# Every case gets its own HOME under the throwaway HOME that lib.sh created.
source "$(dirname "$0")/lib.sh"

export MAC_SKIP_PATH_DETECT=1   # detect CLIs by config dir only: deterministic everywhere
unset XDG_CONFIG_HOME           # keep git --global inside the test HOME
t_require jq
t_require git

PKG="$TMP_HOME/pkg"             # fixture package, deliberately OUTSIDE every case HOME
LOGS="$TMP_HOME/logs"
mkdir -p "$LOGS"

# ---------------------------------------------------------------- helpers

make_pkg() { # a complete package: the real scripts, placeholder content files
  local i=0
  mkdir -p "$PKG/lib" "$PKG/rules" "$PKG/hooks" "$PKG/config" "$PKG/githooks" \
           "$PKG/claude/agents" "$PKG/claude/skills/context-init" "$PKG/claude/skills/techdebt" \
           "$PKG/tools" "$PKG/templates"
  cp "$KIT/install.sh" "$KIT/doctor.sh" "$KIT/uninstall.sh" "$PKG/"
  cp "$KIT/lib/kit.sh" "$PKG/lib/kit.sh"

  # > 4096 bytes on purpose: the Codex cap test needs a rules file bigger than a low cap
  {
    printf '<!-- managed-by: multi-agent-coding -->\n# Core rules (fixture)\n\n'
    while [ "$i" -lt 120 ]; do
      printf 'Line %s: placeholder rules text for the installer test fixture.\n' "$i"
      i=$((i + 1))
    done
  } > "$PKG/rules/core.md"

  # The fixture hook mimics the real contract: exit 2 on the root wipe, 0 otherwise.
  printf '#!/usr/bin/env bash\n# managed-by: multi-agent-coding\ncase "$(cat)" in *"rm -rf /"*) exit 2 ;; esac\nexit 0\n' > "$PKG/hooks/block-dangerous.sh"
  printf '#!/usr/bin/env bash\n# managed-by: multi-agent-coding\necho fixture-pre-commit\n' > "$PKG/githooks/pre-commit"
  printf '#!/usr/bin/env bash\n# managed-by: multi-agent-coding\necho fixture-statusline\n' > "$PKG/claude/statusline-command.sh"
  printf '#!/usr/bin/env bash\n# managed-by: multi-agent-coding\necho fixture-agentsify\n' > "$PKG/tools/agentsify"
  printf '#!/usr/bin/env bash\n# managed-by: multi-agent-coding\necho fixture-plan-init\n' > "$PKG/tools/plan-init"
  # Agents and skills must open with their YAML frontmatter, so the marker sits below it:
  # the fixture keeps that shape, because ownership detection has to cope with it.
  printf -- '---\nname: test-author\ndescription: fixture\ntools: Read\n---\n<!-- managed-by: multi-agent-coding -->\n' \
    > "$PKG/claude/agents/test-author.md"
  printf -- '---\nname: "context-init"\ndescription: "fixture"\nuser-invocable: true\ndisable-model-invocation: true\n---\n<!-- managed-by: multi-agent-coding -->\n' \
    > "$PKG/claude/skills/context-init/SKILL.md"
  printf -- '---\nname: "techdebt"\ndescription: "fixture"\nuser-invocable: true\ndisable-model-invocation: false\n---\n<!-- managed-by: multi-agent-coding -->\n' \
    > "$PKG/claude/skills/techdebt/SKILL.md"
  printf '<!-- managed-by: multi-agent-coding -->\n# AGENTS template (fixture)\n' > "$PKG/templates/AGENTS.md"
  printf '<!-- managed-by: multi-agent-coding -->\n# PLAN template (fixture)\n' > "$PKG/templates/PLAN.md"

  cat > "$PKG/config/hooks.json" <<'JSON'
{"PreToolUse":[{"matcher":"Bash","hooks":[{"type":"command","command":"bash \"@PREFIX@/hooks/block-dangerous.sh\"","timeout":10}]}]}
JSON
  cat > "$PKG/config/permissions.json" <<'JSON'
{"deny":["Read(./.env)","Edit(./.env)"],"ask":["Bash(git push*)","Bash(gh pr merge*)"]}
JSON
  chmod +x "$PKG/install.sh" "$PKG/doctor.sh" "$PKG/uninstall.sh"
}

new_home() { # new_home <case-name> [dirs...] — isolated HOME, optional CLI config dirs
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

tree_hash() { # content + layout digest of a directory (files, dirs, link targets)
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

rc_of() { # run a command, print its exit code
  "$@" >/dev/null 2>&1
  printf '%s\n' "$?"
}

run_log() { # run_log <logfile> <cmd...> — capture stdout+stderr, print the exit code
  local log="$1"; shift
  "$@" > "$log" 2>&1
  printf '%s\n' "$?"
}

count_bak() { find "$1" -name '*.bak-*' 2>/dev/null | wc -l | tr -d ' '; }

jqr() { jq -r "$1" "$2" 2>/dev/null; }

make_pkg
PKG="$(cd "$PKG" && pwd)"   # normalise: mktemp can hand back a doubled slash

# ---------------------------------------------------------------- usage and flags

t_assert "install --help exits 0" bash "$PKG/install.sh" --help
t_assert "uninstall --help exits 0" bash "$PKG/uninstall.sh" --help
t_assert_eq "install --help mentions every level" "4" \
  "$(bash "$PKG/install.sh" --help | grep -cE '^  (1 rules|2 safety|3 claude-quality|4 plan)')"
t_assert_eq "install rejects an unknown flag with exit 2" "2" "$(rc_of bash "$PKG/install.sh" --nope)"
t_assert_eq "install rejects a bad --level with exit 2" "2" "$(rc_of bash "$PKG/install.sh" --level 9 --yes)"
t_assert_eq "install rejects an unknown --only with exit 2" "2" "$(rc_of bash "$PKG/install.sh" --only nope --yes)"
t_assert_eq "uninstall rejects an unknown flag with exit 2" "2" "$(rc_of bash "$PKG/uninstall.sh" --nope)"

# ---------------------------------------------------------------- incomplete package

BROKEN="$TMP_HOME/pkg-broken"
cp -R "$PKG" "$BROKEN"
rm -f "$BROKEN/rules/core.md"
new_home broken .claude
rc="$(run_log "$LOGS/broken.log" bash "$BROKEN/install.sh" --yes --only rules)"
t_assert_eq "an incomplete package fails with exit 1" "1" "$rc"
t_assert_grep "the failure names the missing file" "missing package file: rules/core.md" "$LOGS/broken.log"
t_assert_eq "nothing was written for the broken package" "absent" "$(tree_hash "$PREFIX")"

# ---------------------------------------------------------------- no CLI at all

new_home nocli
rc="$(run_log "$LOGS/nocli.log" bash "$PKG/install.sh" --yes)"
t_assert_eq "no supported CLI fails with exit 1" "1" "$rc"
t_assert_grep "it says no supported CLI was found" "no supported CLI found" "$LOGS/nocli.log"

# ---------------------------------------------------------------- dry run

new_home dry .claude .codex
before="$(tree_hash "$HOME")"
rc="$(run_log "$LOGS/dry.log" bash "$PKG/install.sh" --dry-run --yes)"
after="$(tree_hash "$HOME")"
t_assert_eq "--dry-run exits 0" "0" "$rc"
t_assert_eq "--dry-run leaves HOME byte-identical" "$before" "$after"
t_assert_grep "--dry-run shows the Claude rules path" "would write $HOME/.claude/rules/core.md" "$LOGS/dry.log"
t_assert_grep "--dry-run shows the Codex rules path" "would write $HOME/.codex/AGENTS.md" "$LOGS/dry.log"
t_assert_grep "--dry-run shows the Codex byte cap" "would set project_doc_max_bytes" "$LOGS/dry.log"
t_assert_grep "--dry-run shows the settings.json merge" "would set .hooks.PreToolUse" "$LOGS/dry.log"
t_assert_grep "--dry-run shows the git hooks path" "would run: git config --global core.hooksPath" "$LOGS/dry.log"
t_assert_grep "--dry-run says it wrote nothing" "nothing was written" "$LOGS/dry.log"
t_assert_eq "--dry-run created no manifest" "absent" "$(tree_hash "$PREFIX")"
t_assert_eq "--dry-run wrote no git config" "1" "$(rc_of test -f "$HOME/.gitconfig")"

# ---------------------------------------------------------------- full install

new_home full .claude .codex .grok
rc="$(run_log "$LOGS/full.log" bash "$PKG/install.sh" --yes)"
S="$HOME/.claude/settings.json"
t_assert_eq "a full install exits 0" "0" "$rc"
t_assert "level 1 wrote the Claude rules file" test -f "$HOME/.claude/rules/core.md"
t_assert_grep "the installed rules file carries our marker" "managed-by: multi-agent-coding" "$HOME/.claude/rules/core.md"
t_assert "level 1 wrote the Codex rules file" test -f "$HOME/.codex/AGENTS.md"
t_assert_eq "the Codex rules file is a copy, not a link" "1" "$(rc_of test -L "$HOME/.codex/AGENTS.md")"
t_assert_grep "level 1 raised the Codex byte cap" "^project_doc_max_bytes = 131072$" "$HOME/.codex/config.toml"
t_assert_eq "level 1 wrote nothing under .grok (Claude is present)" "1" "$(rc_of test -e "$HOME/.grok/rules/core.md")"
t_assert_grep "it points at grok inspect instead" "grok inspect" "$LOGS/full.log"
t_assert "level 2 copied the hook into the prefix" test -x "$PREFIX/hooks/block-dangerous.sh"
t_assert "level 2 copied the pre-commit hook" test -x "$PREFIX/githooks/pre-commit"
t_assert_eq "level 2 wired the hook into settings.json" "1" \
  "$(jq "[.hooks.PreToolUse[].hooks[].command] | map(select(contains(\"$PREFIX/hooks/block-dangerous.sh\"))) | length" "$S")"
t_assert_eq "level 2 merged our deny entries" "true" "$(jqr '.permissions.deny | index("Read(./.env)") != null' "$S")"
t_assert_eq "level 2 merged our ask entries" "true" "$(jqr '.permissions.ask | index("Bash(git push*)") != null' "$S")"
t_assert_eq "level 2 wrote the Codex hook file" "1" \
  "$(jq "[.hooks.PreToolUse[].hooks[].command] | map(select(contains(\"block-dangerous\"))) | length" "$HOME/.codex/hooks.json")"
t_assert "level 2 wrote the Grok hook file" test -f "$HOME/.grok/hooks/multi-agent-coding.json"
t_assert_eq "the Grok hook file has our command" "1" \
  "$(jq "[.hooks.PreToolUse[].hooks[].command] | map(select(contains(\"block-dangerous\"))) | length" "$HOME/.grok/hooks/multi-agent-coding.json")"
t_assert_eq "level 2 set the global git hooks path" "$PREFIX/githooks" \
  "$(git config --global --get core.hooksPath)"
t_assert "level 3 wrote the statusline script" test -x "$HOME/.claude/statusline-command.sh"
t_assert_eq "level 3 set .statusLine to our script, quoted" "bash \"$HOME/.claude/statusline-command.sh\"" "$(jqr '.statusLine.command' "$S")"
t_assert "level 3 wrote the test-author agent" test -f "$HOME/.claude/agents/test-author.md"
t_assert "level 3 wrote the context-init skill" test -f "$HOME/.claude/skills/context-init/SKILL.md"
t_assert "level 3 wrote the techdebt skill" test -f "$HOME/.claude/skills/techdebt/SKILL.md"
t_assert_eq "level 3 linked agentsify" "$PREFIX/tools/agentsify" "$(readlink "$HOME/.local/bin/agentsify")"
t_assert_eq "level 3 linked plan-init" "$PREFIX/tools/plan-init" "$(readlink "$HOME/.local/bin/plan-init")"
t_assert "level 4 wrote the AGENTS template" test -f "$PREFIX/templates/AGENTS.md"
t_assert "level 4 wrote the PLAN template" test -f "$PREFIX/templates/PLAN.md"

M="$PREFIX/manifest.txt"
t_assert "the manifest exists" test -f "$M"
for kind in file link settings:hook settings:permissions settings:statusLine codex:cap codex:hook grok:hook git:hooksPath; do
  t_assert_grep "the manifest records $kind" "^$kind	" "$M"
done
t_assert_eq "the manifest has no duplicate line" "0" "$(LC_ALL=C sort "$M" | uniq -d | wc -l | tr -d ' ')"

# ---------------------------------------------------------------- idempotence

lines1="$(wc -l < "$M" | tr -d ' ')"
hash1="$(tree_hash "$HOME")"
bak1="$(count_bak "$HOME")"
rc="$(run_log "$LOGS/full2.log" bash "$PKG/install.sh" --yes)"
t_assert_eq "a second install exits 0" "0" "$rc"
t_assert_eq "a second install changes nothing in HOME" "$hash1" "$(tree_hash "$HOME")"
t_assert_eq "a second install adds no manifest line" "$lines1" "$(wc -l < "$M" | tr -d ' ')"
t_assert_eq "a second install creates no backup" "$bak1" "$(count_bak "$HOME")"
t_assert_eq "a second install still has no duplicate line" "0" "$(LC_ALL=C sort "$M" | uniq -d | wc -l | tr -d ' ')"
t_assert_grep "a second install reports unchanged files" "unchanged $HOME/.claude/rules/core.md" "$LOGS/full2.log"

# ---------------------------------------------------------------- foreign settings.json

new_home merge .claude
cat > "$HOME/.claude/settings.json" <<'JSON'
{
  "permissions": { "defaultMode": "acceptEdits", "deny": ["Read(./private/**)"] },
  "hooks": { "PreToolUse": [ { "matcher": "Bash",
      "hooks": [ { "type": "command", "command": "bash /opt/mine/audit.sh" } ] } ] },
  "statusLine": { "type": "command", "command": "my-own-statusline --fancy" },
  "model": "some-model",
  "env": { "MY_VAR": "1" }
}
JSON
S="$HOME/.claude/settings.json"
rc="$(run_log "$LOGS/merge.log" bash "$PKG/install.sh" --yes --only safety,claude-quality)"
t_assert_eq "installing over a foreign settings.json exits 0" "0" "$rc"
t_assert_eq "it keeps permissions.defaultMode" "acceptEdits" "$(jqr '.permissions.defaultMode' "$S")"
t_assert_eq "it keeps a foreign deny entry" "true" "$(jqr '.permissions.deny | index("Read(./private/**)") != null' "$S")"
t_assert_eq "it keeps the foreign PreToolUse hook" "1" \
  "$(jq '[.hooks.PreToolUse[].hooks[].command] | map(select(contains("/opt/mine/audit.sh"))) | length' "$S")"
t_assert_eq "it adds our hook alongside it" "1" \
  "$(jq '[.hooks.PreToolUse[].hooks[].command] | map(select(contains("block-dangerous"))) | length' "$S")"
t_assert_eq "it keeps a custom statusLine" "my-own-statusline --fancy" "$(jqr '.statusLine.command' "$S")"
t_assert_grep "it says the statusLine was left alone" "left alone: .statusLine" "$LOGS/merge.log"
t_assert_eq "it keeps unrelated top level keys" "some-model" "$(jqr '.model' "$S")"
t_assert_eq "it keeps the env block" "1" "$(jqr '.env.MY_VAR' "$S")"
t_assert_eq "it backed settings.json up once" "1" "$(find "$HOME/.claude" -name 'settings.json.bak-*' | wc -l | tr -d ' ')"
t_assert_eq "no statusLine manifest entry was recorded" "0" \
  "$(grep -c '^settings:statusLine' "$PREFIX/manifest.txt" || true)"

# ---------------------------------------------------------------- Codex byte cap

new_home cap-absent .codex
rc="$(run_log "$LOGS/cap-absent.log" bash "$PKG/install.sh" --yes --only rules)"
t_assert_eq "the cap patch exits 0 when config.toml is absent" "0" "$rc"
t_assert "it creates config.toml" test -f "$HOME/.codex/config.toml"
t_assert_eq "the created file is exactly the one key" "project_doc_max_bytes = 131072" \
  "$(cat "$HOME/.codex/config.toml")"

new_home cap-low .codex
cat > "$HOME/.codex/config.toml" <<'TOML'
model = "some-model"
project_doc_max_bytes = 4096
approval_policy = "on-request"

[tui]
theme = "dark"
TOML
rc="$(run_log "$LOGS/cap-low.log" bash "$PKG/install.sh" --yes --only rules)"
C="$HOME/.codex/config.toml"
t_assert_eq "raising a low cap exits 0" "0" "$rc"
t_assert_grep "it rewrote the key" "^project_doc_max_bytes = 131072$" "$C"
t_assert_not_grep "the old value is gone" "4096" "$C"
t_assert_grep "it kept the other root keys" '^model = "some-model"$' "$C"
t_assert_grep "it kept approval_policy" '^approval_policy = "on-request"$' "$C"
t_assert_grep "it kept the table header" '^\[tui\]$' "$C"
t_assert_grep "it kept the table body" '^theme = "dark"$' "$C"
t_assert_eq "config.toml keeps its 5 content lines" "5" "$(grep -c . "$C")"
t_assert_eq "config.toml keeps its 6 lines in total" "6" "$(wc -l < "$C" | tr -d ' ')"
t_assert_eq "it backed the old config.toml up" "1" "$(find "$HOME/.codex" -name 'config.toml.bak-*' | wc -l | tr -d ' ')"

new_home cap-high .codex
printf 'project_doc_max_bytes = 131072\nmodel = "x"\n' > "$HOME/.codex/config.toml"
before="$(shasum -a 256 "$HOME/.codex/config.toml" | awk '{print $1}')"
rc="$(run_log "$LOGS/cap-high.log" bash "$PKG/install.sh" --yes --only rules)"
t_assert_eq "an already-high cap exits 0" "0" "$rc"
t_assert_grep "it reports the cap as unchanged" "project_doc_max_bytes is 131072" "$LOGS/cap-high.log"
t_assert_eq "it leaves config.toml byte-identical" "$before" \
  "$(shasum -a 256 "$HOME/.codex/config.toml" | awk '{print $1}')"
t_assert_eq "it made no config.toml backup" "0" \
  "$(find "$HOME/.codex" -name 'config.toml.bak-*' | wc -l | tr -d ' ')"

# ---------------------------------------------------------------- Grok without Claude

new_home grok-only .grok
rc="$(run_log "$LOGS/grok.log" bash "$PKG/install.sh" --yes --only rules)"
t_assert_eq "rules for Grok alone exits 0" "0" "$rc"
t_assert "it writes the Grok rules file when Claude is absent" test -f "$HOME/.grok/rules/core.md"
rc="$(run_log "$LOGS/grok-q.log" bash "$PKG/install.sh" --yes --only claude-quality)"
t_assert_eq "claude-quality without Claude exits 0" "0" "$rc"
t_assert_grep "claude-quality says it was skipped" "Claude Code not found" "$LOGS/grok-q.log"
t_assert_eq "it wrote no statusline script" "1" "$(rc_of test -e "$HOME/.claude/statusline-command.sh")"

# ---------------------------------------------------------------- link mode and backups

new_home link .claude
rc="$(run_log "$LOGS/link.log" bash "$PKG/install.sh" --yes --link --only rules,plan)"
t_assert_eq "--link exits 0" "0" "$rc"
t_assert_eq "--link symlinks the rules file into the checkout" "$PKG/rules/core.md" \
  "$(readlink "$HOME/.claude/rules/core.md")"
t_assert_grep "--link records a link in the manifest" "^link	$HOME/.claude/rules/core.md$" "$PREFIX/manifest.txt"

new_home backup .claude/rules
printf 'my own rules, hand written\n' > "$HOME/.claude/rules/core.md"
rc="$(run_log "$LOGS/backup.log" bash "$PKG/install.sh" --yes --only rules)"
t_assert_eq "installing over a foreign rules file exits 0" "0" "$rc"
t_assert_grep "it says what it backed up" "backed up $HOME/.claude/rules/core.md" "$LOGS/backup.log"
t_assert_eq "exactly one backup was made" "1" "$(find "$HOME/.claude/rules" -name 'core.md.bak-*' | wc -l | tr -d ' ')"
t_assert_grep "the backup holds the original text" "hand written" \
  "$(find "$HOME/.claude/rules" -name 'core.md.bak-*' | head -1)"
t_assert_grep "the installed file is ours" "managed-by: multi-agent-coding" "$HOME/.claude/rules/core.md"

# ---------------------------------------------------------------- uninstall

new_home uninst .claude .codex .grok
cat > "$HOME/.claude/settings.json" <<'JSON'
{
  "permissions": { "defaultMode": "acceptEdits", "deny": ["Read(./private/**)"] },
  "hooks": { "PreToolUse": [ { "matcher": "Bash",
      "hooks": [ { "type": "command", "command": "bash /opt/mine/audit.sh" } ] } ],
             "Stop": [ { "matcher": "*", "hooks": [ { "type": "command", "command": "mine-stop" } ] } ] },
  "model": "some-model"
}
JSON
S="$HOME/.claude/settings.json"
bash "$PKG/install.sh" --yes > "$LOGS/uninst-install.log" 2>&1
before_uninstall="$(tree_hash "$HOME")"
rc="$(run_log "$LOGS/uninst-dry.log" bash "$PKG/uninstall.sh" --dry-run)"
t_assert_eq "uninstall --dry-run exits 0" "0" "$rc"
t_assert_eq "uninstall --dry-run changes nothing" "$before_uninstall" "$(tree_hash "$HOME")"
t_assert_grep "uninstall --dry-run lists a removal" "would remove $HOME/.claude/rules/core.md" "$LOGS/uninst-dry.log"

rc="$(run_log "$LOGS/uninst.log" bash "$PKG/uninstall.sh" --yes)"
t_assert_eq "uninstall exits 0" "0" "$rc"
t_assert_eq "it removed the Claude rules file" "1" "$(rc_of test -e "$HOME/.claude/rules/core.md")"
t_assert_eq "it removed the Codex rules file" "1" "$(rc_of test -e "$HOME/.codex/AGENTS.md")"
t_assert_eq "it removed the statusline script" "1" "$(rc_of test -e "$HOME/.claude/statusline-command.sh")"
t_assert_eq "it removed the test-author agent (marker under the frontmatter)" "1" \
  "$(rc_of test -e "$HOME/.claude/agents/test-author.md")"
t_assert_eq "it removed the context-init skill" "1" "$(rc_of test -e "$HOME/.claude/skills/context-init/SKILL.md")"
t_assert_eq "it removed the techdebt skill" "1" "$(rc_of test -e "$HOME/.claude/skills/techdebt/SKILL.md")"
t_assert_not_grep "it left no skill or agent behind" "SKILL.md \(not ours" "$LOGS/uninst.log"
t_assert_eq "it removed the agentsify link" "1" "$(rc_of test -L "$HOME/.local/bin/agentsify")"
t_assert_eq "it removed the hook from the prefix" "1" "$(rc_of test -e "$PREFIX/hooks/block-dangerous.sh")"
t_assert_eq "it removed the Grok hook file" "1" "$(rc_of test -e "$HOME/.grok/hooks/multi-agent-coding.json")"
t_assert_eq "it removed the Codex hook file" "1" "$(rc_of test -e "$HOME/.codex/hooks.json")"
t_assert_eq "it removed the manifest" "1" "$(rc_of test -e "$PREFIX/manifest.txt")"
t_assert_eq "it unset the global git hooks path" "" "$(git config --global --get core.hooksPath || true)"
t_assert_eq "it kept permissions.defaultMode" "acceptEdits" "$(jqr '.permissions.defaultMode' "$S")"
t_assert_eq "it kept the foreign deny entry" "true" "$(jqr '.permissions.deny | index("Read(./private/**)") != null' "$S")"
t_assert_eq "it removed our deny entries" "0" "$(jq '[.permissions.deny[] | select(. == "Edit(./.env)")] | length' "$S")"
t_assert_eq "it removed our ask entries" "null" "$(jqr '.permissions.ask' "$S")"
t_assert_eq "it kept the foreign PreToolUse hook" "1" \
  "$(jq '[.hooks.PreToolUse[].hooks[].command] | map(select(contains("/opt/mine/audit.sh"))) | length' "$S")"
t_assert_eq "it kept the foreign Stop hook" "1" "$(jq '.hooks.Stop | length' "$S")"
t_assert_eq "it removed our hook entry" "0" \
  "$(jq '[.hooks.PreToolUse[].hooks[].command] | map(select(contains("block-dangerous"))) | length' "$S")"
t_assert_eq "it unset the statusLine it had set" "null" "$(jqr '.statusLine' "$S")"
t_assert_eq "it kept unrelated top level keys" "some-model" "$(jqr '.model' "$S")"
t_assert_grep "it reports the Codex cap as left alone" "left alone: project_doc_max_bytes" "$LOGS/uninst.log"
t_assert_grep "the Codex cap is still raised" "^project_doc_max_bytes = 131072$" "$HOME/.codex/config.toml"
rc="$(run_log "$LOGS/uninst2.log" bash "$PKG/uninstall.sh" --yes)"
t_assert_eq "a second uninstall exits 0" "0" "$rc"
t_assert_grep "a second uninstall has nothing to do" "nothing to do" "$LOGS/uninst2.log"

# ---------------------------------------------------------------- --restore-backups

new_home restore .claude/rules .codex
printf 'ORIGINAL hand written rules\n' > "$HOME/.claude/rules/core.md"
printf 'model = "keep-me"\nproject_doc_max_bytes = 4096\n' > "$HOME/.codex/config.toml"
bash "$PKG/install.sh" --yes --only rules > "$LOGS/restore-install.log" 2>&1
t_assert_grep "the install replaced the foreign rules file" "managed-by" "$HOME/.claude/rules/core.md"
rc="$(run_log "$LOGS/restore.log" bash "$PKG/uninstall.sh" --yes --restore-backups)"
t_assert_eq "uninstall --restore-backups exits 0" "0" "$rc"
t_assert_eq "it put the original rules file back" "ORIGINAL hand written rules" \
  "$(cat "$HOME/.claude/rules/core.md")"
t_assert_grep "it says what it restored" "restored $HOME/.claude/rules/core.md" "$LOGS/restore.log"
t_assert_grep "it put the original Codex cap back" "^project_doc_max_bytes = 4096$" "$HOME/.codex/config.toml"
t_assert_grep "the restored config.toml keeps its other keys" '^model = "keep-me"$' "$HOME/.codex/config.toml"

# ---------------------------------------------------------------- a prefix with sed metacharacters

new_home weird-prefix .claude
WEIRD="$HOME/pre&fix|x"
rc="$(run_log "$LOGS/weird.log" bash "$PKG/install.sh" --yes --only safety --prefix "$WEIRD")"
t_assert_eq "install with a prefix containing & and | exits 0" "0" "$rc"
t_assert_eq "the hook command carries the prefix verbatim, quoted" "bash \"$WEIRD/hooks/block-dangerous.sh\"" \
  "$(jq -r '.hooks.PreToolUse[].hooks[].command' "$HOME/.claude/settings.json" | head -1)"
t_assert_eq "install rejects an empty --prefix with exit 2" "2" "$(rc_of bash "$PKG/install.sh" --prefix "" --yes)"

# ---------------------------------------------------------------- a prefix with spaces

new_home space-prefix .claude .codex .grok
SPACED="$HOME/my kit"
rc="$(run_log "$LOGS/spaced.log" bash "$PKG/install.sh" --yes --only safety,claude-quality --prefix "$SPACED")"
t_assert_eq "install with a prefix containing a space exits 0" "0" "$rc"
hook_cmd="$(jq -r '.hooks.PreToolUse[].hooks[].command' "$HOME/.claude/settings.json" | head -1)"
t_assert_eq "the Claude hook command quotes the spaced path" "bash \"$SPACED/hooks/block-dangerous.sh\"" "$hook_cmd"
t_assert_eq "the hook command actually runs from a shell and blocks" "2" \
  "$(printf '{"tool_name":"Bash","tool_input":{"command":"rm -rf /"}}' | sh -c "$hook_cmd" >/dev/null 2>&1; echo $?)"
t_assert_eq "the hook command allows a benign command" "0" \
  "$(printf '{"tool_name":"Bash","tool_input":{"command":"ls"}}' | sh -c "$hook_cmd" >/dev/null 2>&1; echo $?)"
t_assert_grep "the Codex hook file quotes the spaced path" "bash \\\\\"$SPACED/hooks/block-dangerous.sh\\\\\"" "$HOME/.codex/hooks.json"
t_assert_grep "the Grok hook file quotes the spaced path" "bash \\\\\"$SPACED/hooks/block-dangerous.sh\\\\\"" "$HOME/.grok/hooks/multi-agent-coding.json"
sl_cmd="$(jq -r '.statusLine.command' "$HOME/.claude/settings.json")"
t_assert_eq "the statusLine command quotes its path" "bash \"$HOME/.claude/statusline-command.sh\"" "$sl_cmd"
t_assert_eq "the statusLine command runs from a shell" "0" "$(printf '{}' | sh -c "$sl_cmd" >/dev/null 2>&1; echo $?)"
rc="$(run_log "$LOGS/spaced-uninst.log" bash "$PKG/uninstall.sh" --yes --prefix "$SPACED")"
t_assert_eq "uninstall with the spaced prefix exits 0" "0" "$rc"
t_assert_eq "it removed the quoted hook entry" "0" \
  "$(jq '[.hooks.PreToolUse // [] | .[].hooks[].command] | map(select(contains("block-dangerous"))) | length' "$HOME/.claude/settings.json")"
t_assert_eq "it unset the quoted statusLine" "null" "$(jq -r '.statusLine' "$HOME/.claude/settings.json")"
rc="$(run_log "$LOGS/restore-passthru.log" bash "$PKG/install.sh" --uninstall --restore-backups --yes --prefix "$SPACED")"
t_assert_eq "install.sh --uninstall passes --restore-backups through (exit 0)" "0" "$rc"
t_assert_eq "--restore-backups without --uninstall is a usage error" "2" "$(rc_of bash "$PKG/install.sh" --restore-backups --yes)"

# ---------------------------------------------------------------- lost exec bit is restored

new_home execbit .claude
bash "$PKG/install.sh" --yes --only safety > "$LOGS/execbit-1.log" 2>&1
chmod 644 "$HOME/.multi-agent-coding/hooks/block-dangerous.sh"
rc="$(run_log "$LOGS/execbit-2.log" bash "$PKG/install.sh" --yes --only safety)"
t_assert_eq "reinstall over a hook that lost its exec bit exits 0" "0" "$rc"
t_assert "the exec bit is back" test -x "$HOME/.multi-agent-coding/hooks/block-dangerous.sh"
t_assert_grep "it says it restored the mode" "restored mode 755" "$LOGS/execbit-2.log"

# ---------------------------------------------------------------- Codex cap: a same-named key inside a [table] is not the root key

new_home codex-table .claude .codex
printf '[tui]\nproject_doc_max_bytes = 4096\ntheme = "dark"\n' > "$HOME/.codex/config.toml"
bash "$PKG/install.sh" --yes --only rules > "$LOGS/codex-table.log" 2>&1
t_assert_eq "the root key is prepended" "project_doc_max_bytes = 131072" "$(head -1 "$HOME/.codex/config.toml")"
t_assert_grep "the [tui] table keeps its own key untouched" "^project_doc_max_bytes = 4096$" "$HOME/.codex/config.toml"
t_assert_grep "the [tui] table is intact" '^theme = "dark"$' "$HOME/.codex/config.toml"
t_assert_eq "exactly one root-table key" "1" "$(awk '/^[[:space:]]*\[/ { exit } /^project_doc_max_bytes/ { n++ } END { print n+0 }' "$HOME/.codex/config.toml")"

# ---------------------------------------------------------------- --uninstall takes no selection

new_home uninst-guard .claude
rc="$(run_log "$LOGS/uninst-only.log" bash "$PKG/install.sh" --uninstall --only rules)"
t_assert_eq "--uninstall with --only is a usage error (exit 2)" "2" "$rc"
t_assert_grep "it says why" "removes everything the manifest lists" "$LOGS/uninst-only.log"
rc="$(run_log "$LOGS/uninst-level.log" bash "$PKG/install.sh" --uninstall --level 2 --yes)"
t_assert_eq "--uninstall with --level is a usage error (exit 2)" "2" "$rc"
rc="$(run_log "$LOGS/uninst-link.log" bash "$PKG/install.sh" --uninstall --link --yes)"
t_assert_eq "--uninstall with --link is a usage error (exit 2)" "2" "$rc"

# ---------------------------------------------------------------- jq preflight, before any write

new_home nojq .claude .codex
STUB="$HOME/stub-bin"
mkdir -p "$STUB"
for b in bash sh git sed awk grep mkdir cp ln cat printf mktemp dirname basename date tr head tail \
         wc sort uniq find chmod mv rm readlink cut env ls id uname touch tee diff cmp expr sleep \
         true false test stat od hostname xargs; do
  p="$(command -v "$b" 2>/dev/null || true)"
  [ -n "$p" ] && ln -sf "$p" "$STUB/$b"
done
t_assert_fail "the stub PATH really hides jq" env -i "PATH=$STUB" "HOME=$HOME" "$STUB/bash" -c 'command -v jq'
rc="$(run_log "$LOGS/nojq-safety.log" env -i "PATH=$STUB" "HOME=$HOME" "GIT_CONFIG_GLOBAL=$HOME/.gitconfig" \
      MAC_SKIP_PATH_DETECT=1 "$STUB/bash" "$PKG/install.sh" --yes --only safety)"
t_assert_eq "level 2 without jq aborts (exit 1)" "1" "$rc"
t_assert_grep "it names jq and the levels that need it" "jq is required for level 2" "$LOGS/nojq-safety.log"
t_assert_grep "it says nothing was written" "Nothing was written" "$LOGS/nojq-safety.log"
t_assert_eq "it wrote no manifest" "1" "$(rc_of test -e "$HOME/.multi-agent-coding/manifest.txt")"
t_assert_eq "it wrote nothing under the prefix" "1" "$(rc_of test -e "$HOME/.multi-agent-coding")"
rc="$(run_log "$LOGS/nojq-rules.log" env -i "PATH=$STUB" "HOME=$HOME" "GIT_CONFIG_GLOBAL=$HOME/.gitconfig" \
      MAC_SKIP_PATH_DETECT=1 "$STUB/bash" "$PKG/install.sh" --yes --only rules,plan)"
t_assert_eq "levels 1 and 4 install without jq (exit 0)" "0" "$rc"
t_assert_grep "the rules landed without jq" "managed-by" "$HOME/.claude/rules/core.md"

t_done
