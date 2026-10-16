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
# No pipefail: `producer | grep -q` is everywhere here, grep closes the pipe
# on the first match, and pipefail would turn the producer's broken pipe into
# a failed check. It did, on macOS.
set -u

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMPDIR_ROOT="${TMPDIR:-/tmp}"
T="${1:-$TMPDIR_ROOT/na-hooks-test}"

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
# In-place sed that works on both GNU and BSD sed (macOS needs a suffix).
sedi(){ local e="$1"; shift; local f; for f in "$@"; do sed -i.bak "$e" "$f" && rm -f "$f.bak"; done; }

# Never run inside the source checkout, or anywhere we did not just create. A
# failed cd once left this script committing fixtures into the tool repo.
case "$T" in "$SRC"|"$SRC"/*) echo "refusing to run inside $SRC"; exit 1 ;; esac
rm -rf "$T" && mkdir -p "$T" && cd "$T" || { echo "cannot create $T"; exit 1; }
[ "$(pwd -P)" != "$(cd "$SRC" && pwd -P)" ] || { echo "refusing to run inside $SRC"; exit 1; }
# The project root as Python sees it: a native path on Windows (Git Bash's
# /tmp means nothing to a Windows Python), the real path elsewhere.
T="$(pwd -W 2>/dev/null || pwd -P)"
git init -q .
git config user.email test@example.com
git config user.name test
git config commit.gpgsign false
echo base > a.txt
git add a.txt && git commit -qm init

export CLAUDE_PROJECT_DIR="$T"
NA=".claude/never-again/na"
LOG=".claude/never-again/fires.log"
CWD="$(pwd -W 2>/dev/null || pwd -P)"
HOOK=".claude/hooks/na/L001.sh"

# The hook under test is the template itself, with a check that flags any
# changed .txt file containing the marker word. Run through bash explicitly
# with a JSON payload, the way Claude Code runs it.
fire() { printf '{"tool_input":{"command":%s}%s}' "$("$PYBIN" -c 'import json,sys;print(json.dumps(sys.argv[1]))' "$1")" "${2:+,\"tool_use_id\":\"$2\"}" | bash "$HOOK"; }
after() { printf '{"tool_input":{"command":"git commit -m x"},"tool_use_id":"%s"}' "${1:-}" | bash .claude/hooks/na/_after.sh; }
pay() {  # pay AGENT CMD -> that agent's PreToolUse payload
  local c; c="$("$PYBIN" -c 'import json,sys;print(json.dumps(sys.argv[1]))' "$2")"
  case "$1" in
    claude)      printf '{"tool_name":"Bash","tool_input":{"command":%s},"tool_use_id":"tu9","cwd":"%s"}' "$c" "$CWD" ;;
    codex)       printf '{"tool_name":"Bash","tool_input":{"command":%s},"turn_id":"t9","cwd":"%s"}' "$c" "$CWD" ;;
    gemini)      printf '{"tool_name":"run_shell_command","tool_input":{"command":%s},"cwd":"%s"}' "$c" "$CWD" ;;
    copilot)     printf '{"toolName":"bash","toolArgs":{"command":%s},"cwd":"%s"}' "$c" "$CWD" ;;
    antigravity) printf '{"toolCall":{"name":"run_command","args":{"CommandLine":%s,"Cwd":"%s"}},"conversationId":"c9"}' "$c" "$CWD" ;;
  esac
}
dispatch() { printf '{"tool_input":{"command":%s}%s}' "$("$PYBIN" -c 'import json,sys;print(json.dumps(sys.argv[1]))' "$1")" "${2:+,\"tool_use_id\":\"$2\"}" | bash .claude/hooks/na/dispatch; }
logn() { if [ -f "$LOG" ]; then grep -c . "$LOG" || true; else echo 0; fi; }   # grep -c prints 0 and exits 1 on an empty file
col() { awk -F'\t' -v n="$1" 'END{print $n}' "$LOG"; }    # last line, column n

echo "=== install ==="
bash "$SRC/install.sh" . >/dev/null 2>&1 || { echo "install failed"; exit 1; }
check "library installed"          '[ -f .claude/hooks/na/na-lib.sh ]'
check "resolver installed"         '[ -x .claude/hooks/na/_after.sh ]'
check "git runner installed"       '[ -x .claude/hooks/na/pre-commit ]'
check "git stub installed"         'grep -q never-again .git/hooks/pre-commit'
check "merge stub installed"       'grep -q never-again .git/hooks/pre-merge-commit'
check "commit-msg stub installed"  'grep -q "hooks/na/commit-msg" .git/hooks/commit-msg'
check "capture check installed"    '[ -x .claude/hooks/na/_capture.sh ] && [ -x .claude/hooks/na/commit-msg ]'
check "na --version answers"       '"$PYBIN" $NA --version | grep -q "never-again 1\."'
check "na --help answers"          '"$PYBIN" $NA --help | grep -q "na sort"'
check "resolver registered"        'grep -q _after.sh .claude/settings.json'
check "no if filter on our entries" '! grep -q "\"if\"" .claude/settings.json'
check "dispatcher registered"      'grep -q "/na/dispatch" .claude/settings.json'
check "dispatcher installed"       '[ -x .claude/hooks/na/dispatch ]'

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
echo "=== a clone gets its hooks registered by the installer ==="
"$PYBIN" - <<'PY'
import json, io
p = '.claude/settings.json'
d = json.load(io.open(p, encoding='utf-8'))
for g in d['hooks']['PreToolUse']:
    g['hooks'] = [h for h in g['hooks'] if '/na/L001.sh' not in h['command']]
json.dump(d, io.open(p, 'w', encoding='utf-8'), indent=2)
PY
check "L001 per-hook entry removed for the test" '! grep -q "L001.sh" .claude/settings.json'
"$PYBIN" - <<'PY'
import json, io
p = '.claude/settings.json'
d = json.load(io.open(p, encoding='utf-8'))
d['hooks']['PreToolUse'].append({"matcher": "Bash", "hooks": [
    {"type": "command", "if": "Bash(git commit *)", "command": '"$CLAUDE_PROJECT_DIR"/.claude/hooks/na/L001.sh'}]})
json.dump(d, io.open(p, 'w', encoding='utf-8'), indent=2)
PY
OUTR="$(bash "$SRC/install.sh" . 2>&1)"
check "installer drops a per-hook entry"   'echo "$OUTR" | grep -q "dropped 1 per-hook" && ! grep -q "L001.sh" .claude/settings.json'
check "dispatcher entry registered once"   '[ "$(grep -c "/na/dispatch" .claude/settings.json)" -eq 1 ]'
OUTR2="$(bash "$SRC/install.sh" . 2>&1)"
check "second run reports nothing to do"   'echo "$OUTR2" | grep -q "already registered"'
"$PYBIN" - <<'PY'
import json, io
p = '.claude/settings.json'
d = json.load(io.open(p, encoding='utf-8'))
for ev in d['hooks'].values():
    for g in ev:
        for h in g['hooks']:
            if 'hooks/na/' in h['command']:
                h['if'] = 'Bash(git commit *)'
json.dump(d, io.open(p, 'w', encoding='utf-8'), indent=2)
PY
OUTR3="$(bash "$SRC/install.sh" . 2>&1)"
check "an old if filter is dropped in place"  'echo "$OUTR3" | grep -q "dropped the .if. filter from 3" && ! grep -q "\"if\"" .claude/settings.json'
echo "$OUTR2" | grep -q "already registered" || echo "$OUTR2" | sed 's/^/      | /' | head -30

echo
echo "=== the dispatcher runs the index, not the settings ==="
check "index lists L001 in warn"          '"$PYBIN" $NA _index | grep -q "^L001	warn	commit	-$"'
check "na index is readable"              '"$PYBIN" $NA index | grep -q "L001   warn   commit"'
echo TODO-BLOCK > d0.txt
OUTD="$(NA_DRY_RUN=1 dispatch "git commit -m x")"
check "dispatch asks through the index"   'echo "$OUTD" | grep -q "\"ask\"" && echo "$OUTD" | grep -q "d0.txt"'
check "dispatch: not a commit, silent"    '[ -z "$(NA_DRY_RUN=1 dispatch "ls")" ]'
check "chained commit reaches the hook"   'NA_DRY_RUN=1 dispatch "git add . && git commit -m x" | grep -q "\"ask\""'
check "a byte-order mark is ignored"      'printf "\357\273\277{\"tool_input\":{\"command\":\"git commit -m x\"}}" | NA_DRY_RUN=1 bash .claude/hooks/na/dispatch | grep -q "\"ask\""'
# A fake interpreter that leaves a mark when started. The probe runs
# NA_PYTHON first, so a mark means an interpreter was looked for at all.
printf '#!/bin/sh\ntouch "%s/na-started"; exit 1\n' "$T" > "$T/fakepy"; chmod +x "$T/fakepy"
rm -f "$T/na-started"
printf '{"tool_input":{"command":"ls -la"}}' | NA_PYTHON="$T/fakepy" bash .claude/hooks/na/dispatch >/dev/null 2>&1
check "no commit in the payload: no interpreter" '[ ! -f "$T/na-started" ]'
printf '{"tool_input":{"command":"ls -la"}}' | NA_PYTHON="$T/fakepy" bash .claude/hooks/na/_after.sh >/dev/null 2>&1
check "after: no commit, no interpreter"  '[ ! -f "$T/na-started" ]'
for a in codex gemini copilot antigravity; do
  pay "$a" "ls -la" | NA_PYTHON="$T/fakepy" bash .claude/hooks/na/dispatch --agent "$a" >/dev/null 2>&1
done
check "same for every agent"              '[ ! -f "$T/na-started" ]'
printf '{"tool_input":{"command":"git commit -m x"}}' | NA_PYTHON="$T/fakepy" bash .claude/hooks/na/dispatch >/dev/null 2>&1
check "a commit does start one"           '[ -f "$T/na-started" ]'
rm -f "$T/na-started" "$T/fakepy"
sedi 's/^WATCH=""/WATCH=".css"/' "$HOOK"
check "WATCH: no .css changed, hook skipped" '[ -z "$(NA_DRY_RUN=1 dispatch "git commit -m x")" ]'
echo x > e.css
check "WATCH: a .css changed, hook runs"  'NA_DRY_RUN=1 dispatch "git commit -m x" | grep -q "\"ask\""'
rm -f e.css d0.txt; sedi 's/^WATCH=".css"/WATCH=""/' "$HOOK"
cp "$HOOK" .claude/hooks/na/L009.sh; sedi 's/^ID="L001"/ID="L009"/; s/^RULE=.*/RULE="second opinion"/' .claude/hooks/na/L009.sh
"$PYBIN" - <<'PY'
import json, io
p = '.claude/never-again/state.json'
st = json.load(io.open(p, encoding='utf-8'))
st['lessons']['L009'] = {"form": "hook", "mode": "block", "hook": ".claude/hooks/na/L009.sh"}
json.dump(st, io.open(p, 'w', encoding='utf-8'), indent=2)
PY
echo TODO-BLOCK > d1.txt
OUTD="$(NA_DRY_RUN=1 dispatch "git commit -m x")"
check "two hooks, one decision: deny wins" 'echo "$OUTD" | grep -q "\"deny\"" && [ "$(echo "$OUTD" | grep -c .)" -eq 1 ]'
check "both reasons joined"               'echo "$OUTD" | grep -q "second opinion" && echo "$OUTD" | grep -q "TODO-BLOCK"'
git add d1.txt
ERR="$(bash .claude/hooks/na/pre-commit 2>&1 >/dev/null)"; RCD=$?
check "git runner goes through the dispatcher" '[ $RCD -ne 0 ] && echo "$ERR" | grep -q "L009 blocked"'
git reset -q d1.txt; rm -f d1.txt .claude/hooks/na/L009.sh
"$PYBIN" - <<'PY'
import json, io
p = '.claude/never-again/state.json'
st = json.load(io.open(p, encoding='utf-8')); del st['lessons']['L009']
json.dump(st, io.open(p, 'w', encoding='utf-8'), indent=2)
PY
: > "$LOG"

