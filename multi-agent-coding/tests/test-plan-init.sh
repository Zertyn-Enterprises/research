#!/usr/bin/env bash
# managed-by: multi-agent-coding
# tools/plan-init: lane file in the main checkout, PLAN.md symlink in the current
# worktree, git-excluded, never overwritten on a second run.
source "$(dirname "$0")/lib.sh"
t_require git

PLAN_INIT="$KIT/tools/plan-init"
OUT="$HOME/out"
mkdir -p "$OUT"

git config --global init.defaultBranch main
git config --global user.email tester@example.invalid
git config --global user.name tester

# The kit template normally comes from level 4 of the installer; the test ships
# its own so it depends on nothing outside the temp HOME.
mkdir -p "$MULTI_AGENT_CODING_HOME/templates"
cat > "$MULTI_AGENT_CODING_HOME/templates/PLAN.md" <<'TPL'
# PLAN — <lane>

- **Lane:** <lane>
- **Base:** main@<sha7>
- **Merge policy:** docs auto - code hold - deploy never
- **Budget per task:** 2 distinct approaches - ~8 error retries - no scope growth

## Tasks

### 1. <short title>
- goal:
- acceptance:
- scope:
- merge:

## Status (append-only, one line per event)
TPL

MAIN="$HOME/repo"
mkdir -p "$MAIN"
# The temp HOME can sit under a symlinked parent; git reports physical paths, so
# compare against physical paths too.
MAIN="$(cd "$MAIN" && pwd -P)"
git init -q "$MAIN"
echo hello > "$MAIN/file.txt"
git -C "$MAIN" add file.txt
git -C "$MAIN" commit -qm "initial"

WT="$HOME/repo-lane-a"
git -C "$MAIN" worktree add -q "$WT" -b lane-a
WT="$(cd "$WT" && pwd -P)"

LANE_FILE="$MAIN/.claude/plans/lane-a.md"
EXCLUDE="$MAIN/.git/info/exclude"

# --- From inside the worktree: the plan file lands in the MAIN checkout ---
t_assert "exits 0 inside a worktree" bash -c "cd '$WT' && bash '$PLAN_INIT' lane-a"
t_assert "lane file created in the main checkout" test -f "$LANE_FILE"
t_assert_grep "lane name substituted in the template" "^# PLAN — lane-a$" "$LANE_FILE"
t_assert_grep "template keeps the Status section" "^## Status" "$LANE_FILE"
t_assert "no plans dir inside the worktree" test ! -e "$WT/.claude/plans"
t_assert "PLAN.md in the worktree is a symlink" test -L "$WT/PLAN.md"
t_assert_eq "the symlink points at the lane file" "$LANE_FILE" "$(readlink "$WT/PLAN.md")"
t_assert_grep "the symlink resolves to the plan" "^# PLAN — lane-a$" "$WT/PLAN.md"

# --- Exclusions go in the COMMON .git so every worktree inherits them ---
t_assert "the common exclude file exists" test -f "$EXCLUDE"
t_assert_grep "PLAN.md is excluded" "^PLAN\.md$" "$EXCLUDE"
t_assert_grep ".claude/plans/ is excluded" "^\.claude/plans/$" "$EXCLUDE"
t_assert "the worktree is not git-dirty" \
  test -z "$(git -C "$WT" status --porcelain)"

# --- Second run: idempotent, and the lane file is never overwritten ---
printf -- '- 2026-01-01 09:00 T1 started - lane-a@abc1234\n' >> "$LANE_FILE"
before="$(cat "$LANE_FILE")"
t_assert "second run exits 0" bash -c "cd '$WT' && bash '$PLAN_INIT' lane-a"
t_assert_eq "second run keeps the lane file byte for byte" "$before" "$(cat "$LANE_FILE")"
bash -c "cd '$WT' && bash '$PLAN_INIT' lane-a" > "$OUT/second.txt" 2>&1
t_assert_grep "second run says it kept the file" "^kept: " "$OUT/second.txt"
t_assert_grep "second run reports the existing link" "^ok: " "$OUT/second.txt"
t_assert_eq "second run does not duplicate the exclude entry" "1" \
  "$(grep -c '^PLAN\.md$' "$EXCLUDE" | tr -d ' ')"

# --- From the main checkout, and from a subdirectory of it ---
t_assert "exits 0 in the main checkout" bash -c "cd '$MAIN' && bash '$PLAN_INIT' lane-b"
t_assert "second lane file created" test -f "$MAIN/.claude/plans/lane-b.md"
t_assert_eq "main checkout PLAN.md points at lane-b" \
  "$MAIN/.claude/plans/lane-b.md" "$(readlink "$MAIN/PLAN.md")"

mkdir -p "$MAIN/deep/sub"
SUB_WT="$HOME/repo-lane-c"
git -C "$MAIN" worktree add -q "$SUB_WT" -b lane-c
SUB_WT="$(cd "$SUB_WT" && pwd -P)"
mkdir -p "$SUB_WT/deep/sub"
t_assert "exits 0 from a subdirectory of a worktree" \
  bash -c "cd '$SUB_WT/deep/sub' && bash '$PLAN_INIT' lane-c"
t_assert_eq "the link is created at the worktree root, not the subdirectory" \
  "$MAIN/.claude/plans/lane-c.md" "$(readlink "$SUB_WT/PLAN.md")"
t_assert "no PLAN.md in the subdirectory" test ! -e "$SUB_WT/deep/sub/PLAN.md"

# --- Refusals ---
R_FILE="$HOME/repo-file"
mkdir -p "$R_FILE"
git init -q "$R_FILE"
printf '# handwritten\n' > "$R_FILE/PLAN.md"
t_assert_fail "a regular PLAN.md is never clobbered" \
  bash -c "cd '$R_FILE' && bash '$PLAN_INIT' lane-x"
t_assert_grep "the handwritten PLAN.md survives" "handwritten" "$R_FILE/PLAN.md"

t_assert_fail "a lane name with a path separator is rejected" \
  bash -c "cd '$MAIN' && bash '$PLAN_INIT' ../escape"
t_assert "the traversal wrote nothing outside the plans dir" test ! -e "$HOME/escape.md"

t_assert_fail "a missing lane name is a usage error" bash -c "cd '$MAIN' && bash '$PLAN_INIT'"
t_assert_fail "outside a git repository it fails" bash -c "cd '$HOME' && bash '$PLAN_INIT' lane-z"
t_assert "--help exits 0" bash "$PLAN_INIT" --help

t_done
