#!/usr/bin/env bash
# Acceptance test for the hook path: template, library, resolver, git runner,
# grading, retire, reinstall.
#
# Every property here was a bug once:
#   * a hook fired on `echo "git commit"` and stayed silent on `git -C . commit`
#   * self-tests polluted fires.log
#   * grades were a counter with no fire behind them
#   * retire left the hook registered and running
#   * a commit from a terminal saw no hook at all
#   * reinstall crashed on a CLAUDE.md with a byte cp1252 cannot decode
#
#   bash tests/hooks.sh [tmpdir]
set -uo pipefail

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
T="${1:-${TMPDIR:-/tmp}/na-hooks-test}"

na_python() {
  c=""
  for c in ${NA_PYTHON:-} python3 python py; do
    [ -n "$c" ] || continue
    if "$c" -c 'import sys' >/dev/null 2>&1; then
      command -v "$c"
      return 0
    fi
  done
  return 1
}
PYBIN="$(na_python)" || { echo "no working python found"; exit 1; }
PASS=0; FAIL=0
ok()   { PASS=$((PASS+1)); echo "  PASS  $1"; }
bad()  { FAIL=$((FAIL+1)); echo "  FAIL  $1"; }
check(){ if eval "$2"; then ok "$1"; else bad "$1"; fi; }