echo
echo "=== decides from the command, not the substring ==="
check "clean tree: silent"                '[ -z "$(fire "git commit -m x")" ]'
echo TODO-BLOCK > b.txt
check "unstaged change: asks"             'fire "git commit -m x" | grep -q "\"ask\""'
check "a warn also carries a systemMessage" 'NA_DRY_RUN=1 fire "git commit -m x" | grep -q "systemMessage.*warn mode"'
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
# A warn under git exits 0, and the dispatcher once took that as "clean": the
# first real catch in the field was a "clean" line in calls.log.
check "git warn fire is a fired call in calls.log" '[ "$(awk -F"\t" "END{print \$4}" .claude/never-again/calls.log)" = fired ]'
echo "--- promotion rights"
git remote add origin https://example.invalid/repo.git 2>/dev/null
"$PYBIN" - <<'PY'
import json, io
p = '.claude/never-again/state.json'
st = json.load(io.open(p, encoding='utf-8')); st['promotion'] = 'pull-request'
json.dump(st, io.open(p, 'w', encoding='utf-8'), indent=2)
PY
OUTP="$("$PYBIN" $NA promote L001 2>&1)"; RCP=$?
check "pull-request: refused on the default branch" '[ $RCP -ne 0 ] && echo "$OUTP" | grep -q "pull request"'
git checkout -q -b promote-l001
check "pull-request: allowed on a branch"  '"$PYBIN" $NA promote L001 | grep -q "team-wide"'
"$PYBIN" $NA demote L001 >/dev/null; git checkout -q main 2>/dev/null || git checkout -q master
"$PYBIN" - <<'PY'
import json, io
p = '.claude/never-again/state.json'
st = json.load(io.open(p, encoding='utf-8')); st['promotion'] = ['someone.else@example.com']
json.dump(st, io.open(p, 'w', encoding='utf-8'), indent=2)
PY
check "named list: refused for others"     '! "$PYBIN" $NA promote L001 >/dev/null 2>&1'
"$PYBIN" - <<'PY'
import json, io
p = '.claude/never-again/state.json'
st = json.load(io.open(p, encoding='utf-8')); st['promotion'] = ['test@example.com']
json.dump(st, io.open(p, 'w', encoding='utf-8'), indent=2)
PY
check "named list: allowed for a listed identity" '"$PYBIN" $NA promote L001 | grep -q "now block"'
"$PYBIN" $NA demote L001 >/dev/null
"$PYBIN" - <<'PY'
import json, io
p = '.claude/never-again/state.json'
st = json.load(io.open(p, encoding='utf-8')); st['promotion'] = 'anyone'
json.dump(st, io.open(p, 'w', encoding='utf-8'), indent=2)
PY
git remote remove origin
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
echo "=== a sweep asks the check about the whole tree ==="
# c.txt carries the marker and is committed: no commit will ever ask about it
# again, so only a sweep can find it. A sweep records nothing.
N0="$(logn)"
OUTS="$("$PYBIN" $NA sweep L001 2>&1)"; RC=$?
check "sweep finds the committed copy"     '[ $RC -ne 0 ] && echo "$OUTS" | grep -q "L001 in the tree" && echo "$OUTS" | grep -q "c.txt"'
check "sweep is not a fire"                '[ "$(logn)" -eq "$N0" ]'
check "NA_ALL by hand does the same"       'NA_ALL=1 bash "$HOOK" 2>&1 </dev/null | grep -q "L001 in the tree.*c.txt"'
check "sweep refuses a rule line"          '! "$PYBIN" $NA sweep L999 >/dev/null 2>&1'
echo clean > b.txt; echo clean > c.txt; git add b.txt c.txt; git commit -qm x 2>/dev/null
check "clean tree: sweep says so, exit 0"  '"$PYBIN" $NA sweep L001 2>&1 | grep -q "nothing in the tree"'

echo
echo "=== the report is counted from the same files ==="
"$PYBIN" $NA report > report.md 2>&1; RC=$?
check "report renders"                     '[ $RC -eq 0 ] && grep -q "^# never-again report" report.md'
check "report counts the fires it can see" 'grep -q "| Hook fires | $(logn) |" report.md'
check "report lists the hook with its rule" 'grep -q "^| L001 | warn |" report.md'
check "report says who called"             'grep -q "git pre-commit |" report.md'
check "report names the honest column"     'grep -q "Warned past" report.md'
rm -f report.md

echo
echo "=== a fix committed with no lesson is asked about ==="
# The check reads the message: from the command under an agent, from the
# file under git's commit-msg hook. It wants a lesson file in the commit,
# or an `na none` since the last commit. Nothing else satisfies it.
# The install's own files must be in HEAD first, or every commit from here
# would look like it carries a lesson.
git add -A >/dev/null 2>&1; git commit -qm "install files" >/dev/null 2>&1
: > "$LOG"
cap() { NA_DRY_RUN=1 dispatch "$1"; }
# Outside the repo: a file inside it would change the tree between the
# agent's fire and git's second look, and git would ask twice.
CMSG="$TMPDIR_ROOT/na-capture-msg.txt"
gitcap() { printf '%s\n' "$1" > "$CMSG"; NA_DRY_RUN="${2-1}" bash .claude/hooks/na/commit-msg "$CMSG" 2>&1 >/dev/null; }
echo plain > cap.txt
check "clean tree, ordinary message: silent"  '[ -z "$(cap "git commit -m \"add the footer\"")" ]'
check "a fix with no lesson: asks"            'cap "git add cap.txt && git commit -m \"fix the footer\"" | grep -q "capture asks"'
check "the reason names the skill and na none" 'cap "git commit -m \"fix the footer\"" | grep -q "never-again skill" && cap "git commit -m \"fix the footer\"" | grep -q "na none"'
check "conventional fix: asks"                'cap "git commit -m \"fix(nav): weight\"" | grep -q "\"ask\""'
check "revert: asks"                          'cap "git commit -m \"Revert the footer change\"" | grep -q "\"ask\""'
check "-am: asks"                             'cap "git commit -am \"bug in the footer\"" | grep -q "\"ask\""'
check "a heredoc message: asks"               'cap "git commit -m \"\$(cat <<'"'"'EOF'"'"'
fix the footer

