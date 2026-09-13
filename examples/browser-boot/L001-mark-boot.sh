#!/usr/bin/env bash
# Companion to L001. Boots the page headlessly; on success writes the manifest
# the hook checks. The hook calls this itself when the tree has changed since
# the last boot, so you rarely need to run it by hand. Wire it to
# `npm run boot:check` if you want it on demand.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/na-lib.sh"
ROOT="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
STAMP="$ROOT/.claude/never-again/.last-boot"

if ! PY="$(na_python)"; then
  echo "never-again: no working python found; cannot write the boot manifest." >&2
  exit 1
fi

# Replace with your real boot check. It must fail (non-zero) on a broken page.
node "$ROOT/scripts/boot-check.mjs"

# Record what was booted, not merely when. See L001-manifest.py.
mkdir -p "$(dirname "$STAMP")"
"$PY" "$ROOT/.claude/hooks/na/L001-manifest.py" write "$ROOT" "$STAMP"
echo "boot ok — manifest written"
