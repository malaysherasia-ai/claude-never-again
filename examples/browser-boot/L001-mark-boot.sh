#!/usr/bin/env bash
# Companion to L001. Boots the page headlessly; on success writes the stamp
# the hook checks. Wire this to `npm run boot:check` or call it directly.
set -euo pipefail
ROOT="${CLAUDE_PROJECT_DIR:-$(pwd)}"
STAMP="$ROOT/.claude/never-again/.last-boot"

# Resolve a Python that actually runs. On Windows `command -v python3` finds
# the Microsoft Store stub, which exits non-zero and would silence this script.
na_python() {
  local c
  for c in "${NA_PYTHON:-}" python3 python py; do
    [ -n "$c" ] || continue
    if "$c" -c 'import sys' >/dev/null 2>&1; then
      command -v "$c"
      return 0
    fi
  done
  return 1
}
if ! PY="$(na_python)"; then
  echo "never-again: no working python found; cannot write the boot manifest." >&2
  exit 1
fi

# Replace with your real boot check. It must fail (non-zero) on a broken page.
node "$ROOT/scripts/boot-check.mjs"

# Record what was booted, not merely when. See L001-manifest.py.
mkdir -p "$(dirname "$STAMP")"
"$PY" "$ROOT/.claude/hooks/na/L001-manifest.py" write "$ROOT" "$STAMP"
echo "boot ok — stamp written"