Co-Authored-By: x
EOF
)\"" | grep -q "\"ask\""'
check "-m with no space: asks"                'cap "git commit -m\"fix the footer\"" | grep -q "\"ask\""'
CMDQ="git commit -m 'it'\"'\"'s fixed now'"
check "a shell-joined quote: asks"            'cap "$CMDQ" | grep -q "\"ask\""'
check "--amend: silent, it was asked already" '[ -z "$(cap "git commit --amend -m \"fix the footer\"")" ]'
check "a typo fix: silent"                    '[ -z "$(cap "git commit -m \"fix typo in footer\"")" ]'
check "fix in a branch name after the commit: silent" '[ -z "$(cap "git commit -m \"add the footer\" && git push origin fix/footer")" ]'
check "fix in a path before the commit: silent" '[ -z "$(cap "git add fix.js && git commit -m \"add the footer\"")" ]'
check "no -m (editor): silent, git decides"   '[ -z "$(cap "git commit")" ]'
check "not a commit: silent"                  '[ -z "$(cap "echo fix the footer")" ]'
mkdir -p .claude/never-again/archive && echo story > .claude/never-again/archive/L050.md
check "an archive entry in the commit: silent" '[ -z "$(cap "git add -A && git commit -m \"fix the footer\"")" ]'
rm -f .claude/never-again/archive/L050.md
printf -- '- [web] Set the weight — when: nav (L050)\n' >> LESSONS.md
check "a rule line in the commit: silent"     '[ -z "$(cap "git commit -am \"fix the footer\"")" ]'
git checkout -q LESSONS.md
check "na none marks the next commit"         '"$PYBIN" $NA none "one-off" | grep -q "nothing to learn" && [ -f .claude/never-again/.capture-none ]'
check "after na none: silent"                 '[ -z "$(cap "git commit -m \"fix the footer\"")" ]'
check "the mark is ignored by git"            'git check-ignore -q .claude/never-again/.capture-none'
git add cap.txt && git commit -qm "add cap" 2>/dev/null
check "the mark clears when a commit lands"   'cap "git commit -m \"fix the footer\"" | grep -q "\"ask\""'
check "na none in the same command: silent"   '[ -z "$(cap ".claude/never-again/na none && git commit -m \"fix the footer\"")" ]'
check "dry run wrote nothing"                 '[ "$(logn)" -eq 0 ]'
echo "--- from git, where the message first shows"
echo again > cap.txt; git add cap.txt
check "commit-msg: a fix with no lesson warns on stderr" 'gitcap "fix the footer" | grep -q "capture asks"'
check "commit-msg: ordinary message is silent" '[ -z "$(gitcap "add the footer")" ]'
check "commit-msg: comment lines are not the message" '[ -z "$(gitcap "# fix nothing, this is a comment")" ]'
check "commit-msg: a merge is not asked"      '[ -z "$(gitcap "Merge branch '"'"'fix/footer'"'"' into main")" ]'
check "commit-msg: -v diff below the scissors is not the message" '[ -z "$(gitcap "add the footer
# ------------------------ >8 ------------------------
+// a bug lives here")" ]'
check "pre-commit runner has no message: silent" '[ -z "$(NA_DRY_RUN=1 bash .claude/hooks/na/pre-commit 2>&1)" ]'
gitcap "fix the footer" "" >/dev/null
check "a live git fire is logged as capture"  '[ "$(col 2)" = capture ] && [ "$(col 4)" = git ] && [ "$(col 5)" = proceeded ]'
: > "$LOG"
dispatch "git commit -m \"fix the footer\"" tcap >/dev/null
check "agent fire is pending under its id"    '[ "$(col 2)" = capture ] && [ "$(col 5)" = pending ]'
check "git stays quiet after the agent asked" '[ -z "$(gitcap "fix the footer" "")" ] && [ "$(logn)" -eq 1 ] && [ "$(col 5)" = proceeded ]'
OUTC="$("$PYBIN" $NA)"
check "na counts nudges on their own line"    'echo "$OUTC" | grep -q "capture nudges  1" && echo "$OUTC" | grep -q "hook fires      0"'
"$PYBIN" - <<'PY'
import json, io
p = '.claude/never-again/state.json'
st = json.load(io.open(p, encoding='utf-8')); st['capture'] = 'block'
json.dump(st, io.open(p, 'w', encoding='utf-8'), indent=2)
PY
check "block: agent side denies"              'cap "git commit -m \"fix the footer\"" | grep -q "\"deny\""'
ERR="$(git commit -qm "fix the footer" 2>&1)"; RC=$?
check "block: a real git commit is refused"   '[ $RC -ne 0 ] && echo "$ERR" | grep -q "capture blocked"'
"$PYBIN" - <<'PY'
import json, io
p = '.claude/never-again/state.json'
st = json.load(io.open(p, encoding='utf-8')); st['capture'] = 'off'
json.dump(st, io.open(p, 'w', encoding='utf-8'), indent=2)
PY
check "off: silent everywhere"                '[ -z "$(cap "git commit -m \"fix the footer\"")" ] && [ -z "$(gitcap "fix the footer")" ]'
check "off: na says so"                       '"$PYBIN" $NA | grep -q "capture         off"'
"$PYBIN" - <<'PY'
import json, io
p = '.claude/never-again/state.json'
st = json.load(io.open(p, encoding='utf-8')); del st['capture']
json.dump(st, io.open(p, 'w', encoding='utf-8'), indent=2)
PY
check "no key: warn is the default"           'cap "git commit -m \"fix the footer\"" | grep -q "\"ask\""'
ERR="$(git commit -qm "fix the footer" 2>&1)"; RC=$?
check "warn: a real git commit goes through, with the question" '[ $RC -eq 0 ] && echo "$ERR" | grep -q "capture asks"'
ERR="$(git commit --amend --no-edit 2>&1)"; RC=$?
check "amend from git: not asked again"       '[ $RC -eq 0 ] && ! echo "$ERR" | grep -q "capture asks"'
rm -f "$CMSG"; : > "$LOG"

echo
echo "=== the failed call is the witness ==="
# Claude Code reports a failed tool call (PostToolUseFailure) and a call
# that ran (PostToolUse). The after-tool hook keeps failures.log from
# them; the capture check asks from it. Every property here is a claim
# in the README.
FL=".claude/never-again/failures.log"; FOPEN=".claude/never-again/.failures-open"
j() { "$PYBIN" -c 'import json,sys;print(json.dumps(sys.argv[1]))' "$1"; }
failed() { printf '{"hook_event_name":"PostToolUseFailure","tool_name":"Bash","tool_input":{"command":%s},"error":%s,"tool_use_id":"%s","cwd":"%s"}' "$(j "$1")" "$(j "$2")" "${3:-f1}" "$CWD" | bash .claude/hooks/na/_after.sh; }
passed() { printf '{"hook_event_name":"PostToolUse","tool_name":"Bash","tool_input":{"command":%s},"tool_response":{"stdout":"ok","stderr":""},"tool_use_id":"%s","cwd":"%s"}' "$(j "$1")" "${2:-p1}" "$CWD" | bash .claude/hooks/na/_after.sh; }
fln() { if [ -f "$FL" ]; then grep -c . "$FL" || true; else echo 0; fi; }
fcol() { awk -F'\t' -v n="$1" 'END{print $n}' "$FL"; }
rm -f "$FL" "$FOPEN"
printf '#!/bin/sh\ntouch "%s/na-started"; exit 1\n' "$T" > "$T/fakepy"; chmod +x "$T/fakepy"
rm -f "$T/na-started"
printf '{"hook_event_name":"PostToolUse","tool_input":{"command":"npm test"}}' | NA_PYTHON="$T/fakepy" bash .claude/hooks/na/_after.sh >/dev/null 2>&1
check "a pass with nothing open: no interpreter"   '[ ! -f "$T/na-started" ] && [ ! -f "$FL" ]'
check "a failed test run is written down"         '[ -z "$(failed "npm test" "Exit code 1
Error: expected 2 got 3
    at t.js:4")" ] && [ "$(fln)" -eq 1 ] && [ "$(fcol 2)" = fail ] && [ "$(fcol 6)" = "npm test" ] && [ "$(fcol 7)" = "Error: expected 2 got 3" ]'
check "the open mark is set"                      '[ -f "$FOPEN" ]'
check "grep with no match is not a failure"       'failed "grep -q marker a.txt" "Exit code 1" >/dev/null; [ "$(fln)" -eq 1 ]'
check "git diff --quiet is not a failure"         'failed "git diff --quiet && echo same" "Exit code 1" >/dev/null; [ "$(fln)" -eq 1 ]'
check "a chain with a real command is written"    'failed "cd api && npm run build" "Exit code 2
src/x.ts(4,3): error TS2322" f2 >/dev/null; [ "$(fln)" -eq 2 ] && [ "$(fcol 7)" = "src/x.ts(4,3): error TS2322" ]'
BIGERR="$("$PYBIN" -c 'print("E" * 5000)')"
failed "pytest -q" "$BIGERR" >/dev/null; ERRL="$(fcol 7)"
check "a huge error is cut to one bounded line"   '[ "$(fln)" -eq 3 ] && [ "${#ERRL}" -le 160 ] && [ "${#ERRL}" -gt 100 ]'
check "na failures: still failing"                '"$PYBIN" $NA failures | grep -q "still failing" && "$PYBIN" $NA failures | grep -q "npm test"'
check "an open failure alone: a plain commit is silent" '[ -z "$(cap "git commit -m \"add the footer\"")" ]'
check "a failed commit is not a failure"          'failed "git commit -m x" "hook denied" >/dev/null; [ "$(fln)" -eq 3 ]'
check "dry run writes nothing"                    'NA_DRY_RUN=1 failed "make" "Exit code 2" >/dev/null; [ "$(fln)" -eq 3 ]'
check "same command, tree unchanged: flaky, silent" '[ -z "$(passed "npm test")" ] && [ "$(fcol 2)" = flaky ]'
failed "npm test" "Exit code 1
Error: expected 2 got 3" f3 >/dev/null
echo changed >> cap.txt
OUTP="$(passed "npm test" p3)"
check "same command after the tree changed: fixed" '[ "$(fcol 2)" = fixed ]'
check "the note reaches the model"                'echo "$OUTP" | grep -q additionalContext && echo "$OUTP" | grep -q "npm test" && echo "$OUTP" | grep -q "expected 2 got 3"'
check "the note is valid JSON"                    'echo "$OUTP" | "$PYBIN" -c "import json,sys; json.load(sys.stdin)"'
check "the mark stays while another is open"      '[ -f "$FOPEN" ]'
# Claude Code on Windows sets CLAUDE_PROJECT_DIR with backslashes; the gate
# is one file test on that string and must open for that shape.
case "$(uname -s)" in
  MINGW*|MSYS*|CYGWIN*)
    WINP="$(printf '%s' "$T" | sed 's,/,\\,g')"
    rm -f "$T/na-started"
    printf '{"hook_event_name":"PostToolUse","tool_input":{"command":"ls -z"}}' | CLAUDE_PROJECT_DIR="$WINP" NA_PYTHON="$T/fakepy" bash .claude/hooks/na/_after.sh >/dev/null 2>&1
    check "a backslash project dir reaches the pass path" '[ -f "$T/na-started" ]'
    rm -f "$T/na-started" ;;
  *) ok "a backslash project dir reaches the pass path (a Windows shape; not run here)" ;;
