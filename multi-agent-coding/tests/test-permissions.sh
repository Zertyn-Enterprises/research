#!/usr/bin/env bash
# managed-by: multi-agent-coding
# config/permissions.json is merged into a CLI's settings, so its shape matters
# as much as its content: only the two arrays we own, only rule kinds that exist,
# and none of the private-setup leftovers the fragment was derived from.
source "$(dirname "$0")/lib.sh"
t_require jq

F="$KIT/config/permissions.json"

t_assert "config/permissions.json is valid JSON" jq -e . "$F"
t_assert_eq "carries only the deny and ask keys" "ask deny" "$(jq -r 'keys | sort | join(" ")' "$F")"
t_assert "deny and ask are non-empty arrays of strings" jq -e \
  '(.deny | type == "array") and (.ask | type == "array")
   and ((.deny + .ask) | length > 0)
   and ((.deny + .ask) | map(type == "string") | all)' "$F"

BAD="$(jq -r '(.deny + .ask)[] | select(test("^(Bash|Edit|Read)\\(") | not)' "$F")"
t_assert_eq "every rule targets Bash(), Edit() or Read()" "" "$BAD"

# Write() never matched path rules for editing a file; Edit() does.
t_assert_not_grep "no Write() rule" 'Write\(' "$F"
t_assert_not_grep "does not set defaultMode" 'defaultMode' "$F"
t_assert_not_grep "does not set additionalDirectories" 'additionalDirectories' "$F"
t_assert_not_grep "no rule for a private secrets file" 'secrets-' "$F"
# Assembled from two halves so this test file does not itself contain the token.
PRIVATE_DIR='\.ag''ency'
t_assert_not_grep "no reference to a private rules directory" "$PRIVATE_DIR" "$F"

t_assert_grep "asks before editing .env files" '"Edit\(\.env\)"' "$F"
t_assert_grep "denies reading .env files" '"Read\(\.env\)"' "$F"
t_assert_not_grep "does not deny .env.* wholesale (the rules tell agents to read .env.example)" '"Read\((\*\*/)?\.env\.\*\)"' "$F"
t_assert_grep "denies reading .env.local" '"Read\(\.env\.local\)"' "$F"
t_assert_grep "denies the Linux root wipe" '"Bash\(sudo rm -[rf]+ /\*\)"' "$F"
t_assert_grep "denies filesystem creation" '"Bash\(mkfs\*\)"' "$F"
t_assert_grep "denies the Linux power command" '"Bash\(systemctl poweroff\*\)"' "$F"

t_done
