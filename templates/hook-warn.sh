#!/usr/bin/env bash
# never-again hook template
#
# Copy to .claude/hooks/na/<id>.sh, fill in ID, RULE, TRIGGER and CHECK.
# Mode (warn / block / retired) is read from state.json at run time, so a hook
# is promoted, demoted or retired without editing this file.
#
# The same file runs under Claude Code (PreToolUse) and under git (pre-commit,
# through .claude/hooks/na/pre-commit). na-lib.sh handles both.
#
# Rules for the CHECK section:
#   * Look at na_changed_files, not the whole tree. A commit-time hook that
#     scans every file in the repo is slow on every commit forever.
#   * Keep it under a second. A hook people wait on is a hook people remove.
#   * If satisfying the rule means something must have RUN (a test, a boot,
#     a build), run it here when it is stale. Do not test a stamp that another
#     command writes: PreToolUse sees the state from before the tool call, so
#     `run-the-check && git commit` in one command would fire every time.
#   * Self-test with NA_DRY_RUN=1 so test runs do not land in fires.log.
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/na-lib.sh"

ID="L000"                       # <-- lesson id
RULE="one-line rule text"       # <-- shown when this fires
TRIGGER="commit"                # commit | any
WATCH=""                        # e.g. ".css .html": only run when such a file changed

na_begin "$ID" "$TRIGGER"       # sets NA_ROOT, NA_PY, NA_CMD, NA_FILE; exits if not our trigger

# --- CHECK ------------------------------------------------------------------
# Set VIOLATION=1 and DETAIL when the mistake is about to happen.

VIOLATION=0
DETAIL=""

# example: flag a pattern in the files this commit would carry
# while IFS= read -r f; do
#   [ -f "$NA_ROOT/$f" ] || continue
#   if grep -nE 'rm -rf' "$NA_ROOT/$f" >/dev/null; then VIOLATION=1; DETAIL="$DETAIL $f"; fi
# done < <(na_changed_files .sh .bash)
#
# If the check is Python, hand it the files as ARGUMENTS. Its stdin carries the
# script, so a list piped into it is silently lost:
# mapfile -t FILES < <(na_changed_files .html .css)
# [ "${#FILES[@]}" -eq 0 ] && exit 0
# DETAIL="$("$NA_PY" - "$NA_ROOT" "${FILES[@]}" 2>/dev/null <<'PYEOF' || true
# import sys, os
# root, files = sys.argv[1], sys.argv[2:]
# ...print the hits, one string...
# PYEOF
# )"
# [ -n "$DETAIL" ] && VIOLATION=1

# ----------------------------------------------------------------------------

[ "$VIOLATION" -eq 0 ] && exit 0
na_fire "$RULE${DETAIL:+  [$DETAIL]}"