esac
echo more >> cap.txt
passed "cd api && npm run build" p4 >/dev/null; passed "pytest -q" p5 >/dev/null
check "the mark clears once nothing is open"      '[ ! -f "$FOPEN" ]'
check "na failures: fixed, with the error"        '"$PYBIN" $NA failures | grep -q "fixed  (3" && "$PYBIN" $NA failures | grep -q "expected 2 got 3"'
check "na counts fixed, unfiled"                  '"$PYBIN" $NA | grep -q "fixed, unfiled  3"'
check "na review lists them"                      '"$PYBIN" $NA review | grep -q "fixed since the last commit  (3"'
# The question names the most recent fix (pytest here) and counts the rest.
OUTQ="$(cap "git commit -m \"add the footer\"")"
check "capture asks from the record on a plain message" 'echo "$OUTQ" | grep -q "\"ask\"" && echo "$OUTQ" | grep -q "by the record" && echo "$OUTQ" | grep -q "pytest -q" && echo "$OUTQ" | grep -q "and 2 more"'
check "a fix message and the record: both named" 'cap "git commit -m \"fix the footer\"" | grep -q "the record agrees"'
check "git side: commit-msg asks from the record" 'gitcap "add the footer" | grep -q "by the record"'
mkdir -p .claude/never-again/archive && echo story > .claude/never-again/archive/L051.md
check "a lesson in the commit answers it"         '[ -z "$(cap "git add -A && git commit -m \"add the footer\"")" ]'
rm -f .claude/never-again/archive/L051.md
check "na none answers it"                        '"$PYBIN" $NA none "flaky suite" >/dev/null && [ -z "$(cap "git commit -m \"add the footer\"")" ] && [ -z "$(gitcap "add the footer")" ]'
git add cap.txt && git commit -qm "cap again" 2>/dev/null
check "once the commit lands, the record is behind it" '[ -z "$(cap "git commit -m \"add the footer\"")" ] && "$PYBIN" $NA failures | grep -q "nothing since the last commit"'
failed "pytest -q" "Exit code 1
E   assert 1 == 2" f6 >/dev/null
git commit -q --allow-empty -m "empty" 2>/dev/null
check "an open failure survives an unrelated commit" '[ -f "$FOPEN" ] && [ -z "$(passed "ls -la")" ] && [ -f "$FOPEN" ] && "$PYBIN" $NA failures | grep -q "still failing"'
echo later >> cap.txt
OUTP="$(passed "pytest -q" p6)"
check "and its fix after that commit is matched"  'echo "$OUTP" | grep -q "assert 1 == 2" && [ ! -f "$FOPEN" ] && cap "git commit -m \"add the footer\"" | grep -q "by the record"'
check "na none silences the counts too"           '"$PYBIN" $NA none "one-off" >/dev/null && ! "$PYBIN" $NA | grep -q "fixed, unfiled" && ! "$PYBIN" $NA review | grep -q "fixed since" && "$PYBIN" $NA failures | grep -q "answered for the next commit"'
git add cap.txt && git commit -qm "cap later" 2>/dev/null
OLD="$("$PYBIN" -c 'import time; print(time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(time.time() - 90000)))')"
printf '%s\tfail\tdeadbeef00\t-\t-\told-suite\tError: old\t-\n' "$OLD" >> "$FL"; : > "$FOPEN"
check "a failure nothing passed after in a day is forgotten" '[ -z "$(passed "ls -la")" ] && [ ! -f "$FOPEN" ] && ! "$PYBIN" $NA failures | grep -q "old-suite"'
check "a quoted pipe in a quiet command is not a failure" 'failed "grep -q '"'"'a | b'"'"' cap.txt" "Exit code 1" >/dev/null; ! grep -q "grep -q" "$FL"'
check "a heredoc body is not a command"           'failed "cat > x.txt <<'"'"'EOF'"'"'
run: make | tee log
EOF" "Exit code 1" >/dev/null; ! grep -q "tee log" "$FL"'
check "the error line is the error, not the banner" 'failed "npm run check" "Exit code 1
> app@1.0.0 check
> jest
FAIL src/x.test.js
  ● expected 2 got 3" f7 >/dev/null; [ "$(fcol 7)" = "FAIL src/x.test.js" ]'
passed "npm run check" p7 >/dev/null
check "a retry with the tree unchanged closes it"  '[ "$(fcol 2)" = flaky ] && [ ! -f "$FOPEN" ]'
check "the record is ignored by git"              'git check-ignore -q "$FL" && git check-ignore -q "$FOPEN"'
rm -f "$T/na-started"
printf '{"hook_event_name":"PostToolUse","tool_input":{"command":"ls"}}' | NA_PYTHON="$T/fakepy" bash .claude/hooks/na/_after.sh >/dev/null 2>&1
check "with nothing open, ordinary calls are quiet again" '[ ! -f "$T/na-started" ]'
rm -f "$T/fakepy" "$T/na-started" "$FL" "$FOPEN" "$CMSG"; : > "$LOG"

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
echo BROKEN > sweep.txt
OUTS="$("$PYBIN" $NA sweep L002 2>&1)"; RC=$?
check "sweep of a verify hook runs its command"  '[ $RC -ne 0 ] && echo "$OUTS" | grep -q "check failed"'
rm -f sweep.txt
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
# Rules folders of other editors, and Claude Code's memory for this project
# (outside the repo, under a slug of the directory Claude was started in,
# which may be a parent of the repo). Nothing already written may be lost.
mkdir -p .github/instructions && printf 'Prefer small PRs.\n' > .github/instructions/pr.instructions.md
FAKEHOME="$TMPDIR_ROOT/na-home"; rm -rf "$FAKEHOME"
SLUG="$("$PYBIN" -c 'import re,sys; print(re.sub(r"[:\\/.]", "-", sys.argv[1]))' "$(dirname "$T")")"
mkdir -p "$FAKEHOME/.claude/projects/$SLUG/memory"
printf -- '---\nname: no-force-push\ndescription: x\n---\n\nNever force-push to main.\n' > "$FAKEHOME/.claude/projects/$SLUG/memory/no-force-push.md"
printf -- '- [x](x.md) index only\n' > "$FAKEHOME/.claude/projects/$SLUG/memory/MEMORY.md"
mkdir -p "$FAKEHOME/.claude/projects/other-project/memory" && printf 'Not ours.\n' > "$FAKEHOME/.claude/projects/other-project/memory/n.md"
# A sibling whose slug merely starts with ours (app vs app-docs) is not ours.
REPOSLUG="$("$PYBIN" -c 'import re,sys; print(re.sub(r"[:\\/.]", "-", sys.argv[1]))' "$T")"
mkdir -p "$FAKEHOME/.claude/projects/${REPOSLUG}-docs/memory" && printf 'Sibling notes.\n' > "$FAKEHOME/.claude/projects/${REPOSLUG}-docs/memory/s.md"
OUTM="$(HOME="$FAKEHOME" USERPROFILE="$FAKEHOME" "$PYBIN" $NA import)"
check "an editor's rules folder is a candidate" 'echo "$OUTM" | grep -q "github/instructions/pr.instructions.md"'
check "Claude Code memory for a parent dir is found" 'echo "$OUTM" | grep -q "~/.claude/projects/$SLUG/memory/no-force-push.md .* 1 line(s)"'
check "front matter is not a note"         '! echo "$OUTM" | grep -q "no-force-push.md .* [2-9] line"'
check "the memory index is not a note"     '! echo "$OUTM" | grep -q "MEMORY.md"'
check "another project's memory is not"    '! echo "$OUTM" | grep -q "other-project"'
check "a sibling repo's memory is not"      '! echo "$OUTM" | grep -q "Sibling\|${REPOSLUG}-docs"'
check "na counts the files not imported"   'HOME="$FAKEHOME" USERPROFILE="$FAKEHOME" "$PYBIN" $NA | grep -q "notes  .*not imported yet"'
check "review names them"                  'HOME="$FAKEHOME" USERPROFILE="$FAKEHOME" "$PYBIN" $NA review | grep -q "not imported yet" && HOME="$FAKEHOME" USERPROFILE="$FAKEHOME" "$PYBIN" $NA review | grep -q "no-force-push.md"'
HOME="$FAKEHOME" USERPROFILE="$FAKEHOME" "$PYBIN" $NA import --mark "~/.claude/projects/$SLUG/memory/no-force-push.md" --filed 1 >/dev/null
check "a memory file can be marked"        'HOME="$FAKEHOME" USERPROFILE="$FAKEHOME" "$PYBIN" $NA import | grep -q "no-force-push.md .* imported"'
rm -rf "$FAKEHOME" .github/instructions
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
check "settings.json stays the person's own" 'git check-ignore -q .claude/settings.json'
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
check "vercel: quiet once ignored"         '! echo "$OUT9" | grep -q "public URLs"'
printf '/CLAUDE.md\n/LESSONS.md\n/.claude/\n' > .vercelignore
OUT9="$(bash "$SRC/install.sh" . 2>&1)"
check "vercel: leading slash counts too"   '! echo "$OUT9" | grep -q "public URLs"'
rm -f vercel.json .vercelignore