# Never run inside the source checkout, or anywhere we did not just create. A
# failed cd once left this script committing fixtures into the tool repo.
case "$T" in "$SRC"|"$SRC"/*) echo "refusing to run inside $SRC"; exit 1 ;; esac
rm -rf "$T" && mkdir -p "$T" && cd "$T" || { echo "cannot create $T"; exit 1; }
[ "$(pwd -P)" != "$(cd "$SRC" && pwd -P)" ] || { echo "refusing to run inside $SRC"; exit 1; }
git init -q .
git config user.email test@example.com
git config user.name test
git config commit.gpgsign false
echo base > a.txt
git add a.txt && git commit -qm init

export CLAUDE_PROJECT_DIR="$T"
NA=".claude/never-again/na"
LOG=".claude/never-again/fires.log"
HOOK=".claude/hooks/na/L001.sh"

# The hook under test is the template itself, with a check that flags any
# changed .txt file containing the marker word. Run through bash explicitly
# with a JSON payload, the way Claude Code runs it.
fire() { printf '{"tool_input":{"command":%s}%s}' "$("$PYBIN" -c 'import json,sys;print(json.dumps(sys.argv[1]))' "$1")" "${2:+,\"tool_use_id\":\"$2\"}" | bash "$HOOK"; }
after() { printf '{"tool_use_id":"%s"}' "${1:-}" | bash .claude/hooks/na/_after.sh; }
logn() { [ -f "$LOG" ] && grep -c . "$LOG" || echo 0; }
col() { awk -F'\t' -v n="$1" 'END{print $n}' "$LOG"; }    # last line, column n

echo "=== install ==="
bash "$SRC/install.sh" . >/dev/null 2>&1 || { echo "install failed"; exit 1; }
check "library installed"          '[ -f .claude/hooks/na/na-lib.sh ]'
check "resolver installed"         '[ -x .claude/hooks/na/_after.sh ]'
check "git runner installed"       '[ -x .claude/hooks/na/pre-commit ]'
check "git stub installed"         'grep -q never-again .git/hooks/pre-commit'
check "resolver registered"        'grep -q _after.sh .claude/settings.json'

cp .claude/never-again/hook-template.sh "$HOOK"
"$PYBIN" - "$HOOK" <<'PY'
import sys, io
p = sys.argv[1]
s = io.open(p, encoding="utf-8").read()
s = s.replace('ID="L000"', 'ID="L001"').replace('RULE="one-line rule text"', 'RULE="no TODO-BLOCK in committed text"')
s = s.replace('DETAIL=""\n', 'DETAIL=""\nwhile IFS= read -r f; do [ -f "$NA_ROOT/$f" ] || continue; '
              'if grep -q TODO-BLOCK "$NA_ROOT/$f"; then VIOLATION=1; DETAIL="$DETAIL $f"; fi; '
              'done < <(na_changed_files .txt)\n', 1)
io.open(p, "w", encoding="utf-8", newline="\n").write(s)
PY
"$PYBIN" - <<'PY'
import json, io
p = '.claude/settings.json'
d = json.load(io.open(p, encoding='utf-8'))
d['hooks'].setdefault('PreToolUse', []).append({"matcher": "Bash", "hooks": [
    {"type": "command", "if": "Bash(git commit *)", "command": '"$CLAUDE_PROJECT_DIR"/.claude/hooks/na/L001.sh'}]})
json.dump(d, io.open(p, 'w', encoding='utf-8'), indent=2)
p = '.claude/never-again/state.json'
s = json.load(io.open(p, encoding='utf-8'))
s['lessons']['L001'] = {"scope": "test", "rule": "no TODO-BLOCK", "form": "hook", "mode": "warn",
                        "filed": "2026-01-01", "hook": ".claude/hooks/na/L001.sh"}
s['nextId'] = 2
json.dump(s, io.open(p, 'w', encoding='utf-8'), indent=2)
PY

echo
echo "=== decides from the command, not the substring ==="
check "clean tree: silent"                '[ -z "$(fire "git commit -m x")" ]'
echo TODO-BLOCK > b.txt
check "unstaged change: asks"             'fire "git commit -m x" | grep -q "\"ask\""'
check "names the file"                    'fire "git commit -m x" | grep -q "b.txt"'
check "one fire per run logged"           '[ "$(logn)" -eq 2 ]'
check "echo of the words: silent"         '[ -z "$(NA_DRY_RUN=1 fire "echo git commit")" ]'
check "unrelated command: silent"         '[ -z "$(NA_DRY_RUN=1 fire "ls -la")" ]'
check "double space: asks"                'NA_DRY_RUN=1 fire "git  commit -m x" | grep -q "\"ask\""'
check "git -C . commit: asks"             'NA_DRY_RUN=1 fire "git -C . commit -m x" | grep -q "\"ask\""'
check "git -c k=v commit: asks"           'NA_DRY_RUN=1 fire "git -c core.autocrlf=false commit -m x" | grep -q "\"ask\""'
check "add && commit chain: asks"         'NA_DRY_RUN=1 fire "git add -A && git commit -m x" | grep -q "\"ask\""'
check "dry run wrote nothing"             '[ "$(logn)" -eq 2 ]'

echo
echo "=== outcome is recorded, not guessed ==="
: > "$LOG"
fire "git commit -m x" t1 >/dev/null
check "fire is pending"                   '[ "$(col 5)" = pending ]'
check "carries the tool_use_id"           '[ "$(col 7)" = t1 ]'
after t1
check "after the call: proceeded"         '[ "$(col 5)" = proceeded ]'
fire "git commit -m x" t2 >/dev/null
fire "git commit -m x" t3 >/dev/null
check "same hook firing again settles the last as declined" \
                                          '[ "$(awk -F"\t" "NR==2{print \$5}" "$LOG")" = declined ]'
check "newest still pending"              '[ "$(col 5)" = pending ]'

echo
echo "=== grades attach to fires ==="
OUT="$("$PYBIN" $NA ok L001 2>&1)"
check "na ok grades the latest fire"      'echo "$OUT" | grep -q "graded"'
check "grade written to the log"          '[ "$(col 6)" = ok ]'
OUT="$("$PYBIN" $NA ok L001 2>&1)"
check "second ok grades the older fire"   '[ "$(awk -F"\t" "NR==2{print \$6}" "$LOG")" = ok ]'
OUT="$("$PYBIN" $NA ok L001 2>&1)"; OUT="$("$PYBIN" $NA ok L001 2>&1)"; RC=$?
check "nothing left to grade: refuses"    '[ $RC -ne 0 ] && echo "$OUT" | grep -q "no ungraded"'
"$PYBIN" $NA wrong L001 >/dev/null 2>&1
: > "$LOG"
for i in 1 2 3 4 5 6; do fire "git commit -m x" >/dev/null; done
check "declined fires count toward the streak" '"$PYBIN" $NA | grep -q "ready to promote: L001"'
OUT="$("$PYBIN" $NA)"
check "stats show per-hook outcomes"      'echo "$OUT" | grep -q "declined"'

echo
echo "=== the same hook guards git itself ==="
: > "$LOG"
git add b.txt
ERR="$(bash .claude/hooks/na/pre-commit 2>&1 >/dev/null)"; RC=$?
check "runner warns on stderr"            'echo "$ERR" | grep -q "L001 would block"'
check "warn mode lets git proceed"        '[ $RC -eq 0 ]'
check "git fire logged as proceeded"      '[ "$(col 4)" = git ] && [ "$(col 5)" = proceeded ]'
"$PYBIN" $NA promote L001 >/dev/null
ERR="$(git commit -qm x 2>&1)"; RC=$?
check "block mode: real git commit refused" '[ $RC -ne 0 ]'
check "refusal names the hook"            'echo "$ERR" | grep -q "L001 blocked"'
check "logged as blocked"                 '[ "$(col 5)" = blocked ]'
"$PYBIN" $NA demote L001 >/dev/null
git commit -qm x 2>/dev/null; RC=$?
check "warn mode: real git commit goes through" '[ $RC -eq 0 ]'

echo
echo "=== one commit, one fire, even with both runners ==="
: > "$LOG"
echo TODO-BLOCK > c.txt
fire "git add c.txt && git commit -m x" t9 >/dev/null
git add c.txt
ERR="$(bash .claude/hooks/na/pre-commit 2>&1 >/dev/null)"
check "git runner stays quiet after Claude asked" '[ -z "$ERR" ]'
check "and records that the person proceeded"  '[ "$(logn)" -eq 1 ] && [ "$(col 5)" = proceeded ]'
git commit -qm x 2>/dev/null

echo
echo "=== retire stops the cost ==="
"$PYBIN" $NA retire L001 >/dev/null
check "deregistered from settings.json"   '! grep -q "L001.sh" .claude/settings.json'
check "resolver entry kept"               'grep -q _after.sh .claude/settings.json'
check "script moved to the archive"       '[ ! -f "$HOOK" ] && [ -f .claude/never-again/archive/L001.sh ]'
echo TODO-BLOCK > d.txt; git add d.txt
check "git runner has nothing to run"     '[ -z "$(bash .claude/hooks/na/pre-commit 2>&1)" ]'

echo
echo "=== reinstall is safe ==="
printf '\n# Notes\nOwner: \xc5\x81ukasz\n' >> CLAUDE.md
bash "$SRC/install.sh" . >/dev/null 2>&1; RC=$?
check "reinstall survives non-cp1252 bytes" '[ $RC -eq 0 ]'
check "block present exactly once"        '[ "$(grep -c "BEGIN never-again" CLAUDE.md)" -eq 1 ]'
check "user text kept"                    'grep -q ukasz CLAUDE.md'
check "resolver registered once per event" \
  '[ "$("$PYBIN" -c "import json,io;d=json.load(io.open(\".claude/settings.json\",encoding=\"utf-8\"));print(sum(1 for e in (\"PostToolUse\",\"PostToolUseFailure\") for g in d[\"hooks\"].get(e,[]) for h in g[\"hooks\"] if \"_after\" in h[\"command\"]))")" -eq 2 ]'

echo
echo "=== a LESSONS.md that predates the tool ==="
printf '# My notes\n\nAlways run the tests before pushing.\nNever hardcode the API key.\n' > LESSONS.md
OUT4="$(bash "$SRC/install.sh" . 2>&1)"
check "file left untouched"               '[ "$(grep -c . LESSONS.md)" -eq 3 ] && grep -q "hardcode" LESSONS.md'
check "install says the notes are invisible to na" 'echo "$OUT4" | grep -q "2 line(s) of notes in your own words"'
check "and says how to bring them in"     'echo "$OUT4" | grep -q "refile each note"'
printf -- '- [ci] Run the tests before pushing — when: before push (L001)\n' >> LESSONS.md
OUT5="$(bash "$SRC/install.sh" . 2>&1)"
check "mixed file: counts filed and notes" 'echo "$OUT5" | grep -q "1 filed, 2 note(s)"'

echo
echo "=== a repo's own docs/LESSONS.md is not adopted ==="
mkdir -p docs
printf '# Project record\n\n- [ops] Rotate the key monthly — when: first Monday (L001)\n' > docs/LESSONS.md
OUT6="$("$PYBIN" $NA)"
check "na counts the root file only"       'echo "$OUT6" | grep -q "across 1 file "'
"$PYBIN" $NA sort >/dev/null 2>&1
check "na sort left it alone"              'grep -q "Rotate the key" docs/LESSONS.md && [ "$(grep -c . docs/LESSONS.md)" -eq 2 ]'
mkdir -p packages/api && cp .claude/never-again/lessons-template.md packages/api/LESSONS.md
printf -- '- [api] Validate the schema — when: before commit (L002)\n' >> packages/api/LESSONS.md
check "a marked package file is counted"   '"$PYBIN" $NA | grep -q "across 2 files"'
check "and loads from inside the package"  '(cd packages/api && CLAUDE_PROJECT_DIR="$T" "$PYBIN" "$T/$NA" | grep -q "loaded here     2")'

echo
echo "=== CLAUDE.md.bak stays out of git ==="
check "backup is gitignored"               'git check-ignore -q CLAUDE.md.bak'

echo
echo "=== a hand-deleted .claude/ does not break commits ==="
mv .claude .claude.off
echo x > e.txt; git add e.txt
git commit -qm x 2>/dev/null; RC=$?
check "stub exits 0 without its runner"    '[ $RC -eq 0 ]'
mv .claude.off .claude

echo
echo "=== a repo that ignores .claude/ is told ==="
printf '.claude/\n' >> .gitignore
OUT7="$(bash "$SRC/install.sh" . 2>&1)"
check "install warns the hooks stay local" 'echo "$OUT7" | grep -q "NOT shared through git"'
check "and prints the un-ignore lines"     'echo "$OUT7" | grep -q "!.claude/hooks/na/"'
sed -i '/^\.claude\/$/d' .gitignore

echo
echo "=== a static host is told ==="
echo '{}' > vercel.json
OUT8="$(bash "$SRC/install.sh" . 2>&1)"
check "vercel: warns about /LESSONS.md"    'echo "$OUT8" | grep -q "serve /LESSONS.md publicly"'
echo 'LESSONS.md' > .vercelignore
OUT9="$(bash "$SRC/install.sh" . 2>&1)"
check "vercel: quiet once ignored"         '! echo "$OUT9" | grep -q "serve /LESSONS.md"'
rm -f vercel.json .vercelignore

echo
echo "  ---------------------------------"
echo "  $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
