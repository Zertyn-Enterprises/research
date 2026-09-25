#!/usr/bin/env bash
# managed-by: multi-agent-coding
# claude/statusline-command.sh: one line on stdout, exit 0, and a plain
# fallback when jq is not on PATH.
source "$(dirname "$0")/lib.sh"
t_require jq
t_require git

SL="$KIT/claude/statusline-command.sh"
WORK="$HOME/work"
mkdir -p "$WORK"

# A repo so the git segment is exercised on a real branch.
git config --global init.defaultBranch main
REPO="$HOME/repo"
mkdir -p "$REPO"
git init -q "$REPO"
git -C "$REPO" config user.email tester@example.invalid
git -C "$REPO" config user.name tester
git -C "$REPO" checkout -q -b lane-a 2>/dev/null || true
echo hello > "$REPO/file.txt"
git -C "$REPO" add file.txt
git -C "$REPO" commit -qm "initial"

# Realistic Claude Code status-line payload.
cat > "$WORK/in.json" <<JSON
{
  "hook_event_name": "Status",
  "session_id": "0123456789abcdef",
  "session_name": "lane-a",
  "transcript_path": "$HOME/.claude/projects/x/y.jsonl",
  "cwd": "$REPO",
  "model": { "id": "claude-sonnet-x", "display_name": "Sonnet 4.6" },
  "workspace": { "current_dir": "$REPO", "project_dir": "$REPO" },
  "version": "2.0.0",
  "output_style": { "name": "default" },
  "vim": { "mode": "NORMAL" },
  "agent": { "name": "test-author" },
  "cost": {
    "total_cost_usd": 1.2345,
    "total_duration_ms": 61000,
    "total_lines_added": 42,
    "total_lines_removed": 7
  },
  "context_window": {
    "used_percentage": 63.4,
    "remaining_percentage": 36.6,
    "total_input_tokens": 1250000,
    "total_output_tokens": 45000,
    "current_usage": {
      "input_tokens": 4321,
      "output_tokens": 512,
      "cache_creation_input_tokens": 2048,
      "cache_read_input_tokens": 98765
    }
  }
}
JSON

run_statusline() { # run_statusline <out-file>
  bash "$SL" < "$WORK/in.json" > "$1" 2> "$1.err"
}

t_assert "exits 0 on a full payload" run_statusline "$WORK/out.txt"
t_assert_eq "prints exactly one line" "1" "$(wc -l < "$WORK/out.txt" | tr -d ' ')"
t_assert_eq "that line is not empty" "1" "$(grep -c . "$WORK/out.txt" | tr -d ' ')"
t_assert_eq "writes nothing to stderr" "" "$(cat "$WORK/out.txt.err")"
t_assert_grep "shows the model" "Sonnet 4\.6" "$WORK/out.txt"
t_assert_grep "shows the branch" "lane-a" "$WORK/out.txt"
t_assert_grep "shows the context percentage" "63%" "$WORK/out.txt"
t_assert_grep "shows the session cost" '\$1\.23' "$WORK/out.txt"
t_assert_grep "shows the compacted message tokens" "4\.3k" "$WORK/out.txt"

# An empty object must still render a line rather than blow up on missing fields.
echo '{}' > "$WORK/empty.json"
t_assert "exits 0 on an empty object" bash -c "bash '$SL' < '$WORK/empty.json' > '$WORK/out-empty.txt'"
t_assert_eq "empty object still prints one line" "1" "$(grep -c . "$WORK/out-empty.txt" | tr -d ' ')"

# --- Fallback with jq hidden: a bin dir holding everything BUT jq. ---
STUB="$HOME/stub-bin"
mkdir -p "$STUB"
for b in bash sh env cat sed awk head tail tr git wc grep printf; do
  p="$(command -v "$b" 2>/dev/null || true)"
  [ -n "$p" ] && ln -sf "$p" "$STUB/$b"
done
in_stub() { env -i "PATH=$STUB" "$STUB/bash" -c "$1"; }
t_assert_fail "the stub bin dir really hides jq" in_stub 'command -v jq'
t_assert "the stub bin dir still provides sed" in_stub 'command -v sed'

fallback() {
  env -i "PATH=$STUB" "HOME=$HOME" "$STUB/bash" "$SL" \
    < "$WORK/in.json" > "$WORK/out-nojq.txt" 2> "$WORK/out-nojq.err"
}
t_assert "exits 0 without jq" fallback
t_assert_eq "fallback prints exactly one non-empty line" "1" \
  "$(grep -c . "$WORK/out-nojq.txt" | tr -d ' ')"
t_assert_grep "fallback names the missing dependency" "jq" "$WORK/out-nojq.txt"
t_assert_grep "fallback still shows where it is" "repo" "$WORK/out-nojq.txt"

t_done