echo
echo "=== the same hooks under other agents ==="
# Each agent hands the dispatcher its own payload shape and wants its own
# answer shape back. The hook in between is the one from the template.
agent() { pay "$1" "$2" | NA_DRY_RUN="${3-1}" bash .claude/hooks/na/dispatch --agent "$1" 2>/dev/null; }

cp .claude/never-again/hook-template.sh .claude/hooks/na/L021.sh
"$PYBIN" - <<'PY'
import sys, io, json
p = '.claude/hooks/na/L021.sh'
s = io.open(p, encoding="utf-8").read()
s = s.replace('ID="L000"', 'ID="L021"').replace('RULE="one-line rule text"', 'RULE="no TODO-BLOCK"')
s = s.replace('DETAIL=""\n', 'DETAIL=""\nwhile IFS= read -r f; do [ -f "$NA_ROOT/$f" ] || continue; '
              'if grep -q TODO-BLOCK "$NA_ROOT/$f"; then VIOLATION=1; DETAIL="$DETAIL $f"; fi; '
              'done < <(na_changed_files .txt)\n', 1)
io.open(p, "w", encoding="utf-8", newline="\n").write(s)
p = '.claude/never-again/state.json'
st = json.load(io.open(p, encoding='utf-8'))
st['lessons']['L021'] = {"form": "hook", "mode": "warn", "hook": ".claude/hooks/na/L021.sh"}
json.dump(st, io.open(p, 'w', encoding='utf-8'), indent=2)
PY
echo TODO-BLOCK > ag.txt
O="$(agent claude "git commit -m x")"
check "claude: ask + systemMessage"        'echo "$O" | grep -q "\"ask\"" && echo "$O" | grep -q systemMessage'
O="$(agent codex "git commit -m x")"
check "codex warn: allow + additionalContext" 'echo "$O" | grep -q "\"allow\"" && echo "$O" | grep -q additionalContext && ! echo "$O" | grep -q "\"ask\""'
O="$(agent gemini "git commit -m x")"
check "gemini warn: systemMessage only"    'echo "$O" | grep -q systemMessage && ! echo "$O" | grep -q decision'
O="$(agent copilot "git commit -m x")"
check "copilot warn: top-level ask"        'echo "$O" | grep -q "^{\"permissionDecision\": \"ask\""'
O="$(agent antigravity "git commit -m x")"
check "antigravity warn: decision ask"     'echo "$O" | grep -q "\"decision\": \"ask\"" && echo "$O" | grep -q "\"allow_tool\": true"'
check "agent guessed from the shape"       'pay codex "git commit -m x" | NA_DRY_RUN=1 bash .claude/hooks/na/dispatch | grep -q additionalContext'
check "not a commit: silent for every agent" '[ -z "$(agent codex ls)$(agent gemini ls)$(agent copilot ls)$(agent antigravity ls)" ]'
mkdir -p agsub
check "root found from the payload cwd"    '(cd agsub && pay codex "git commit -m x" | NA_DRY_RUN=1 bash ../.claude/hooks/na/dispatch --agent codex | grep -q ag.txt)'
check "root found from Antigravity's Cwd"  '(cd agsub && pay antigravity "git commit -m x" | NA_DRY_RUN=1 bash ../.claude/hooks/na/dispatch --agent antigravity | grep -q ag.txt)'
rmdir agsub
"$PYBIN" - <<'PY'
import json, io
p = '.claude/never-again/state.json'
st = json.load(io.open(p, encoding='utf-8')); st['lessons']['L021']['mode'] = 'block'
json.dump(st, io.open(p, 'w', encoding='utf-8'), indent=2)
PY
check "codex block: deny"                  'agent codex "git commit -m x" | grep -q "\"deny\""'
check "gemini block: decision deny"        'agent gemini "git commit -m x" | grep -q "\"decision\": \"deny\""'
check "copilot block: deny"                'agent copilot "git commit -m x" | grep -q "\"permissionDecision\": \"deny\""'
check "antigravity block: decision deny"   'agent antigravity "git commit -m x" | grep -q "\"decision\": \"deny\""'
"$PYBIN" - <<'PY'
import json, io
p = '.claude/never-again/state.json'
st = json.load(io.open(p, encoding='utf-8')); st['lessons']['L021']['mode'] = 'warn'
json.dump(st, io.open(p, 'w', encoding='utf-8'), indent=2)
PY
: > "$LOG"
agent codex "git commit -m x" "" >/dev/null
check "fire logged with the agent as source" '[ "$(col 4)" = codex ] && [ "$(col 5)" = pending ]'
ccol() { awk -F'\t' -v n="$1" 'END{print $n}' .claude/never-again/calls.log; }
check "the call itself is logged"          '[ "$(ccol 2)" = codex ] && [ "$(ccol 3)" = claude ] && [ "$(ccol 4)" = fired ]'
check "calls.log is ignored"               'git check-ignore -q .claude/never-again/calls.log'
pay codex "ls" | bash .claude/hooks/na/_after.sh --agent codex
check "after a non-commit: still pending"  '[ "$(col 5)" = pending ]'
pay codex "git commit -m x" | bash .claude/hooks/na/_after.sh --agent codex
check "after the commit: proceeded"        '[ "$(col 5)" = proceeded ]'
git add ag.txt; bash .claude/hooks/na/pre-commit >/dev/null 2>&1; git reset -q ag.txt
check "git side logs no agent"             '[ "$(ccol 2)" = - ] && [ "$(ccol 3)" = git ]'
check "a warned git commit is a fired call" '[ "$(ccol 4)" = fired ]'
echo fine > ag.txt; git add ag.txt; bash .claude/hooks/na/pre-commit >/dev/null 2>&1; git reset -q ag.txt
check "a quiet git commit is a clean call"  '[ "$(ccol 4)" = clean ]'
rm -f ag.txt

