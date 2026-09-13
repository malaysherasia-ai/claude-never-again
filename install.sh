#!/usr/bin/env bash
# never-again installer — safe to run repeatedly.
#
#   ./install.sh [target-repo]   (defaults to the current directory)

set -euo pipefail

PY="${NA_PYTHON:-$(command -v python3 || command -v python)}"

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEST="$(cd "${1:-$PWD}" && pwd)"

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
cp "$SRC/templates/hook-warn.sh" "$DEST/.claude/never-again/hook-template.sh"
echo "  cli        .claude/never-again/na"

# --- LESSONS.md -------------------------------------------------------------
if [ -f "$DEST/LESSONS.md" ]; then
  echo "  lessons    LESSONS.md already exists — left untouched"
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
  "$PY" - "$CLAUDE" "$BLOCK" <<'PY'
import re, sys
path, block = sys.argv[1], sys.argv[2]
text = open(path).read()
new = open(block).read().strip()
text = re.sub(
    r"<!-- BEGIN never-again -->.*?<!-- END never-again -->",
    new, text, flags=re.S)
open(path, "w").write(text)
PY
  echo "  claude.md  existing block updated (backup at CLAUDE.md.bak)"
else
  cp "$CLAUDE" "$CLAUDE.bak"
  { echo; cat "$BLOCK"; } >>"$CLAUDE"
  echo "  claude.md  block appended (backup at CLAUDE.md.bak)"
fi

# --- .gitignore -------------------------------------------------------------
GI="$DEST/.gitignore"
if ! { [ -f "$GI" ] && grep -q "never-again/fires.log" "$GI"; }; then
  { echo; echo "# never-again (local only)"
    echo ".claude/never-again/fires.log"
    echo ".claude/never-again/.last-boot"; } >>"$GI"
  echo "  gitignore  local state ignored"
fi

cat <<'EOF'

Done. LESSONS.md and the hooks are meant to be committed — they are team
knowledge. Only fires.log is local.

Next: fix a bug, then tell Claude "never again".

Stats:  .claude/never-again/na
Handy:  alias na=".claude/never-again/na"
EOF
