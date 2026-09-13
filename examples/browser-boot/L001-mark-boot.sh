#!/usr/bin/env bash
# Companion to L001. Boots the page headlessly; on success writes the stamp
# the hook checks. Wire this to `npm run boot:check` or call it directly.
set -euo pipefail
ROOT="${CLAUDE_PROJECT_DIR:-$(pwd)}"
STAMP="$ROOT/.claude/never-again/.last-boot"

# Replace with your real boot check. It must fail (non-zero) on a broken page.
node "$ROOT/scripts/boot-check.mjs"

mkdir -p "$(dirname "$STAMP")"
touch "$STAMP"
echo "boot ok — stamp written"