echo
echo "=== registering with other agents ==="
mkdir -p .codex
printf '{"hooks":{"PreToolUse":[{"matcher":"Bash","hooks":[{"type":"command","command":"echo mine"}]}]}}\n' > .codex/hooks.json
OUTA="$(bash "$SRC/install.sh" --agent gemini,copilot --agent antigravity . 2>&1)"
check "codex found by its folder"          'echo "$OUTA" | grep -q "codex: registered"'
check "codex: own entry kept"              'grep -q "echo mine" .codex/hooks.json && grep -q "never-again/launch" .codex/hooks.json'
check "codex: after-hook registered"       'grep -q "codex --after" .codex/hooks.json'
check "gemini: BeforeTool + AfterTool"     'grep -q BeforeTool .gemini/settings.json && grep -q AfterTool .gemini/settings.json'
check "copilot: own file"                  'grep -q preToolUse .github/hooks/never-again.json && grep -q '"'"'"version": 1'"'"' .github/hooks/never-again.json'
# Antigravity never calls the IDE hook and its git runs in a terminal nobody
# reads, so the release nudge is invisible there: the stop is set once, when
# the agent joins, and a choice made afterwards stands.
check "antigravity joining sets updates: block" 'grep -q "\"updates\": \"block\"" .claude/never-again/state.json && echo "$OUTA" | grep -q "updates    block"'
check "the install records that it set it"   'grep -q "\"updatesSetByInstall\"" .claude/never-again/state.json'
"$PYBIN" - <<'PY'
import json, io
p = '.claude/never-again/state.json'
st = json.load(io.open(p, encoding='utf-8')); st['updates'] = 'check'
json.dump(st, io.open(p, 'w', encoding='utf-8'), indent=2)
PY
OUTA2="$(bash "$SRC/install.sh" . 2>&1)"
check "a re-run keeps the person's choice"   'grep -q "\"updates\": \"check\"" .claude/never-again/state.json && ! echo "$OUTA2" | grep -q "updates    block"'
# A repo that registered Antigravity under an older release has the agent
# but no record: the first installer that knows about the stop sets it.
"$PYBIN" - <<'PY'
import json, io
p = '.claude/never-again/state.json'
st = json.load(io.open(p, encoding='utf-8')); del st['updatesSetByInstall']
json.dump(st, io.open(p, 'w', encoding='utf-8'), indent=2)
PY
OUTA3="$(bash "$SRC/install.sh" . 2>&1)"
check "an older antigravity install is moved to block once" 'grep -q "\"updates\": \"block\"" .claude/never-again/state.json && echo "$OUTA3" | grep -q "updates    block"'
# The entry must work from any directory: Antigravity was seen running it
# from .agents/ itself. Run the exact command from the file, as a shell
# would, from that directory and from a nested one.
entry_cmd() { "$PYBIN" -c 'import json,sys
d = json.load(open(sys.argv[1]))
c = d[sys.argv[2]] if sys.argv[2] in d else d
print(next(h["command"] for g in c[sys.argv[3]] for h in g["hooks"] if "never-again/launch" in h["command"] or "hooks/na/" in h["command"]))' "$@"; }
AGCMD="$(entry_cmd .agents/hooks.json never-again PreToolUse)"
CXCMD="$(entry_cmd .codex/hooks.json hooks PreToolUse)"
check "entries run the launcher, hold no path" 'echo "$AGCMD" | grep -q "never-again/launch" && ! echo "$AGCMD" | grep -q "hooks/na" && ! echo "$AGCMD" | grep -q "\$("'
check "launcher installed"                '[ -x "$HOME/.never-again/launch" ]'
echo TODO-BLOCK > agdir.txt
check "antigravity entry runs from .agents/" '(cd .agents && pay antigravity "git commit -m x" | NA_DRY_RUN=1 eval "$AGCMD" | grep -q agdir.txt)'
check "codex entry runs from a nested dir" '(mkdir -p deep/er && cd deep/er && pay codex "git commit -m x" | NA_DRY_RUN=1 eval "$CXCMD" | grep -q agdir.txt)'
rm -rf agdir.txt deep
check "launcher: no cwd in payload, process cwd" 'echo TODO-BLOCK > lc.txt && printf "{\"tool_input\":{\"command\":\"git commit -m x\"}}" | NA_DRY_RUN=1 bash "$HOME/.never-again/launch" --agent codex | grep -q lc.txt; r=$?; rm -f lc.txt; [ $r -eq 0 ]'
check "launcher: outside a repo, silent"  '[ -z "$(cd "$TMPDIR_ROOT" && printf "{\"tool_input\":{\"command\":\"git commit -m x\"}}" | bash "$HOME/.never-again/launch" --agent codex 2>&1)" ]'
check "entry with no launcher exits 0"    'HOME="$TMPDIR_ROOT/nohome" bash -c "$(echo "$CXCMD" | sed "s/^\"[^\"]*\" //; s/^bash //; s/^-c //" | sed "s/^\"//; s/\"$//")" </dev/null; [ $? -eq 0 ]'
case "$(uname -s)" in
  MINGW*|MSYS*|CYGWIN*)
    check "windows: Git's bash by full path" 'echo "$AGCMD" | grep -q "Git/bin/bash.exe"'
    # The Copilot powershell field, run by PowerShell 5.1 itself: the quoting
    # that broke the fourth Antigravity run.
    PSCMD="$("$PYBIN" -c "import json;print(json.load(open('.github/hooks/never-again.json'))['hooks']['preToolUse'][0]['powershell'])")"
    echo TODO-BLOCK > ps.txt
    OUTPS="$(NA_DRY_RUN=1 powershell -NoProfile -Command "'$(pay copilot "git commit -m x")' | $PSCMD" 2>&1)"
    rm -f ps.txt
    check "powershell 5.1 runs the copilot entry" 'echo "$OUTPS" | grep -q "\"permissionDecision\": \"ask\"" && echo "$OUTPS" | grep -q ps.txt'
    echo "$OUTPS" | grep -q ps.txt || { echo "      | HOME=$HOME  launcher: $(ls -la "$HOME/.never-again/launch" 2>&1)"; echo "      | cmd: $PSCMD"; printf '%s
' "$OUTPS" | head -8 | sed 's/^/      | /'
      echo TODO-BLOCK > ps.txt
      powershell -NoProfile -Command "'$(pay copilot "git commit -m x")' | & 'C:/Program Files/Git/bin/bash.exe' -c 'echo HOME=\$HOME PWD=\$PWD; command -v python python3 py; git --version; bash -x ~/.never-again/launch --agent copilot'" 2>&1 | tail -25 | sed 's/^/      | /'
      rm -f ps.txt; } ;;
esac
check "copilot: bash and powershell forms" 'grep -q "\"bash\": \"bash -c" .github/hooks/never-again.json && grep -q "\"powershell\": \"& " .github/hooks/never-again.json'
"$PYBIN" - <<'PY'
import json, io
p = '.codex/hooks.json'
d = json.load(io.open(p, encoding='utf-8'))
for g in d['hooks']['PreToolUse']:
    for h in g['hooks']:
        if 'never-again/launch --agent codex;' in h['command']:
            h['command'] = 'bash "/old/absolute/.claude/hooks/na/dispatch" --agent codex'
json.dump(d, io.open(p, 'w', encoding='utf-8'), indent=2)
PY
OUTC="$(bash "$SRC/install.sh" . 2>&1)"
check "a stale entry is rewritten"         'echo "$OUTC" | grep -q "codex: registered" && ! grep -q "/old/absolute/" .codex/hooks.json && [ "$(grep -c "agent codex; exit 0" .codex/hooks.json)" -eq 1 ]'
check "agents remembered in state"         '"$PYBIN" -c "import json,sys; a=json.load(open(sys.argv[1]))[\"agents\"]; sys.exit(0 if a==[\"codex\",\"gemini\",\"copilot\",\"antigravity\"] else 1)" .claude/never-again/state.json'
check "AGENTS.md has the block"            'grep -q "BEGIN never-again" AGENTS.md'
check "GEMINI.md has the block"            'grep -q "BEGIN never-again" GEMINI.md'
check "copilot-instructions has the block" 'grep -q "BEGIN never-again" .github/copilot-instructions.md'
check "skill copied for each agent"        '[ -f .agents/skills/never-again/SKILL.md ] && [ -f .gemini/skills/never-again/SKILL.md ] && [ -f .github/skills/never-again/SKILL.md ]'
check "block-only files are not notes"     '! echo "$OUTA" | grep -q "AGENTS.md"'
OUTB="$(bash "$SRC/install.sh" . 2>&1)"
check "re-run keeps the agents"            '[ "$(echo "$OUTB" | grep -c "already registered in")" -eq 4 ]'
check "re-run registers once"              '[ "$(grep -c "agent codex; exit 0" .codex/hooks.json)" -eq 1 ] && [ "$(grep -c "agent gemini; exit 0" .gemini/settings.json)" -eq 1 ]'
check "backups are ignored"                'git check-ignore -q AGENTS.md.bak && git check-ignore -q .github/copilot-instructions.md.bak'
check "unknown agent refused"              '! bash "$SRC/install.sh" --agent cursor . >/dev/null 2>&1'
rm -f .claude/hooks/na/L021.sh
"$PYBIN" - <<'PY'
import json, io
p = '.claude/never-again/state.json'
st = json.load(io.open(p, encoding='utf-8')); del st['lessons']['L021']
json.dump(st, io.open(p, 'w', encoding='utf-8'), indent=2)
PY

echo
echo "=== review: stale by evidence, duplicates by words, grades handed back ==="
cat >> LESSONS.md <<'EOF'
- [tests] Never chain the boot check into the commit command; run it as its own step — when: writing a commit command (L040)
- [tests] Run the boot check as its own step, never chained into the commit command — when: writing a commit command (L041)
- [css] Use font: inherit on form controls so buttons match the page — when: styling forms (L042)
EOF
"$PYBIN" - <<'PY'
import json, io
p = '.claude/never-again/state.json'
st = json.load(io.open(p, encoding='utf-8'))
for lid in ('L040', 'L041', 'L042'):
    st['lessons'][lid] = {"scope": "tests", "form": "rule", "filed": "2020-01-01", "file": "LESSONS.md"}
