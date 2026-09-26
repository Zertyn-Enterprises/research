#!/usr/bin/env bash
# managed-by: multi-agent-coding
# Scrub the package: no private-setup leftovers anywhere, every "<Section> §n"
# citation in rules/core.md resolves to a real heading, and the rules file stays
# small enough for the strictest CLI to load whole.
# This file is the only one excluded from the token scan (it has to name the tokens).
set -u

# shellcheck source=tests/lib.sh
source "$(dirname "$0")/lib.sh"

CORE="$KIT/rules/core.md"
t_assert "rules/core.md exists" test -f "$CORE"

# ---------------------------------------------------------------- file lists
ALL="$TMP_HOME/scrub-all.txt"
MAIN="$TMP_HOME/scrub-main.txt"
NOEXC="$TMP_HOME/scrub-noexc.txt"

find "$KIT" -type f -print | LC_ALL=C sort > "$ALL"
grep -Fvx -e "$KIT/tests/test-scrub.sh" "$ALL" > "$MAIN" || :
# Ghostty and tokuse are allowed in exactly these two files (see the spec).
grep -Fvx -e "$KIT/ROADMAP.md" -e "$KIT/extras/README.md" "$MAIN" > "$NOEXC" || :

main_files=()
while IFS= read -r f; do [ -n "$f" ] && main_files+=("$f"); done < "$MAIN"
noexc_files=()
while IFS= read -r f; do [ -n "$f" ] && noexc_files+=("$f"); done < "$NOEXC"

t_assert "the package has files to scan" test "${#main_files[@]}" -gt 0

# The public repository's own clone URL is the one place the org name belongs.
PUBLIC_URL='github\.com/Zertyn-Enterprises/research'

scan() { # scan <ere> <"all"|"noexc"> -> prints file:line hits (max 10)
  local pat="$1" set_name="$2"
  if [ "$set_name" = noexc ]; then
    [ "${#noexc_files[@]}" -gt 0 ] || return 0
    grep -inHE -- "$pat" "${noexc_files[@]}" < /dev/null 2>/dev/null | grep -vE -- "$PUBLIC_URL" | head -10
  else
    [ "${#main_files[@]}" -gt 0 ] || return 0
    grep -inHE -- "$pat" "${main_files[@]}" < /dev/null 2>/dev/null | grep -vE -- "$PUBLIC_URL" | head -10
  fi
}

# ------------------------------------------- 1. forbidden tokens, one per token
while IFS= read -r tok; do
  [ -n "$tok" ] || continue
  case "$tok" in
    Ghostty | tokuse) hits="$(scan "$tok" noexc)" ;;
    *) hits="$(scan "$tok" all)" ;;
  esac
  t_assert_eq "no forbidden token: $tok" "" "$hits"
done <<'TOKENS'
zertyn
02_hq
01_lab
03_archive
PENDIENTES
Fable
Astra
gpt-5\.6
~/\.agency
\.agency/
heimdall
phame
viraloop
some3c
hecaton
singularity
kino
nexus
intentx
roomify
bozzetto
178\.156
zertynsolutions
@gmail
Ghostty
tokuse
/Users/
/srv/
SUPERGROK
NECESITO
HICE
OPCIONES
SI NADA
TOKENS

# ----------------------------------------- 2. every "<Section> §n" ref resolves
# Pass 1 collects "# Section" + "## n." headings; pass 2 checks each §n citation.
# A bare §n (nothing capitalised before it, or a connector word like "see"/"the")
# is a reference to the current section and is not checked.
REFCHK="$TMP_HOME/refcheck.awk"
cat > "$REFCHK" <<'AWK'
function norm(t) {
  gsub(/^[^A-Za-z&]+/, "", t)
  gsub(/[^A-Za-z&-]+$/, "", t)
  return t
}
function check(pre, num, lineno,   n, w, i, runstart, s, k, cand, longest, resolved, lw) {
  sub(/[ \t]+$/, "", pre)
  n = split(pre, w, /[ \t]+/)
  for (i = 1; i <= n; i++) w[i] = norm(w[i])
  runstart = n + 1
  for (i = n; i >= 1; i--) {
    if (w[i] ~ /^([A-Za-z][A-Za-z-]*|&)$/) runstart = i
    else break
  }
  if (runstart > n) return                      # bare §n
  resolved = 0
  for (s = runstart; s <= n; s++) {
    cand = w[s]
    for (k = s + 1; k <= n; k++) cand = cand " " w[k]
    if (s == runstart) longest = cand
    if ((cand SUBSEP num) in valid) { resolved = 1; break }
  }
  if (resolved) return
  lw = tolower(w[n])
  if (lw in connector) return                   # relative reference
  printf "rules/core.md:%d: unresolved reference \"%s %s%s\"\n", lineno, longest, SEC, num
}
BEGIN {
  split("see in on the of and at per from to under above these this its by with", c, " ")
  for (i in c) connector[c[i]] = 1
}
NR == FNR {
  if (substr($0, 1, 2) == "# ") {
    name = substr($0, 3)
    p = index(name, " " EM)
    if (p > 0) name = substr(name, 1, p - 1)
    sub(/[ \t]+$/, "", name)
    section = name
  } else if (substr($0, 1, 3) == "## ") {
    rest = substr($0, 4)
    if (match(rest, /^[0-9]+\./) && section != "") {
      valid[section SUBSEP substr(rest, 1, RLENGTH - 1)] = 1
      seen++
    }
  }
  next
}
{
  rest = $0
  while (match(rest, SEC "[0-9]+")) {
    m = substr(rest, RSTART, RLENGTH)
    pre = substr(rest, 1, RSTART - 1)
    rest = substr(rest, RSTART + RLENGTH)
    gsub(/[^0-9]/, "", m)
    if (m != "") check(pre, m, FNR)
  }
}
END { if (seen == 0) print "refcheck: no \"## n.\" headings found — parser broken" }
AWK

unresolved="$(LC_ALL=C awk -v EM="—" -v SEC="§" -f "$REFCHK" "$CORE" "$CORE" 2>&1)"
t_assert_eq "every <Section> §n reference in rules/core.md resolves" "" "$unresolved"

# --------------------------------------------------------- 3. size of the rules
bytes="$(wc -c < "$CORE" | tr -d ' ')"
t_assert "rules/core.md is under 40000 bytes (is $bytes)" test "$bytes" -lt 40000

# ------------------------------------- 4. no private wording in rules/core.md
while IFS= read -r tok; do
  [ -n "$tok" ] || continue
  hits="$(grep -inHE -- "$tok" "$CORE" < /dev/null 2>/dev/null | head -10)"
  t_assert_eq "rules/core.md has no \"$tok\"" "" "$hits"
done <<'RULETOKENS'
dispatch
headless
Zertyn
VPS
PENDIENTES
~/\.agency
NECESITO
RULETOKENS

# ------------------------------------------------- 5. English brief labels
for label in '▍NEED' '▍DID' '▍OPTIONS' '▍IF SILENT'; do
  t_assert_grep "rules/core.md defines $label" "$label" "$CORE"
done

t_done
