#!/usr/bin/env bash
# managed-by: multi-agent-coding
# tools/agentsify: the four handled cases, the two that need a human, --dry-run,
# --stage, and a git worktree.
source "$(dirname "$0")/lib.sh"
t_require git

AGENTSIFY="$KIT/tools/agentsify"
OUT="$HOME/out"
mkdir -p "$OUT"

git config --global init.defaultBranch main
git config --global user.email tester@example.invalid
git config --global user.name tester

# The kit template normally comes from level 4 of the installer; the test ships
# its own so it depends on nothing outside the temp HOME.
mkdir -p "$MULTI_AGENT_CODING_HOME/templates"
cat > "$MULTI_AGENT_CODING_HOME/templates/AGENTS.md" <<'TPL'
# AGENTS.md — <repo>

Rules of this repo for every agent.

## Stack and commands
- install - dev - test - lint - typecheck - build

## Repo rules
- <conventions an agent cannot infer from the code>
TPL

mkrepo() { # mkrepo <path> -> an initialized repo with one commit
  mkdir -p "$1"
  git init -q "$1"
  echo hello > "$1/file.txt"
  git -C "$1" add file.txt
  git -C "$1" commit -qm "initial"
}

# --- Case 1: neither file exists -> AGENTS.md from the template + symlink ---
R1="$HOME/case1"
mkrepo "$R1"
t_assert "case 1 exits 0" bash "$AGENTSIFY" "$R1"
t_assert "case 1 AGENTS.md is a regular file" test -f "$R1/AGENTS.md"
t_assert_grep "case 1 fills the repo name from the template" "AGENTS.md — case1" "$R1/AGENTS.md"
t_assert "case 1 CLAUDE.md is a symlink" test -L "$R1/CLAUDE.md"
t_assert_eq "case 1 symlink points at AGENTS.md" "AGENTS.md" "$(readlink "$R1/CLAUDE.md")"
t_assert_grep "case 1 symlink resolves" "AGENTS.md — case1" "$R1/CLAUDE.md"
t_assert "case 1 stages nothing without --stage" \
  test -z "$(git -C "$R1" diff --cached --name-only)"

# --- Case 2: CLAUDE.md is a tracked regular file, no AGENTS.md ---
R2="$HOME/case2"
mkrepo "$R2"
printf '# rules of case2\n' > "$R2/CLAUDE.md"
git -C "$R2" add CLAUDE.md
git -C "$R2" commit -qm "add instructions"
t_assert "case 2 exits 0" bash "$AGENTSIFY" "$R2"
t_assert "case 2 AGENTS.md is a regular file" test -f "$R2/AGENTS.md"
t_assert_grep "case 2 keeps the original content" "rules of case2" "$R2/AGENTS.md"
t_assert_eq "case 2 symlink points at AGENTS.md" "AGENTS.md" "$(readlink "$R2/CLAUDE.md")"
t_assert "case 2 records the rename in the index" \
  bash -c "git -C '$R2' diff --cached --name-only | grep -qx AGENTS.md"

# --- Case 3: already standard -> no-op ---
t_assert "case 3 exits 0 on a second run" bash "$AGENTSIFY" "$R1"
bash "$AGENTSIFY" "$R1" > "$OUT/case3.txt" 2>&1
t_assert_grep "case 3 says it is already standard" "already standard" "$OUT/case3.txt"
t_assert_eq "case 3 leaves the symlink alone" "AGENTS.md" "$(readlink "$R1/CLAUDE.md")"
t_assert_grep "case 3 leaves AGENTS.md alone" "AGENTS.md — case1" "$R1/AGENTS.md"

# --- Case 4: CLAUDE.md is a symlink to a missing target -> replaced ---
R4="$HOME/case4"
mkrepo "$R4"
ln -s docs/gone.md "$R4/CLAUDE.md"
t_assert "case 4 sees a broken symlink" test -L "$R4/CLAUDE.md"
bash "$AGENTSIFY" "$R4" > "$OUT/case4.txt" 2>&1
t_assert_grep "case 4 reports the replacement" "replace: broken symlink" "$OUT/case4.txt"
t_assert_eq "case 4 relinks to AGENTS.md" "AGENTS.md" "$(readlink "$R4/CLAUDE.md")"
t_assert "case 4 created AGENTS.md from the template" test -f "$R4/AGENTS.md"

# --- Needs a human: CLAUDE.md symlinks to another file that exists ---
R5="$HOME/case5"
mkrepo "$R5"
printf '# product state\n' > "$R5/CONTEXT.md"
ln -s CONTEXT.md "$R5/CLAUDE.md"
t_assert_fail "mixed rules and state exits non-zero" bash "$AGENTSIFY" "$R5"
t_assert_eq "mixed rules and state is left untouched" "CONTEXT.md" "$(readlink "$R5/CLAUDE.md")"
t_assert "mixed rules and state creates no AGENTS.md" test ! -e "$R5/AGENTS.md"

# --- Needs a human: two different regular files ---
R6="$HOME/case6"
mkrepo "$R6"
printf '# a\n' > "$R6/CLAUDE.md"
printf '# b\n' > "$R6/AGENTS.md"
t_assert_fail "two regular files exit non-zero" bash "$AGENTSIFY" "$R6"
t_assert "two regular files: CLAUDE.md is still a file" test -f "$R6/CLAUDE.md"
t_assert_grep "two regular files: AGENTS.md untouched" "^# b$" "$R6/AGENTS.md"

# --- --dry-run writes nothing ---
R7="$HOME/case7"
mkrepo "$R7"
bash "$AGENTSIFY" --dry-run "$R7" > "$OUT/dry.txt" 2>&1
t_assert_eq "dry run exits 0" "0" "$?"
t_assert_grep "dry run announces the creation" "would create: AGENTS.md" "$OUT/dry.txt"
t_assert_grep "dry run announces the link" "would link: CLAUDE.md" "$OUT/dry.txt"
t_assert_grep "dry run says it wrote nothing" "nothing was written" "$OUT/dry.txt"
t_assert "dry run created no AGENTS.md" test ! -e "$R7/AGENTS.md"
t_assert "dry run created no CLAUDE.md" test ! -e "$R7/CLAUDE.md"

# --- --stage stages both paths ---
t_assert "--stage exits 0" bash "$AGENTSIFY" --stage "$R7"
t_assert "--stage staged AGENTS.md" \
  bash -c "git -C '$R7' diff --cached --name-only | grep -qx AGENTS.md"
t_assert "--stage staged CLAUDE.md" \
  bash -c "git -C '$R7' diff --cached --name-only | grep -qx CLAUDE.md"

# --- Inside a git worktree: the worktree root is the repo root ---
R8="$HOME/case8"
mkrepo "$R8"
WT="$HOME/case8-lane"
git -C "$R8" worktree add -q "$WT" -b lane-a
t_assert "worktree run exits 0" bash -c "cd '$WT' && bash '$AGENTSIFY'"
t_assert "worktree got its own AGENTS.md" test -f "$WT/AGENTS.md"
t_assert_eq "worktree symlink points at AGENTS.md" "AGENTS.md" "$(readlink "$WT/CLAUDE.md")"
t_assert "the main checkout was not touched" test ! -e "$R8/AGENTS.md"

# --- Usage errors ---
t_assert_fail "unknown option is a usage error" bash "$AGENTSIFY" --nope
t_assert "--help exits 0" bash "$AGENTSIFY" --help

t_done