st['lessons']['L043'] = {"scope": "tests", "form": "hook", "mode": "warn", "filed": "2020-01-01", "file": "LESSONS.md"}
json.dump(st, io.open(p, 'w', encoding='utf-8'), indent=2)
PY
check "dup finds the rules that say the same"  '"$PYBIN" $NA dup "chain the boot check into the commit command" | grep -q L040 && "$PYBIN" $NA dup "chain the boot check into the commit command" | grep -q L041'
check "dup leaves the unrelated rule out"      '! "$PYBIN" $NA dup "chain the boot check into the commit command" | grep -q L042'
check "dup L040 names its twin, not itself"    '"$PYBIN" $NA dup L040 | grep -q L041 && ! "$PYBIN" $NA dup L040 | grep -q L040'
check "dup on different words says nothing"    '[ -z "$("$PYBIN" $NA dup "totally different words about nothing here")" ]'
"$PYBIN" $NA _fired L043 warn claude tu43 >/dev/null
OUTW="$(after tu43)"
# Only additionalContext reaches the model after a tool call; a
# systemMessage goes to the person, and the person is not who grades.
check "after a warned commit: ids handed back"  'echo "$OUTW" | grep -q "L043 warned" && echo "$OUTW" | grep -q "na ok L###" && echo "$OUTW" | grep -q "\"additionalContext\"" && echo "$OUTW" | grep -q "\"hookEventName\":\"PostToolUse\""'
check "the fire is proceeded and ungraded"     '[ "$(col 2)" = L043 ] && [ "$(col 5)" = proceeded ] && [ "$(col 6)" = - ]'
"$PYBIN" $NA _fired L043 warn claude >/dev/null
check "copilot: nothing handed back"           '[ -z "$(pay copilot "git commit -m x" | bash .claude/hooks/na/_after.sh --agent copilot)" ]'
"$PYBIN" $NA _fired L043 warn claude >/dev/null
check "gemini: a systemMessage instead"        'pay gemini "git commit -m x" | bash .claude/hooks/na/_after.sh --agent gemini | grep -q "\"systemMessage\":\"never-again: L043 warned"'
# The same hook runs on PostToolUseFailure: a commit that failed landed
# nothing to grade, so nothing is handed back (the fire is still proceeded:
# the person did go past the warning).
"$PYBIN" $NA _fired L043 warn claude tu-fail >/dev/null
OUTF="$(printf '{"hook_event_name":"PostToolUseFailure","tool_input":{"command":"git commit -m x"},"tool_use_id":"tu-fail"}' | bash .claude/hooks/na/_after.sh)"
check "a failed commit hands nothing back"     '[ -z "$OUTF" ] && [ "$(col 5)" = proceeded ]'
check "a quiet commit hands nothing back"      '[ -z "$(after tu-none)" ]'
OUTS1="$("$PYBIN" $NA stale --commits 1)"
check "stale: old rule lines with no trace"    'echo "$OUTS1" | grep -q "^  L040" && echo "$OUTS1" | grep -q "^  L041" && echo "$OUTS1" | grep -q "^  L042"'
check "stale: a hook with a recent fire is not" '! echo "$OUTS1" | grep -q "^  L043"'
check "stale says a rule line cannot prove itself" 'echo "$OUTS1" | grep -q "no fire can prove a rule line"'
# The message carries an em dash: git prints UTF-8, and a Windows Python
# once read it as cp1252 and crashed the first review on the tool's repo.
git commit -q --allow-empty -m "note on L041 — with a dash" 2>/dev/null
OUTS2="$("$PYBIN" $NA stale --commits 1)"; RCS=$?
check "a mention in a commit is a trace"       '[ $RCS -eq 0 ] && ! echo "$OUTS2" | grep -q "^  L041" && echo "$OUTS2" | grep -q "^  L040"'
"$PYBIN" - <<'PY'
import json, io
p = '.claude/never-again/state.json'
st = json.load(io.open(p, encoding='utf-8'))
st['lessons']['L044'] = {"scope": "tests", "form": "rule", "filed": "2999-01-01", "file": "LESSONS.md"}
json.dump(st, io.open(p, 'w', encoding='utf-8'), indent=2)
PY
check "a lesson younger than the window is not judged" '! "$PYBIN" $NA stale --commits 1 | grep -q "^  L044"'
OUTR="$("$PYBIN" $NA review)"
check "review: stale section"                  'echo "$OUTR" | grep -q "^  stale" && echo "$OUTR" | grep -q "L040"'
check "review: the pair that says the same"    'echo "$OUTR" | grep -q "say the same thing" && echo "$OUTR" | grep -q "L040 ~ L041"'
check "review: warned past, ungraded"          'echo "$OUTR" | grep -q "warned past, ungraded" && echo "$OUTR" | grep -q "na ok L043"'
check "review changes nothing"                 'grep -q "(L041)" LESSONS.md && "$PYBIN" $NA review | grep -q "Act through the never-again skill"'
"$PYBIN" $NA ok L043 >/dev/null; "$PYBIN" $NA wrong L043 >/dev/null 2>&1
"$PYBIN" $NA _fired L043 warn claude >/dev/null; "$PYBIN" $NA wrong L043 >/dev/null
check "review: a hook graded wrong twice is noisy" '"$PYBIN" $NA review | grep -q "false positives"'
check "na --help lists review, stale, dup"     '"$PYBIN" $NA --help | grep -q "na review" && "$PYBIN" $NA --help | grep -q "na stale" && "$PYBIN" $NA --help | grep -q "na dup"'
"$PYBIN" - <<'PY'
import json, io, re
p = '.claude/never-again/state.json'
st = json.load(io.open(p, encoding='utf-8'))
for lid in ('L040', 'L041', 'L042', 'L043', 'L044'):
    st['lessons'].pop(lid, None)
json.dump(st, io.open(p, 'w', encoding='utf-8'), indent=2)
q = 'LESSONS.md'
t = io.open(q, encoding='utf-8').read()
t = "\n".join(ln for ln in t.split("\n") if not re.search(r"\(L04[0-4]\)\s*$", ln))
io.open(q, 'w', encoding='utf-8').write(t)
PY

echo
echo "=== a newer release is noticed once a day, named on the next commit ==="
CACHE=.claude/never-again/.update-check
rm -f "$CACHE"
# Registering Antigravity above set "block"; this block is about the nudge.
"$PYBIN" - <<'PY'
import json, io
p = '.claude/never-again/state.json'
st = json.load(io.open(p, encoding='utf-8')); st['updates'] = 'check'
json.dump(st, io.open(p, 'w', encoding='utf-8'), indent=2)
PY
printf '{"tag_name":"v9.9.9"}' > "$TMPDIR_ROOT/na-release.json"
RELURL="file:///$(cd "$TMPDIR_ROOT" && { pwd -W 2>/dev/null || pwd -P; } | sed 's,^/,,')/na-release.json"
check "nothing cached: --cached says nothing" '[ -z "$("$PYBIN" $NA _check-update --cached)" ] && [ ! -f "$CACHE" ]'
check "the check fetches and names 9.9.9"    '[ "$(NA_UPDATE_URL="$RELURL" "$PYBIN" $NA _check-update)" = "9.9.9" ] && [ -f "$CACHE" ]'
check "within a day: cached, no fetch"       '[ "$(NA_UPDATE_URL="file:///nowhere/x.json" "$PYBIN" $NA _check-update)" = "9.9.9" ]'
check "na stats names it"                    '"$PYBIN" $NA | grep -q "9.9.9 is out"'
echo TODO-BLOCK > u.txt
OUTN="$(pay claude "git commit -m x" | NA_DRY_RUN=1 bash .claude/hooks/na/dispatch)"
check "the next commit carries the line"     'echo "$OUTN" | grep -q "9.9.9 is out"'
check "not on other commands"                '[ -z "$(pay claude ls | NA_DRY_RUN=1 bash .claude/hooks/na/dispatch)" ]'
git add u.txt
ERRN="$(bash .claude/hooks/na/pre-commit 2>&1 >/dev/null)"
check "git side says it too"                 'echo "$ERRN" | grep -q "9.9.9 is out"'
git reset -q u.txt; rm -f u.txt
"$PYBIN" - <<'PY'
import json, io
p = '.claude/never-again/.update-check'
c = json.load(io.open(p, encoding='utf-8')); c['ts'] = 0
json.dump(c, io.open(p, 'w', encoding='utf-8'))
PY
check "offline: keeps what it knew"          '[ "$(NA_UPDATE_URL="file:///nowhere/x.json" "$PYBIN" $NA _check-update)" = "9.9.9" ]'
printf '{"tag_name":"v0.0.1"}' > "$TMPDIR_ROOT/na-release.json"
"$PYBIN" - <<'PY'
import json, io
p = '.claude/never-again/.update-check'
c = json.load(io.open(p, encoding='utf-8')); c['ts'] = 0
json.dump(c, io.open(p, 'w', encoding='utf-8'))
PY
check "an older release is not news"         '[ -z "$(NA_UPDATE_URL="$RELURL" "$PYBIN" $NA _check-update)" ]'
"$PYBIN" - <<'PY'
import json, io
p = '.claude/never-again/state.json'
st = json.load(io.open(p, encoding='utf-8')); st['updates'] = 'off'
json.dump(st, io.open(p, 'w', encoding='utf-8'), indent=2)
p = '.claude/never-again/.update-check'
json.dump({"ts": 0, "latest": "9.9.9"}, io.open(p, 'w', encoding='utf-8'))
PY
check "updates off: silent, no fetch"        '[ -z "$(NA_UPDATE_URL="$RELURL" "$PYBIN" $NA _check-update)" ] && [ -z "$("$PYBIN" $NA _check-update --cached)" ]'
"$PYBIN" - <<'PY'
import json, io
p = '.claude/never-again/state.json'
st = json.load(io.open(p, encoding='utf-8')); st['updates'] = 'check'
json.dump(st, io.open(p, 'w', encoding='utf-8'), indent=2)
PY
rm -f "$CACHE" "$TMPDIR_ROOT/na-release.json"
check "new state.json carries the setting"   'grep -q "\"updates\": \"check\"" .claude/never-again/state.json'
check ".update-check is ignored"             'git check-ignore -q .claude/never-again/.update-check'

