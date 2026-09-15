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
check "emoji in the message: still asks"  'NA_DRY_RUN=1 fire "git commit -m \"fix 🤖 footer\"" | grep -q "\"ask\""'
check "quoted mention of git commit: silent" '[ -z "$(NA_DRY_RUN=1 fire "echo \"{\\\"command\\\":\\\"x && git commit -m x\\\"}\" | cat")" ]'
check "chain helper: single command is not a chain" '! (source .claude/hooks/na/na-lib.sh; na_is_chain "git commit -m x")'
check "chain helper: checkout && commit is"  '(source .claude/hooks/na/na-lib.sh; na_is_chain "git checkout -b fix && git commit -m x")'

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
cp .claude/never-again/lessons-template.md LESSONS.md
printf -- '- [ci] Run the tests before pushing — when: before push (L001)\n' >> LESSONS.md
OUT5b="$(bash "$SRC/install.sh" . 2>&1)"
check "template header is not counted as notes" 'echo "$OUT5b" | grep -q "left untouched (1 filed)$"'

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
echo "=== a verify-shaped hook runs the check itself ==="
# The check: fail when any .txt file contains BROKEN, and count its runs. Any
# command works here; a test suite or a browser boot is the same shape.
printf '#!/bin/sh\necho run >> runs.log\n! grep -rl BROKEN --include=*.txt --exclude-dir=vendor --exclude-dir=.claude . >/dev/null\n' > check.sh
printf 'runs.log\nvendor/\n' >> .gitignore
mkdir -p vendor nested/scripts scripts && echo BROKEN > vendor/ignored.txt && echo x > nested/scripts/deep.txt && echo x > scripts/top.txt
git add -A >/dev/null 2>&1; git commit -qm "fixture" >/dev/null 2>&1   # before the hook exists: no runner pass
cp .claude/never-again/hook-verify-template.sh .claude/hooks/na/L002.sh
"$PYBIN" - <<'PY'
import json, io
p = '.claude/hooks/na/L002.sh'
s = io.open(p, encoding='utf-8').read().replace('ID="L000"', 'ID="L002"').replace(
    'RULE="the check must pass before committing"', 'RULE="the smoke check must pass before committing"')
io.open(p, 'w', encoding='utf-8', newline='\n').write(s)
p = '.claude/never-again/state.json'
st = json.load(io.open(p, encoding='utf-8'))
st['lessons']['L002'] = {"form": "hook", "mode": "warn", "hook": ".claude/hooks/na/L002.sh",
                         "verify": {"run": "sh check.sh", "watch": ".txt", "skip": "scripts"}}
