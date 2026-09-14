#!/usr/bin/env bash
# never-again installer — safe to run repeatedly.
#
#   bash install.sh [target-repo]              install or re-install
#   bash install.sh --uninstall [target-repo]   remove it again
#
# Both default to the current directory.

set -euo pipefail

# Resolve a Python that actually runs. On Windows `command -v python3` finds
# the Microsoft Store stub, which exits non-zero and would silence this script.
na_python() {
  local c
  for c in "${NA_PYTHON:-}" python3 python py; do
    [ -n "$c" ] || continue
    # Existence is not the test — the Store stub exists and still does nothing.
    # Only an interpreter that runs a statement and exits 0 is accepted.
    if "$c" -c 'import sys' >/dev/null 2>&1; then
      command -v "$c"
      return 0
    fi
  done
  return 1
}
PY="$(na_python)" || { echo "never-again: no working python found" >&2; exit 1; }

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# --- uninstall --------------------------------------------------------------
# Delegates to `na`, which lives in the target repo. This script lives in the
# clone, and people delete the clone once they have installed; the repo still
# has `na`. One implementation, so install and uninstall cannot drift over
# which files belong to never-again.
UNINSTALL=0
ARGS=()
for a in "$@"; do
  case "$a" in
    --uninstall) UNINSTALL=1 ;;
    *) ARGS+=("$a") ;;
  esac
done
set -- ${ARGS+"${ARGS[@]}"}

DEST="$(cd "${1:-$PWD}" && pwd)"

if [ "$UNINSTALL" -eq 1 ]; then
  NA="$DEST/.claude/never-again/na"
  if [ ! -f "$NA" ]; then
    echo "never-again is not installed in $DEST (no .claude/never-again/na)." >&2
    exit 1
  fi
  exec "$PY" "$NA" uninstall
fi

echo "never-again → $DEST"

mkdir -p "$DEST/.claude/skills" \
         "$DEST/.claude/hooks/na" \
         "$DEST/.claude/never-again/archive"

# --- skill ------------------------------------------------------------------
cp -R "$SRC/skills/never-again" "$DEST/.claude/skills/"
echo "  skill      .claude/skills/never-again/"

# --- scripts ----------------------------------------------------------------
cp "$SRC/scripts/na" "$DEST/.claude/never-again/na"
chmod +x "$DEST/.claude/never-again/na"
cp "$SRC/templates/na.cmd" "$DEST/.claude/never-again/na.cmd"
cp "$SRC/templates/hook-warn.sh" "$DEST/.claude/never-again/hook-template.sh"
cp "$SRC/templates/LESSONS.md"   "$DEST/.claude/never-again/lessons-template.md"
echo "  cli        .claude/never-again/na  (na.cmd for PowerShell and cmd)"

# The shared library every hook sources, the after-commit resolver that records
# what the person chose at a warn prompt, and the runner git calls so hooks
# apply to commits made outside Claude Code's Bash tool too.
cp "$SRC/templates/na-lib.sh"       "$DEST/.claude/hooks/na/na-lib.sh"
cp "$SRC/templates/after-commit.sh" "$DEST/.claude/hooks/na/_after.sh"
cp "$SRC/templates/pre-commit"      "$DEST/.claude/hooks/na/pre-commit"
chmod +x "$DEST/.claude/hooks/na/_after.sh" "$DEST/.claude/hooks/na/pre-commit"
echo "  hooks      .claude/hooks/na/na-lib.sh, _after.sh, pre-commit"

# --- settings.json: the after-commit resolver --------------------------------
# Merged, never replaced. Idempotent: an entry pointing at _after.sh is left as
# it is. The skill merges each lesson's own hook the same way.
SETTINGS="$DEST/.claude/settings.json"
"$PY" - "$SETTINGS" <<'PYEOF'
import json, os, sys
path = sys.argv[1]
settings = {}
if os.path.isfile(path):
    with open(path, encoding="utf-8") as fh:
        text = fh.read().strip()
    if text:
        try:
            settings = json.loads(text)
        except ValueError as exc:
            sys.exit("  settings   .claude/settings.json could not be parsed (%s); "
                     "register .claude/hooks/na/_after.sh on PostToolUse yourself" % exc)
hooks = settings.setdefault("hooks", {})
entry = {"type": "command", "if": "Bash(git commit *)",
         "command": '"$CLAUDE_PROJECT_DIR"/.claude/hooks/na/_after.sh'}
added = 0
for event in ("PostToolUse", "PostToolUseFailure"):
    groups = hooks.setdefault(event, [])
    present = any("/.claude/hooks/na/_after.sh" in (h.get("command", "").replace("\\", "/"))
                  for g in groups for h in (g or {}).get("hooks", []) or [])
    if present:
        continue
    group = next((g for g in groups if g.get("matcher") == "Bash"), None)
    if group is None:
        group = {"matcher": "Bash", "hooks": []}
        groups.append(group)
    group.setdefault("hooks", []).append(dict(entry))
    added += 1
