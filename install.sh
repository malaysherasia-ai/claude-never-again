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
cp "$SRC/templates/hook-warn.sh"   "$DEST/.claude/never-again/hook-template.sh"
cp "$SRC/templates/hook-verify.sh" "$DEST/.claude/never-again/hook-verify-template.sh"
cp "$SRC/templates/LESSONS.md"     "$DEST/.claude/never-again/lessons-template.md"
cp "$SRC/templates/na-manifest.py" "$DEST/.claude/hooks/na/na-manifest.py"
echo "  cli        .claude/never-again/na  (na.cmd for PowerShell and cmd)"

# The shared library every hook sources, the after-commit resolver that records
# what the person chose at a warn prompt, and the runner git calls so hooks
# apply to commits made outside Claude Code's Bash tool too.
cp "$SRC/templates/na-lib.sh"       "$DEST/.claude/hooks/na/na-lib.sh"
cp "$SRC/templates/na-verify.sh"    "$DEST/.claude/hooks/na/na-verify.sh"
cp "$SRC/templates/after-commit.sh" "$DEST/.claude/hooks/na/_after.sh"
cp "$SRC/templates/pre-commit"      "$DEST/.claude/hooks/na/pre-commit"
chmod +x "$DEST/.claude/hooks/na/_after.sh" "$DEST/.claude/hooks/na/pre-commit"
echo "  hooks      .claude/hooks/na/na-lib.sh, na-verify.sh, na-manifest.py, _after.sh, pre-commit"

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
# A pre-commit hook we did not write is never edited; we say what to add. A
# stub we wrote is rewritten only if it is exactly a stub we wrote, so lines
# a person added to it survive.
na_stub() {
  cat <<'SHEOF'
#!/bin/sh
# never-again pre-commit stub (managed by install.sh; uninstall removes it)
r="$(git rev-parse --show-toplevel)/.claude/hooks/na/pre-commit"
if [ ! -f "$r" ]; then
  echo "never-again: .claude/hooks/na/pre-commit is missing, so no hook ran. Re-run install.sh, or delete .git/hooks/pre-commit." >&2
  exit 0
fi
exec "$r" "$@"
SHEOF
}
na_old_stub() {
  cat <<'SHEOF'
#!/bin/sh
# never-again pre-commit stub (managed by install.sh; uninstall removes it)
exec "$(git rev-parse --show-toplevel)/.claude/hooks/na/pre-commit" "$@"
SHEOF
}
na_old_stub_2() {
  cat <<'SHEOF'
#!/bin/sh
# never-again pre-commit stub (managed by install.sh; uninstall removes it)
r="$(git rev-parse --show-toplevel)/.claude/hooks/na/pre-commit"
[ -f "$r" ] || exit 0
exec "$r" "$@"
SHEOF
}
if HOOKDIR="$(git -C "$DEST" rev-parse --git-path hooks 2>/dev/null)"; then
  case "$HOOKDIR" in /*|[A-Za-z]:*) ;; *) HOOKDIR="$DEST/$HOOKDIR" ;; esac
  mkdir -p "$HOOKDIR"
  STUB="$HOOKDIR/pre-commit"
  if [ ! -f "$STUB" ]; then
    na_stub >"$STUB"; chmod +x "$STUB"
    echo "  git        pre-commit stub installed"
  elif [ "$(cat "$STUB")" = "$(na_stub)" ]; then
    echo "  git        pre-commit stub already in place"
  elif [ "$(cat "$STUB")" = "$(na_old_stub)" ] || [ "$(cat "$STUB")" = "$(na_old_stub_2)" ]; then
    na_stub >"$STUB"; chmod +x "$STUB"
    echo "  git        pre-commit stub upgraded"
  elif grep -q "never-again" "$STUB"; then
    echo "  git        pre-commit already calls never-again (edited by hand, left alone)"
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
  # counted, not capped, not sorted, not enforced. `na` says so, in the same
  # terms it counts by.
  CLAUDE_PROJECT_DIR="$DEST" "$PY" "$DEST/.claude/never-again/na" _lessons-report
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
# The local-only block (fires.log, verified manifests, the CLAUDE.md backup)
# is owned by `na`, which writes it fresh or brings an older one up to date.
if GIOUT="$(CLAUDE_PROJECT_DIR="$DEST" "$PY" "$DEST/.claude/never-again/na" _gitignore 2>&1)"; then
  case "$GIOUT" in
    written)  echo "  gitignore  local state ignored" ;;
    upgraded) echo "  gitignore  local-only block brought up to date" ;;
  esac
else
  echo "  gitignore  COULD NOT update .gitignore: ${GIOUT##*$'\n'}"
  echo "             Add these lines yourself so local state is never committed:"
  echo "               .claude/never-again/fires.log"
  echo "               .claude/never-again/verified/"
  echo "               CLAUDE.md.bak"
fi

# A repo that ignores .claude/ keeps the hooks on this machine. Ask git about
# a hook that does not exist yet, which is the question that matters: will the
# next hook the skill writes reach the repo? Git never re-includes a path under
# an excluded directory, so the fix is to replace the .claude/ line, not add to it.
if git -C "$DEST" check-ignore -q .claude/hooks/na/L000.sh 2>/dev/null; then
  if git -C "$DEST" ls-files --error-unmatch .claude/hooks/na >/dev/null 2>&1; then
    echo "  gitignore  .claude/ is ignored but the hooks are tracked: existing hooks are shared,"
    echo "             new ones will be dropped by 'git add'. To share them, replace the"
    echo "             .claude/ line in .gitignore with:"
  else
    echo "  gitignore  .claude/ is ignored in this repo, so the hooks, state.json and skill"
    echo "             stay on this machine and are NOT shared through git. LESSONS.md still is."
    echo "             To share the hooks too, replace the .claude/ line in .gitignore with:"
  fi
  CLAUDE_PROJECT_DIR="$DEST" "$PY" "$DEST/.claude/never-again/na" _gitignore --advice | sed 's/^/               /'
fi

# --- static hosts -------------------------------------------------------------
# If the repo root is deployed as-is, /LESSONS.md and /.claude/ are URLs. The
# host does not matter; the tell is a site at the root. Quiet when the usual
# ignore file already excludes them.
ROOT_SITE=""
for tell in index.html CNAME vercel.json netlify.toml firebase.json; do
  [ -f "$DEST/$tell" ] && ROOT_SITE="$tell" && break
done
if [ -n "$ROOT_SITE" ] && ! { [ -f "$DEST/.vercelignore" ] && grep -q "LESSONS.md" "$DEST/.vercelignore" && grep -q "^\.claude" "$DEST/.vercelignore"; }; then
  echo "  hosting    $ROOT_SITE at the root: if this directory is deployed as a site, /LESSONS.md,"
  echo "             /CLAUDE.md and /.claude/ (hooks, settings, state) become public URLs."
  echo "             Exclude them (.vercelignore or the equivalent) or publish a subdirectory."
fi

cat <<'EOF'

Done. LESSONS.md and the hooks are meant to be committed — they are team
knowledge. Only fires.log, the verified manifests and CLAUDE.md.bak stay local.

Next: fix a bug, then tell Claude "never again".

Stats:  .claude/never-again/na          (PowerShell: .claude\never-again\na.cmd)
Handy:  alias na=".claude/never-again/na"
EOF
