#!/usr/bin/env bash
# never-again L001 — boot the build in a real browser before committing.
# Register: PreToolUse, matcher "Bash", if "Bash(git commit *)", timeout 180.
# Also runs from git's pre-commit through .claude/hooks/na/pre-commit.
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/na-lib.sh"

ID="L001"
RULE="Boot the build in a real browser before committing"
TRIGGER="commit"

na_begin "$ID" "$TRIGGER"

STAMP="$NA_ROOT/.claude/never-again/.last-boot"
MANIFEST="$NA_ROOT/.claude/hooks/na/L001-manifest.py"
BOOT="$NA_ROOT/.claude/hooks/na/L001-mark-boot.sh"

# Fresh: every source file matches what was last booted successfully.
if "$NA_PY" "$MANIFEST" check "$NA_ROOT" "$STAMP" >/dev/null 2>&1; then
  exit 0
fi

# Stale: something differs from the last verified boot. The first version of
# this hook stopped here and asked "did you boot?", which fired every time the
# boot and the commit were chained in one command, because PreToolUse sees the
# tree from before the command runs. So the hook now runs the boot itself.
# A passing boot writes the manifest and the commit goes through silently.
OUT="$(bash "$BOOT" 2>&1)" && exit 0

# The page is broken. Say what failed, not just that something did.
DETAIL="$(printf '%s' "$OUT" | grep -v '^$' | tail -4 | tr '\n' ';' | cut -c1-300)"
na_fire "$RULE  [boot failed: $DETAIL]"
