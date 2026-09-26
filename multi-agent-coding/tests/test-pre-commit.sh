#!/usr/bin/env bash
# managed-by: multi-agent-coding
# The secrets gate, end to end: a real temp repo whose core.hooksPath points at
# this kit's githooks directory. The missing-gitleaks path is checked first so it
# is covered on machines that do not have the scanner at all.
source "$(dirname "$0")/lib.sh"

HOOK="$KIT/githooks/pre-commit"
BASH_BIN="$(command -v bash)"

t_assert "githooks/pre-commit is executable" test -x "$HOOK"

echo "-- gitleaks missing: warn, do not block --"
EMPTY_BIN="$TMP_HOME/empty-bin"
mkdir -p "$EMPTY_BIN"
WARN="$TMP_HOME/warning.txt"
env PATH="$EMPTY_BIN" "$BASH_BIN" "$HOOK" >/dev/null 2>"$WARN"
t_assert_eq "exits 0 when gitleaks is not on PATH" 0 "$?"
t_assert_grep "warns that staged changes were NOT scanned" 'WARNING: gitleaks not installed' "$WARN"

t_require gitleaks

echo "-- gitleaks present: staged secret blocks the commit --"
REPO="$TMP_HOME/repo"
mkdir -p "$REPO"
git init -q "$REPO"
git -C "$REPO" config core.hooksPath "$KIT/githooks"
git -C "$REPO" config user.email test@example.invalid
git -C "$REPO" config user.name "kit test"

printf 'hello\n' > "$REPO/readme.txt"
git -C "$REPO" add readme.txt
t_assert "a clean staged change still commits with the gate enabled" \
  git -C "$REPO" commit -m "add readme"

# Split literal: a fake AWS access key id (AKIA + 16 uppercase/digits) that must
# look real to the scanner without sitting in this file as one matchable token.
# It is matched by the scanner's aws-access-token rule, not by an entropy guess.
FAKE_KEY="AKIA""QYLPMN5HNXUEFCGB"
printf 'aws_access_key_id = "%s"\n' "$FAKE_KEY" > "$REPO/creds.txt"
git -C "$REPO" add creds.txt
t_assert_fail "rejects a commit whose staged diff contains an AWS-style key" \
  git -C "$REPO" commit -m "add creds"

REASON="$TMP_HOME/reason.txt"
( cd "$REPO" && "$BASH_BIN" "$HOOK" ) >/dev/null 2>"$REASON"
t_assert_eq "the hook itself exits 1 on a staged secret" 1 "$?"
t_assert_grep "says gitleaks found the secret and how not to bypass it" \
  'gitleaks found staged secrets' "$REASON"
t_assert_grep "names --no-verify as the thing not to do" 'no-verify' "$REASON"

t_done
