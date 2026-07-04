#!/usr/bin/env bash
#
# install.sh — install these Claude Code rules + example settings into ~/.claude.
# Portable and hook-free. Rules land in ~/.claude/rules/, which Claude Code
# auto-loads at the start of every session. Nothing here overwrites your work
# without backing it up first.

set -euo pipefail

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEST="$HOME/.claude"
ts="$(date +%Y%m%d-%H%M%S)"

mkdir -p "$DEST/rules"

# --- rules: copy into ~/.claude/rules (auto-loaded at session start) ---
for f in "$SRC"/rules/*.md; do
  name="$(basename "$f")"
  d="$DEST/rules/$name"
  if [ -e "$d" ] && ! diff -q "$f" "$d" >/dev/null 2>&1; then
    cp "$d" "$d.bak-$ts"
    echo "backed up existing rules/$name -> rules/$name.bak-$ts"
  fi
  cp "$f" "$d"
  echo "installed rules/$name"
done

# --- settings: never clobber an existing settings.json ---
if [ -f "$DEST/settings.json" ]; then
  cp "$SRC/settings.example.json" "$DEST/settings.example.json"
  echo
  echo "NOTE: ~/.claude/settings.json already exists — left it untouched."
  echo "      Wrote the template to ~/.claude/settings.example.json instead."
  echo "      Merge the 'permissions' (deny/ask) block into your settings.json by hand."
else
  cp "$SRC/settings.example.json" "$DEST/settings.json"
  echo "installed settings.json (from template)"
fi

echo
echo "Done. Restart Claude Code and run /memory to confirm the rules loaded."
echo "If your version does not auto-load ~/.claude/rules/, add these to ~/.claude/CLAUDE.md:"
for f in "$SRC"/rules/*.md; do echo "  @~/.claude/rules/$(basename "$f")"; done