echo
echo "=== \"updates\": \"block\": a stale release stops the commit, not a line ==="
# The line on a successful commit's stderr was committed straight past by an
# agent that runs git in a terminal nobody reads (L006). A refused command is
# read: from every agent's hook and from git's own pre-commit.
set_updates() { "$PYBIN" - "$1" <<'PY'
import json, io, sys
p = '.claude/never-again/state.json'
st = json.load(io.open(p, encoding='utf-8')); st['updates'] = sys.argv[1]
json.dump(st, io.open(p, 'w', encoding='utf-8'), indent=2)
PY
}
set_cache() { "$PYBIN" - "$@" <<'PY'
import json, io, sys, time
p = '.claude/never-again/.update-check'
c = {"ts": time.time(), "latest": sys.argv[1], "checked_by": "test"}
if len(sys.argv) > 2: c["later"] = sys.argv[2]; c["laterTs"] = float(sys.argv[3])
json.dump(c, io.open(p, 'w', encoding='utf-8'))
PY
}
set_updates block; set_cache 9.9.9
check "--how says stop"                      '[ "$("$PYBIN" $NA _check-update --cached --how)" = "9.9.9 stop" ]'
check "--cached alone still just the version" '[ "$("$PYBIN" $NA _check-update --cached)" = "9.9.9" ]'
OUTB="$(pay claude "git commit -m x" | NA_DRY_RUN=1 bash .claude/hooks/na/dispatch)"
check "Claude Code: the commit is denied"    'echo "$OUTB" | grep -q "\"permissionDecision\": \"deny\"" && echo "$OUTB" | grep -q "9.9.9 is out"'
check "the reason names the way out"         'echo "$OUTB" | grep -q "na upgrade" && echo "$OUTB" | grep -q "upgrade --later"'
check "no nudge line on top of the stop"     '! echo "$OUTB" | grep -q "when convenient"'
check "not on other commands"                '[ -z "$(pay claude ls | NA_DRY_RUN=1 bash .claude/hooks/na/dispatch)" ]'
OUTB="$(pay antigravity "git commit -m x" | NA_DRY_RUN=1 bash .claude/hooks/na/dispatch --agent antigravity)"
check "Antigravity: decision deny"           'echo "$OUTB" | grep -q "\"decision\": \"deny\"" && echo "$OUTB" | grep -q "\"allow_tool\": false"'
echo fine > u.txt; git add u.txt     # no hook has anything to say; the release is the only stop
ERRB="$(bash .claude/hooks/na/pre-commit 2>&1 >/dev/null)"; RCB=$?
check "git side: the commit is refused"      '[ $RCB -ne 0 ] && echo "$ERRB" | grep -q "stopped until the repo moves"'
check "a stopped commit is a fired call"     '[ "$(awk -F"\t" "END{print \$3\" \"\$4}" .claude/never-again/calls.log)" = "git fired" ]'
check "retrying unchanged does not get past" 'bash .claude/hooks/na/pre-commit >/dev/null 2>&1; [ $? -ne 0 ]'
check "na says commits stop"                 '"$PYBIN" $NA | grep -q "commits stop until then"'
OUTL="$("$PYBIN" $NA upgrade --later 2>&1)"
check "--later defers and says so"           'echo "$OUTL" | grep -q "9.9.9 deferred" && "$PYBIN" -c "import json,sys; c=json.load(open(\".claude/never-again/.update-check\")); sys.exit(0 if c.get(\"later\")==\"9.9.9\" and c.get(\"laterTs\") else 1)"'
check "deferred: --how says nudge"           '[ "$("$PYBIN" $NA _check-update --cached --how)" = "9.9.9 nudge" ]'
ERRB="$(bash .claude/hooks/na/pre-commit 2>&1 >/dev/null)"; RCB=$?
check "deferred: git commit goes ahead"      '[ $RCB -eq 0 ] && echo "$ERRB" | grep -q "9.9.9 is out" && ! echo "$ERRB" | grep -q stopped'
OUTB="$(pay claude "git commit -m x" | NA_DRY_RUN=1 bash .claude/hooks/na/dispatch)"
check "deferred: Claude Code gets the line"  '! echo "$OUTB" | grep -q deny && echo "$OUTB" | grep -q "when convenient"'
check "na says it is deferred"               '"$PYBIN" $NA | grep -q "deferred: commits go ahead"'
"$PYBIN" - <<'PY'
import json, io
p = '.claude/never-again/.update-check'
c = json.load(io.open(p, encoding='utf-8')); c['ts'] = 0
json.dump(c, io.open(p, 'w', encoding='utf-8'))
PY
printf '{"tag_name":"v9.9.9"}' > "$TMPDIR_ROOT/na-release.json"
NA_UPDATE_URL="$RELURL" "$PYBIN" $NA _check-update >/dev/null
check "the daily refresh keeps the deferral" '[ "$("$PYBIN" $NA _check-update --cached --how)" = "9.9.9 nudge" ]'
set_cache 9.9.9 9.9.9 0
check "a day later the stop is back"         '[ "$("$PYBIN" $NA _check-update --cached --how)" = "9.9.9 stop" ]'
set_cache 9.9.10 9.9.9 "$(date +%s)"
check "a newer release than the deferred one stops" '[ "$("$PYBIN" $NA _check-update --cached --how)" = "9.9.10 stop" ]'
set_cache 0.0.1
check "nothing newer: --later has nothing to defer" '"$PYBIN" $NA upgrade --later | grep -q "Nothing to defer"'
# A cache ahead of GitHub (a release pulled or retagged) would stop every
# commit while the way out says there is nothing to do; na upgrade heard
# GitHub itself, so the cache takes that answer.
set_cache 9.9.9; printf '{"tag_name":"v0.0.1"}' > "$TMPDIR_ROOT/na-release.json"
OUTU="$(NA_UPDATE_URL="$RELURL" "$PYBIN" $NA upgrade 2>&1)"
check "upgrade with nothing newer settles the cache" 'echo "$OUTU" | grep -q "Nothing to do" && [ -z "$("$PYBIN" $NA _check-update --cached --how)" ]'
check "the stop is gone with it"             'bash .claude/hooks/na/pre-commit >/dev/null 2>&1'
check "--from a local copy leaves the cache alone" 'set_cache 9.9.9; "$PYBIN" $NA upgrade --check --from "$SRC" >/dev/null 2>&1; [ "$("$PYBIN" $NA _check-update --cached)" = "9.9.9" ]'
set_updates check; set_cache 9.9.9
check "check mode: --how says nudge"         '[ "$("$PYBIN" $NA _check-update --cached --how)" = "9.9.9 nudge" ]'
OUTL="$("$PYBIN" $NA upgrade --later 2>&1)"
check "--later under check says commits never stopped" 'echo "$OUTL" | grep -q "never stopped"'
set_updates off
check "off: --how says nothing"              '[ -z "$("$PYBIN" $NA _check-update --cached --how)" ]'
set_updates check
git reset -q u.txt; rm -f u.txt "$CACHE" "$TMPDIR_ROOT/na-release.json"

echo
echo "=== na upgrade moves one repo, on request, forwards only ==="
# A copy of the source with a higher version stands in for a release; the
# network path differs only in where the tarball comes from.
UPSRC="$TMPDIR_ROOT/na-upgrade-src"; rm -rf "$UPSRC"; mkdir -p "$UPSRC"
for f in install.sh scripts templates skills; do cp -R "$SRC/$f" "$UPSRC/"; done
sedi 's/^VERSION = "[0-9.]*"/VERSION = "9.9.9"/' "$UPSRC/scripts/na"
OUTU="$("$PYBIN" $NA upgrade --check --from "$SRC" 2>&1)"
check "same version: nothing to do"      'echo "$OUTU" | grep -q "up to date"'
OUTU="$("$PYBIN" $NA upgrade --check --from "$UPSRC" 2>&1)"
check "--check reports, changes nothing" 'echo "$OUTU" | grep -q "available  9.9.9" && "$PYBIN" $NA --version | grep -q "never-again 1\."'
OUTU="$("$PYBIN" $NA upgrade --from "$UPSRC" </dev/null 2>&1)"
check "no answer: nothing changed"       'echo "$OUTU" | grep -q "Nothing changed" && "$PYBIN" $NA --version | grep -q "never-again 1\."'
echo "keep me" >> LESSONS.md
OUTU="$("$PYBIN" $NA upgrade --yes --from "$UPSRC" 2>&1)"
check "--yes runs the installer here"    'echo "$OUTU" | grep -q -- "-> 9.9.9" && "$PYBIN" $NA --version | grep -q "never-again 9.9.9"'
check "upgrade keeps LESSONS.md"         'grep -q "keep me" LESSONS.md'
check "upgrade keeps state.json"         'grep -q "\"agents\"" .claude/never-again/state.json'
OUTU="$("$PYBIN" $NA upgrade --yes --from "$SRC" 2>&1)"
check "never moves backwards"            'echo "$OUTU" | grep -q "up to date" && "$PYBIN" $NA --version | grep -q "never-again 9.9.9"'
( cd "$UPSRC" && sedi 's/^VERSION = "9.9.9"/VERSION = "9.9.10"/' scripts/na && mkdir -p ../na-upgrade-tar && tar czf ../na-upgrade-tar/release.tgz --transform 's,^,claude-never-again-9.9.10/,' . 2>/dev/null || tar czf ../na-upgrade-tar/release.tgz -s ',^,claude-never-again-9.9.10/,' . )
OUTU="$("$PYBIN" $NA upgrade --yes --from "$TMPDIR_ROOT/na-upgrade-tar/release.tgz" 2>&1)"
check "a tarball works the same way"     'echo "$OUTU" | grep -q -- "-> 9.9.10" && "$PYBIN" $NA --version | grep -q "never-again 9.9.10"'
bash "$SRC/install.sh" . >/dev/null 2>&1
rm -rf "$UPSRC" "$TMPDIR_ROOT/na-upgrade-tar"

echo
echo "  ---------------------------------"
echo "  $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
