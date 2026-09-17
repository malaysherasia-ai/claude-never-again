#!/usr/bin/env bash
# Acceptance test for `na uninstall`.
#
# The property under test is not "it deletes things" but "it deletes only its
# own things". The fixture is therefore a repo that already has opinions: a
# CLAUDE.md with a house-style section, a settings.json with the user's own
# hook and an env block, a .gitignore with real entries, and a LESSONS.md with
# a rule in it. All of those must survive.
#
#   bash tests/uninstall.sh [tmpdir]
set -u    # no pipefail: `producer | grep -q` would fail on the producer's broken pipe

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
T="${1:-${TMPDIR:-/tmp}/na-uninstall-test}"

# Resolve a Python that actually runs, the same way the tool does. On Windows
# `command -v python3` finds the Microsoft Store stub: it exists, it is on PATH,
# and it exits 49 having run nothing. Testing for existence here hung this very
# script. Existence is never the test.
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
# failed cd once left this script rewriting CLAUDE.md in the tool repo.
case "$T" in "$SRC"|"$SRC"/*) echo "refusing to run inside $SRC"; exit 1 ;; esac
rm -rf "$T" && mkdir -p "$T" && cd "$T" || { echo "cannot create $T"; exit 1; }
[ "$(pwd -P)" != "$(cd "$SRC" && pwd -P)" ] || { echo "refusing to run inside $SRC"; exit 1; }
git init -q .

# --- a repo that already has opinions of its own ---------------------------
cat > CLAUDE.md <<'EOF'
# Project instructions

## House style
Two spaces, no tabs. This line must survive an uninstall.
EOF

mkdir -p .claude
cat > .claude/settings.json <<'EOF'
{
  "env": { "MY_VAR": "keep-me" },
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          { "type": "command", "if": "Bash(rm *)", "command": "echo my-own-hook" }
        ]
      }
    ]
  }
}
EOF

cat > .gitignore <<'EOF'
node_modules/
*.log
EOF

# Another agent's config with an entry of its own, and its rules file with
# a section of its own. Both must survive too.
mkdir -p .codex
printf '{"hooks":{"PreToolUse":[{"matcher":"Bash","hooks":[{"type":"command","command":"echo mine"}]}]}}\n' > .codex/hooks.json
printf '# Agent notes\n\nKeep this line.\n' > AGENTS.md

echo "=== install ==="
bash "$SRC/install.sh" --agent copilot . >/dev/null 2>&1 || { echo "install failed"; exit 1; }

# The skill registers hooks after install; simulate that.
mkdir -p .claude/hooks/na
echo '#!/usr/bin/env bash' > .claude/hooks/na/L001.sh
"$PYBIN" - <<'PY'
import json
d=json.load(open('.claude/settings.json'))
d['hooks']['PreToolUse'][0]['hooks'].append({
  "type":"command","if":"Bash(git commit *)",
  "command":'"$CLAUDE_PROJECT_DIR"/.claude/hooks/na/L001.sh'})
json.dump(d, open('.claude/settings.json','w'), indent=2)
PY
echo "user's own lesson" >> LESSONS.md

check "installed: skill dir"        '[ -d .claude/skills/never-again ]'
check "installed: na"               '[ -f .claude/never-again/na ]'
check "installed: CLAUDE.md block"  'grep -q "BEGIN never-again" CLAUDE.md'
check "installed: gitignore block"  'grep -q "never-again/fires.log" .gitignore && grep -q "never-again/calls.log" .gitignore'
check "installed: git stub"         'grep -q "never-again" .git/hooks/pre-commit'
check "installed: resolver entry"   'grep -q "_after.sh" .claude/settings.json'
check "installed: codex entries"    'grep -q dispatch .codex/hooks.json'
check "installed: copilot file"     '[ -f .github/hooks/never-again.json ]'
check "installed: AGENTS.md block"  'grep -q "BEGIN never-again" AGENTS.md'
check "installed: agent skills"     '[ -f .agents/skills/never-again/SKILL.md ] && [ -f .github/skills/never-again/SKILL.md ]'

echo
echo "=== uninstall refuses without confirmation (non-tty) ==="
OUT="$("$PYBIN" .claude/never-again/na uninstall </dev/null 2>&1)"
check "refuses without --yes"       'echo "$OUT" | grep -q "Nothing removed"'
check "nothing removed yet"         '[ -d .claude/never-again ]'
check "plan lists LESSONS.md kept"  'echo "$OUT" | grep -q "keep .*LESSONS.md"'

echo
echo "=== uninstall --yes ==="
"$PYBIN" .claude/never-again/na uninstall --yes 2>&1 | sed 's/^/    /'

echo
echo "=== removed what it owns ==="
check "skill dir gone"              '[ ! -d .claude/skills/never-again ]'
check "hooks/na gone"               '[ ! -d .claude/hooks/na ]'
check "never-again dir gone"        '[ ! -d .claude/never-again ]'
check "git stub gone"               '[ ! -f .git/hooks/pre-commit ]'
check "merge stub gone"             '[ ! -f .git/hooks/pre-merge-commit ]'
check "copilot file gone"           '[ ! -f .github/hooks/never-again.json ] && [ ! -d .github/hooks ]'
check "agent skills gone"           '[ ! -d .agents/skills/never-again ] && [ ! -d .github/skills ]'

echo
echo "=== kept what it does not own ==="
check "LESSONS.md kept"             '[ -f LESSONS.md ]'
check "LESSONS.md content intact"   'grep -q "user.s own lesson" LESSONS.md'
check "CLAUDE.md still exists"      '[ -f CLAUDE.md ]'
check "CLAUDE.md house style kept"  'grep -q "must survive an uninstall" CLAUDE.md'
check "CLAUDE.md block stripped"    '! grep -q "never-again" CLAUDE.md'
check "gitignore user lines kept"   'grep -q "node_modules/" .gitignore'
check "gitignore block stripped"    '! grep -q "never-again" .gitignore && ! grep -q "CLAUDE.md.bak" .gitignore'
check "codex own entry kept"        'grep -q "echo mine" .codex/hooks.json && ! grep -q "hooks/na" .codex/hooks.json'
check "AGENTS.md own text kept"     'grep -q "Keep this line" AGENTS.md && ! grep -q "never-again" AGENTS.md'
check "copilot-instructions block stripped" '! grep -q "never-again" .github/copilot-instructions.md'

echo
echo "=== settings.json merged, not replaced ==="
"$PYBIN" - <<'PY'
import json,sys
d=json.load(open('.claude/settings.json'))
checks=[
 ("env preserved", d.get('env',{}).get('MY_VAR')=='keep-me'),
 ("user hook preserved", any('my-own-hook' in h.get('command','')
    for g in d.get('hooks',{}).get('PreToolUse',[]) for h in g.get('hooks',[]))),
 ("na hook removed", not any('hooks/na' in h.get('command','')
    for g in d.get('hooks',{}).get('PreToolUse',[]) for h in g.get('hooks',[]))),
 ("resolver removed", not any('hooks/na' in h.get('command','')
    for e in ('PostToolUse','PostToolUseFailure')
    for g in d.get('hooks',{}).get(e,[]) for h in g.get('hooks',[]))),
]
for name,good in checks:
    print(("  PASS  " if good else "  FAIL  ")+name)
sys.exit(0 if all(g for _,g in checks) else 1)
PY
S=$?; [ $S -eq 0 ] && PASS=$((PASS+4)) || FAIL=$((FAIL+1))

echo
echo "=== safe to run twice ==="
# After a real uninstall `na` is gone, so the second attempt comes through
# install.sh. It must say so plainly rather than erroring or half-acting.
OUT2="$(bash "$SRC/install.sh" --uninstall . 2>&1)"; RC2=$?
check "second run says not installed" 'echo "$OUT2" | grep -q "not installed"'
check "second run exits non-zero"     '[ "$RC2" -ne 0 ]'
check "CLAUDE.md untouched again"     'grep -q "must survive an uninstall" CLAUDE.md'

# A stale install directory holding nothing but na is also a clean no-op.
mkdir -p .claude/never-again
cp "$SRC/scripts/na" .claude/never-again/na
"$PYBIN" .claude/never-again/na uninstall --yes >/dev/null 2>&1
check "stale dir removed cleanly"     '[ ! -d .claude/never-again ]'
check "still keeps CLAUDE.md"         'grep -q "must survive an uninstall" CLAUDE.md'

echo
echo "=== a pre-commit hook that is not ours is not touched ==="
printf '#!/bin/sh
echo my-own-pre-commit
' > .git/hooks/pre-commit
OUT3="$(bash "$SRC/install.sh" . 2>&1)"
check "install says what line to add"   'echo "$OUT3" | grep -q "add this line"'
check "install left it alone"           'grep -q my-own-pre-commit .git/hooks/pre-commit && ! grep -q never-again .git/hooks/pre-commit'
"$PYBIN" .claude/never-again/na uninstall --yes >/dev/null 2>&1
check "uninstall left it alone"         'grep -q my-own-pre-commit .git/hooks/pre-commit'

echo
echo "  ---------------------------------"
echo "  $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