if added:
    with open(path, "w", encoding="utf-8", newline="\n") as fh:
        json.dump(settings, fh, indent=2)
        fh.write("\n")
    print("  settings   after-commit resolver registered (%d event%s)" % (added, "" if added == 1 else "s"))
else:
    print("  settings   after-commit resolver already registered")
PYEOF

# --- git pre-commit -----------------------------------------------------------
# A stub in git's hooks directory hands every commit to the runner, so a hook
# guards commits from any tool or terminal, not only Claude Code's Bash tool.
# An existing pre-commit hook is never edited; we say what line to add.
if HOOKDIR="$(git -C "$DEST" rev-parse --git-path hooks 2>/dev/null)"; then
  case "$HOOKDIR" in /*|[A-Za-z]:*) ;; *) HOOKDIR="$DEST/$HOOKDIR" ;; esac
  mkdir -p "$HOOKDIR"
  STUB="$HOOKDIR/pre-commit"
  if [ ! -f "$STUB" ]; then
    # If someone deletes .claude/ by hand instead of running uninstall, the
    # stub must not fail every commit from then on. No runner, no opinion.
    cat >"$STUB" <<'SHEOF'
#!/bin/sh
# never-again pre-commit stub (managed by install.sh; uninstall removes it)
r="$(git rev-parse --show-toplevel)/.claude/hooks/na/pre-commit"
[ -f "$r" ] || exit 0
exec "$r" "$@"
SHEOF
    chmod +x "$STUB"
    echo "  git        pre-commit stub installed"
  elif grep -q "never-again pre-commit stub" "$STUB"; then
    # Ours. Rewrite it so an older stub picks up the missing-runner guard.
    if ! grep -q '\[ -f "\$r" \]' "$STUB"; then
      cat >"$STUB" <<'SHEOF'
#!/bin/sh
# never-again pre-commit stub (managed by install.sh; uninstall removes it)
r="$(git rev-parse --show-toplevel)/.claude/hooks/na/pre-commit"
[ -f "$r" ] || exit 0
exec "$r" "$@"
SHEOF
      chmod +x "$STUB"
      echo "  git        pre-commit stub upgraded"
    else
      echo "  git        pre-commit stub already in place"
    fi
  elif grep -q "never-again" "$STUB"; then
    echo "  git        pre-commit already calls never-again"
  else
    echo "  git        you already have a pre-commit hook; add this line to it:"
    echo '             "$(git rev-parse --show-toplevel)/.claude/hooks/na/pre-commit" || exit 1'
  fi
else
  echo "  git        not a git repository; commit hooks will run from Claude Code only"
fi

# --- LESSONS.md -------------------------------------------------------------
if [ -f "$DEST/LESSONS.md" ]; then
  # Many people kept a LESSONS.md long before this tool. It is theirs, so it
  # is never edited. But notes in their own words are invisible to `na`: not
  # counted, not capped, not sorted, not enforced. Say so, and say what to do.
  "$PY" - "$DEST/LESSONS.md" <<'PYEOF'
import re, sys
rule = re.compile(r"^\s*-\s+\[[^\]]+\]\s+.+\(L\d+\)\s*$")
lines = open(sys.argv[1], encoding="utf-8", errors="replace").read().split("\n")
# A file made from our template carries a marker; its header prose above the
# marker is ours, not the person's notes. Only look below it.
marker = next((i for i, ln in enumerate(lines) if "managed by the never-again skill" in ln), None)
if marker is not None:
    lines = lines[marker + 1:]
filed = sum(1 for ln in lines if rule.match(ln))
other = sum(1 for ln in lines if ln.strip() and not ln.lstrip().startswith(("#", "<!--"))
            and not rule.match(ln) and ln.strip() != "---")
if other and not filed:
    print("  lessons    LESSONS.md already exists — left untouched")
    print("             It holds %d line(s) of notes in your own words. Claude will read them," % other)
    print("             but never-again cannot count, cap, sort or enforce them. To bring them")
    print("             in, tell Claude once:")
    print('               "read LESSONS.md and refile each note through the never-again skill"')
elif other:
    print("  lessons    LESSONS.md already exists — left untouched (%d filed, %d note(s) in your own words)" % (filed, other))
else:
    print("  lessons    LESSONS.md already exists — left untouched (%d filed)" % filed)
PYEOF
else
  cp "$SRC/templates/LESSONS.md" "$DEST/LESSONS.md"
  echo "  lessons    LESSONS.md created"
fi

# --- state.json -------------------------------------------------------------
STATE="$DEST/.claude/never-again/state.json"
if [ -f "$STATE" ]; then
  echo "  state      state.json already exists — left untouched"
else
  cat >"$STATE" <<'JSON'
{
  "version": 1,
  "nextId": 1,
  "cap": 40,
  "loadedWarn": 60,
  "tokensPerPreventedRepeat": 8000,
  "lessons": {}
}
JSON
  echo "  state      state.json created"
fi

# --- CLAUDE.md --------------------------------------------------------------
# Merge, never clobber. The block is delimited so it can be replaced or removed.
CLAUDE="$DEST/CLAUDE.md"
BLOCK="$SRC/templates/CLAUDE-block.md"

if [ ! -f "$CLAUDE" ]; then
  { echo "# Project instructions"; echo; cat "$BLOCK"; } >"$CLAUDE"
  echo "  claude.md  created with the never-again block"
elif grep -q "<!-- BEGIN never-again -->" "$CLAUDE"; then
  cp "$CLAUDE" "$CLAUDE.bak"
  # Explicit UTF-8 throughout. Python's default on Windows is cp1252, which
  # cannot decode every byte and crashed this step on ordinary non-English text.
  "$PY" - "$CLAUDE" "$BLOCK" <<'PYEOF'
import re, sys
path, block = sys.argv[1], sys.argv[2]
text = open(path, encoding="utf-8").read()
new = open(block, encoding="utf-8").read().strip()
text = re.sub(
    r"<!-- BEGIN never-again -->.*?<!-- END never-again -->",
    lambda _m: new, text, flags=re.S)
open(path, "w", encoding="utf-8", newline="\n").write(text)
PYEOF
  echo "  claude.md  existing block updated (backup at CLAUDE.md.bak)"
else
  cp "$CLAUDE" "$CLAUDE.bak"
  { echo; cat "$BLOCK"; } >>"$CLAUDE"
  echo "  claude.md  block appended (backup at CLAUDE.md.bak)"
fi

# --- .gitignore -------------------------------------------------------------
GI="$DEST/.gitignore"
CLAUDE_IGNORED=0
if git -C "$DEST" check-ignore -q .claude/hooks/na 2>/dev/null; then
  CLAUDE_IGNORED=1
fi
if [ "$CLAUDE_IGNORED" -eq 1 ]; then
  # The whole .claude/ tree is per-user here, so the hooks, the modes and the
  # skill never reach git. The tool still works on this machine; the "a new
  # clone inherits every hook" promise does not hold. Say so once, loudly.
  echo "  gitignore  .claude/ is ignored in this repo, so the hooks, state.json and skill"
  echo "             stay on this machine and are NOT shared through git. LESSONS.md still is."
  echo "             To share the hooks too, add these lines to .gitignore:"
  echo "               !.claude/hooks/na/"
  echo "               !.claude/never-again/"
  echo "               !.claude/skills/never-again/"
  echo "               .claude/never-again/fires.log"
  echo "               .claude/never-again/.last-boot"
elif ! { [ -f "$GI" ] && grep -q "never-again/fires.log" "$GI"; }; then
  { echo; echo "# never-again (local only)"
    echo ".claude/never-again/fires.log"
    echo ".claude/never-again/.last-boot"
    echo "CLAUDE.md.bak"; } >>"$GI"
  echo "  gitignore  local state ignored"
elif ! grep -q "^CLAUDE.md.bak$" "$GI"; then
  # An install from before 0.2.1 wrote the block without this line.
  "$PY" - "$GI" <<'PYEOF'
import io, sys
p = sys.argv[1]
s = io.open(p, encoding="utf-8").read()
s = s.replace(".claude/never-again/.last-boot\n", ".claude/never-again/.last-boot\nCLAUDE.md.bak\n", 1)
io.open(p, "w", encoding="utf-8", newline="\n").write(s)
PYEOF
  echo "  gitignore  CLAUDE.md.bak added to the local-only block"
fi

# --- static hosts -------------------------------------------------------------
# A root LESSONS.md is a public URL on a host that serves the repo root.
for host in "vercel.json:.vercelignore" "netlify.toml:_redirects"; do
  cfg="${host%%:*}"
  if [ -f "$DEST/$cfg" ]; then
    case "$cfg" in
      vercel.json)
        if ! { [ -f "$DEST/.vercelignore" ] && grep -q "LESSONS.md" "$DEST/.vercelignore" && grep -q "^\.claude" "$DEST/.vercelignore"; }; then
          echo "  hosting    vercel.json found: Vercel would serve /LESSONS.md publicly, and"
          echo "             /.claude/ with it (hooks, settings.json, state.json). Add to .vercelignore:"
          echo "               .claude"
          echo "               LESSONS.md"
          echo "               CLAUDE.md"
        fi ;;
      netlify.toml)
        echo "  hosting    netlify.toml found: if the publish directory is the repo root,"
        echo "             /LESSONS.md and /.claude/ are public URLs. Publish a subdirectory or block them." ;;
    esac
  fi
done

cat <<'EOF'

Done. LESSONS.md and the hooks are meant to be committed — they are team
knowledge. Only fires.log is local.

Next: fix a bug, then tell Claude "never again".

Stats:  .claude/never-again/na          (PowerShell: .claude\never-again\na.cmd)
Handy:  alias na=".claude/never-again/na"
EOF