json.dump(st, io.open(p, 'w', encoding='utf-8'), indent=2)
PY
V=".claude/hooks/na/L002.sh"; VM=".claude/never-again/verified/L002"
firev() { HOOK="$V" NA_DRY_RUN=1 fire "git commit -m x"; }
firelive() { HOOK="$V" fire "git commit -m x" "${1:-}"; }
runs() { if [ -f runs.log ]; then grep -c . runs.log || true; else echo 0; fi; }
setcfg() { "$PYBIN" -c "
import json, io, sys
p = '.claude/never-again/state.json'
st = json.load(io.open(p, encoding='utf-8'))
if sys.argv[1] == 'del': st['lessons']['L002'].pop('verify', None)
else: st['lessons']['L002']['verify'] = json.loads(sys.argv[1])
json.dump(st, io.open(p, 'w', encoding='utf-8'), indent=2)" "$1"; }
check "dry run: runs the check, records nothing" '[ -z "$(firev)" ] && [ ! -f "$VM" ] && [ "$(runs)" -eq 1 ]'
: > runs.log
check "never verified: runs the check, passes, silent" '[ -z "$(firelive)" ] && [ -f "$VM" ] && [ "$(runs)" -eq 1 ]'
check "string config is one item, not characters" 'grep -q "a.txt" "$VM"'
check "the command's own script is watched"    'grep -q "check.sh" "$VM"'
check "gitignored files are never watched"    '! grep -q "vendor/ignored.txt" "$VM"'
check "skip is a root prefix, nested kept"    '! grep -q "scripts/top.txt" "$VM" && grep -q "nested/scripts/deep.txt" "$VM"'
check "unchanged: fast path, no run"          '[ -z "$(firelive)" ] && [ "$(runs)" -eq 1 ]'
sleep 2.2; touch -m a.txt
check "touched but identical: still no run"   '[ -z "$(firelive)" ] && [ "$(runs)" -eq 1 ]'
"$PYBIN" - <<'PY'
import os, time
st = os.stat('a.txt'); time.sleep(2.2)
open('a.txt', 'w').write('bass\n')                       # same length as "base\n"
os.utime('a.txt', ns=(st.st_atime_ns, st.st_mtime_ns))    # mtime restored
PY
check "same-length edit, mtime restored: caught" '[ -z "$(firelive)" ] && [ "$(runs)" -eq 2 ] && grep -q "bass" a.txt'
setcfg '{"run": "sh check.sh # v2", "watch": ".txt", "skip": "scripts"}'
check "changed command: runs again"           '[ -z "$(firelive)" ] && [ "$(runs)" -eq 3 ]'
rm a.txt
check "deleted on disk: runs once"            '[ -z "$(firelive)" ] && [ "$(runs)" -eq 4 ]'
check "deleted but still in the index: no rerun" '[ -z "$(firelive)" ] && [ "$(runs)" -eq 4 ]'
echo base > a.txt
echo BROKEN > g.txt
OUT="$(firev)"
check "changed and failing: asks"             'echo "$OUT" | grep -q "\"ask\""'
check "names the command that failed"         'echo "$OUT" | grep -q "sh check.sh # v2 failed"'
echo fine > g.txt
check "fixed: runs again, passes, silent"     '[ -z "$(firelive)" ] && grep -q "g.txt" "$VM"'
check "manifest dir is gitignored"            'git check-ignore -q "$VM"'
echo BROKEN > g.txt
bash "$V" --run >/dev/null 2>&1; RC=$?
check "--run reports a failure"               '[ $RC -ne 0 ]'
echo fine > g.txt
check "--run records a pass"                  'bash "$V" --run 2>&1 | grep -q "recorded"'
echo "--- git after Claude asked on the same tree: no second run"
echo BROKEN > g.txt; : > runs.log; : > "$LOG"
firelive tv >/dev/null                          # a real fire, left pending, tree T1
git add g.txt
ERR="$(bash .claude/hooks/na/pre-commit 2>&1 >/dev/null)"
check "same tree: quiet, no second run"       '[ -z "$ERR" ] && [ "$(runs)" -eq 1 ]'
check "recorded as proceeded"                 '[ "$(col 5)" = proceeded ]'
echo "--- git after a decline and a fix: verified"
git reset -q g.txt; echo BROKEN > g.txt; : > runs.log; : > "$LOG"
firelive tw >/dev/null                          # pending on the broken tree
echo fine > g.txt                               # the person fixes it instead
git add g.txt
ERR="$(bash .claude/hooks/na/pre-commit 2>&1 >/dev/null)"
check "different tree: the check runs"        '[ -z "$ERR" ] && [ "$(runs)" -eq 1 ]'
check "the declined fire stays a decline"     '[ "$(col 5)" != proceeded ]'
git reset -q g.txt; : > "$LOG"
echo "--- a dead hook says so, and never blocks git"
setcfg '{"run": "", "watch": ".txt"}'
check "misconfigured: visible systemMessage"  'firev | grep -q "systemMessage.*verify.run"'
ERR="$(NA_EVENT=git bash "$V" 2>&1 >/dev/null </dev/null)"; RC=$?
check "misconfigured under git: stderr, exit 0" '[ $RC -eq 0 ] && echo "$ERR" | grep -q "verify.run"'
setcfg del
check "unconfigured: visible systemMessage"   'firev | grep -q "systemMessage.*no verify block"'
setcfg '{"run": "sh check.sh", "watch": ".txt", "skip": "scripts"}'
"$PYBIN" - <<'PY'
import json, io
p = '.claude/never-again/state.json'
st = json.load(io.open(p, encoding='utf-8')); st['lessons']['L002']['mode'] = 'retired'
json.dump(st, io.open(p, 'w', encoding='utf-8'), indent=2)
PY
echo BROKEN > g.txt; : > runs.log
check "retired: silent and the command never runs" '[ -z "$(firev)" ] && [ "$(runs)" -eq 0 ]'
echo fine > g.txt
"$PYBIN" $NA retire L002 >/dev/null 2>&1
check "retire removes the manifest"           '[ ! -f "$VM" ] && [ ! -f "$V" ]'
rm -f g.txt check.sh runs.log; rm -rf vendor nested scripts
"$PYBIN" - <<'PY'
import io
p = '.gitignore'; s = io.open(p, encoding='utf-8').read().replace('runs.log\nvendor/\n', '')
io.open(p, 'w', encoding='utf-8', newline='\n').write(s)
PY
git add -A >/dev/null 2>&1; git commit -qm "teardown" >/dev/null 2>&1

echo
echo "=== notes that predate the tool are found, not edited ==="
printf '# Notes\n\nAlways run the tests before pushing.\nNever hardcode the API key.\n' > NOTES.md
mkdir -p .cursor/rules && printf 'Prefer named exports.\n' > .cursor/rules/style.mdc
printf '\n## House rules\nUse two spaces.\nRun lint before commit.\n' >> CLAUDE.md
OUTI="$("$PYBIN" $NA import)"
check "lists NOTES.md with a count"        'echo "$OUTI" | grep -q "NOTES.md .*2 line(s)   not imported"'
check "lists the editor rules file"        'echo "$OUTI" | grep -q "cursor/rules/style.mdc"'
check "lists CLAUDE.md minus our block"    'echo "$OUTI" | grep -qE "CLAUDE.md .* [1-4] line\(s\)"'   # the block alone would add five
check "does not list the managed root LESSONS.md" '! echo "$OUTI" | grep -q "^  LESSONS.md"'
check "docs/LESSONS.md is a candidate"     'echo "$OUTI" | grep -q "docs/LESSONS.md"'
"$PYBIN" $NA import --mark NOTES.md --filed 2 >/dev/null
check "marked as imported"                 '"$PYBIN" $NA import | grep -q "NOTES.md .*imported"'
"$PYBIN" $NA import --mark CLAUDE.md --filed 1 >/dev/null
check "CLAUDE.md mark matches the listing" '"$PYBIN" $NA import | grep -q "CLAUDE.md .* imported"'
bash "$SRC/install.sh" . >/dev/null 2>&1
check "reinstall does not unmark CLAUDE.md" '"$PYBIN" $NA import | grep -q "CLAUDE.md .* imported"'
check "source file untouched"              '[ "$(grep -c . NOTES.md)" -eq 3 ]'
echo "Third note." >> NOTES.md
check "changed since import is noticed"    '"$PYBIN" $NA import | grep -q "NOTES.md .*changed since import"'
OUTI2="$(bash "$SRC/install.sh" . 2>&1)"
check "installer points at the notes"      'echo "$OUTI2" | grep -q "import the existing notes"'
rm -rf NOTES.md .cursor
"$PYBIN" - <<'PY'
import io
p = 'CLAUDE.md'; s = io.open(p, encoding='utf-8').read().replace('\n## House rules\nUse two spaces.\nRun lint before commit.\n', '')
io.open(p, 'w', encoding='utf-8', newline='\n').write(s)
PY

echo
echo "=== CLAUDE.md.bak stays out of git ==="
check "backup is gitignored"               'git check-ignore -q CLAUDE.md.bak'

echo
echo "=== an old stub is upgraded on re-run ==="
printf '#!/bin/sh\n# never-again pre-commit stub (managed by install.sh; uninstall removes it)\nexec "$(git rev-parse --show-toplevel)/.claude/hooks/na/pre-commit" "$@"\n' > .git/hooks/pre-commit
OUT10="$(bash "$SRC/install.sh" . 2>&1)"
check "install says it upgraded the stub"  'echo "$OUT10" | grep -q "stub upgraded"'
check "stub now guards a missing runner"   'grep -q "is missing" .git/hooks/pre-commit'
printf '\nnpm run lint\n' >> .git/hooks/pre-commit
OUT10b="$(bash "$SRC/install.sh" . 2>&1)"
check "a stub edited by hand is left alone" 'echo "$OUT10b" | grep -q "edited by hand" && grep -q "npm run lint" .git/hooks/pre-commit'
"$PYBIN" - <<'PY'
import io
p = '.git/hooks/pre-commit'; s = io.open(p, encoding='utf-8').read().replace('\nnpm run lint\n', '')
io.open(p, 'w', encoding='utf-8', newline='\n').write(s)
PY

echo
echo "=== a hand-deleted .claude/ does not break commits ==="
mv .claude .claude.off
echo x > e.txt; git add e.txt
ERR="$(git commit -qm x 2>&1)"; RC=$?
check "stub exits 0 without its runner"    '[ $RC -eq 0 ]'
check "and says the runner is missing"     'echo "$ERR" | grep -q "pre-commit is missing"'
mv .claude.off .claude

echo
echo "=== a repo that ignores .claude/ is told ==="
printf '.claude/\n' >> .gitignore
OUT7="$(bash "$SRC/install.sh" . 2>&1)"
check "hooks tracked: says new ones get dropped" 'echo "$OUT7" | grep -q "new ones will be dropped"'
git rm -r -q --cached .claude >/dev/null 2>&1
OUT7="$(bash "$SRC/install.sh" . 2>&1)"
check "hooks untracked: warns they stay local" 'echo "$OUT7" | grep -q "NOT shared through git"'
check "says to replace the .claude/ line"  'echo "$OUT7" | grep -q "replace the .claude/ line"'
check "local-only block still written"     'grep -q "CLAUDE.md.bak" .gitignore'
"$PYBIN" - <<'PY'
import io, subprocess
p = '.gitignore'; s = io.open(p, encoding='utf-8').read()
advice = subprocess.run(['python', '.claude/never-again/na', '_gitignore', '--advice'],
                        capture_output=True, text=True).stdout
io.open(p, 'w', encoding='utf-8', newline='\n').write(s.replace('.claude/\n', advice))
PY
check "applying the advice really un-ignores the hooks" '! git check-ignore -q .claude/hooks/na/L000.sh'
check "and keeps the local files ignored"  'git check-ignore -q .claude/never-again/fires.log'
check "and shares the hook registrations"  '! git check-ignore -q .claude/settings.json'
"$PYBIN" - <<'PY'
import io, subprocess
p = '.gitignore'; s = io.open(p, encoding='utf-8').read()
advice = subprocess.run(['python', '.claude/never-again/na', '_gitignore', '--advice'],
                        capture_output=True, text=True).stdout
io.open(p, 'w', encoding='utf-8', newline='\n').write(s.replace(advice, '.claude/\n'))
PY
"$PYBIN" - <<'PY'
import io
p = '.gitignore'; s = io.open(p, encoding='utf-8').read().replace('.claude/\n', '')
io.open(p, 'w', encoding='utf-8', newline='\n').write(s)
PY
git add .claude >/dev/null 2>&1

echo
echo "=== an old gitignore block is upgraded wholesale ==="
"$PYBIN" - <<'PY'
import io
p = '.gitignore'; s = io.open(p, encoding='utf-8').read()
s = s[:s.index("# never-again (local only)")].rstrip("\n")
s += "\n\n# never-again (local only)\n.claude/never-again/fires.log\nCLAUDE.md.bak\n"
io.open(p, 'w', encoding='utf-8', newline='\n').write(s)
PY
OUT11="$(bash "$SRC/install.sh" . 2>&1)"
check "install says it upgraded the block"  'echo "$OUT11" | grep -q "brought up to date"'
check "verified/ now ignored"               'grep -q "never-again/verified/" .gitignore'
check "block appears once"                  '[ "$(grep -c "never-again (local only)" .gitignore)" -eq 1 ]'
check "second run is quiet"                 '! bash "$SRC/install.sh" . 2>&1 | grep -q "brought up to date"'
echo "--- bytes and line endings survive"
"$PYBIN" - <<'PY'
import io
p = '.gitignore'; raw = io.open(p, 'rb').read()
raw = raw[:raw.index(b"# never-again (local only)")].rstrip(b"\n").replace(b"\n", b"\r\n")
raw = b"# caf\xe9 (cp1252 comment)\r\n" + raw + b"\r\n\r\n# never-again (local only)\r\n.claude/never-again/fires.log\r\n"
io.open(p, 'wb').write(raw)
PY
OUT12="$(bash "$SRC/install.sh" . 2>&1)"
check "non-UTF-8 gitignore: upgraded, not crashed" 'echo "$OUT12" | grep -q "brought up to date"'
check "the cp1252 byte survived"            '"$PYBIN" -c "import io,sys; sys.exit(0 if b\"caf\\xe9\" in io.open(\".gitignore\",\"rb\").read() else 1)"'
check "CRLF endings kept"                   '"$PYBIN" -c "import io,sys; r=io.open(\".gitignore\",\"rb\").read(); sys.exit(0 if b\"\\r\\n\" in r and b\"\\n\" not in r.replace(b\"\\r\\n\", b\"\") else 1)"'
"$PYBIN" - <<'PY'
import io
p = '.gitignore'; raw = io.open(p, 'rb').read().replace(b"\r\n", b"\n")
raw = raw.replace(b"# caf\xe9 (cp1252 comment)\n", b"")
io.open(p, 'wb').write(raw)
PY

echo
echo "=== a static host is told ==="
echo '{}' > vercel.json
OUT8="$(bash "$SRC/install.sh" . 2>&1)"
check "vercel: warns about /LESSONS.md"    'echo "$OUT8" | grep -q "/LESSONS.md" && echo "$OUT8" | grep -q "public URLs"'
printf '.claude\nLESSONS.md\nCLAUDE.md\n' > .vercelignore
OUT9="$(bash "$SRC/install.sh" . 2>&1)"
check "vercel: quiet once ignored"         '! echo "$OUT9" | grep -q "serve /LESSONS.md"'
rm -f vercel.json .vercelignore

echo
echo "  ---------------------------------"
echo "  $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
