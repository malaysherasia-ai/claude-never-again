#!/usr/bin/env bash
# never-again verify engine. Installed as .claude/hooks/na/na-verify.sh and
# sourced by every verify-shaped hook, which is a five-line stub:
#
#   ID="L017"
#   RULE="the test suite must pass before committing"
#   TRIGGER="commit"
#   source "$(dirname "${BASH_SOURCE[0]}")/na-verify.sh"
#
# The command, the watched files and the skipped directories live in the
# lesson's record in state.json:
#
#   "verify": { "run": "npm test --silent", "watch": [".ts", ".tsx"], "skip": ["dist"] }
#
# Behaviour:
#   fresh    nothing watched has changed since the check last passed -> silent
#   stale    something changed -> the command runs now; a pass is recorded
#            silently, a failure fires with the last lines of output
#   --run    run the command by hand and record a pass (bash L017.sh --run)
#
# It never asks "did you run it?": PreToolUse sees the tree from before the
# tool call, so a stamp written by another command would always look stale.
# Give the settings entry a "timeout" longer than the command takes.
#
# Files are listed by git (tracked plus untracked-not-ignored), so anything in
# .gitignore never counts. A pass is recorded in .claude/never-again/verified/,
# which is local to the machine.

source "$(dirname "${BASH_SOURCE[0]}")/na-lib.sh"

: "${ID:?na-verify.sh: set ID before sourcing}"
: "${RULE:?na-verify.sh: set RULE before sourcing}"
TRIGGER="${TRIGGER:-commit}"

MANUAL=0
[ "${1:-}" = "--run" ] && MANUAL=1

if [ "$MANUAL" -eq 1 ]; then
  na_env || { echo "never-again $ID: no working python found" >&2; exit 1; }
else
  na_begin "$ID" "$TRIGGER"
fi

HELPER="$NA_ROOT/.claude/hooks/na/na-manifest.py"

# One spawn reads the config and compares the tree. First line: RUN=<command>.
RES="$("$NA_PY" "$HELPER" check "$NA_ROOT" "$NA_STATE" "$ID" 2>&1)"; RC=$?
RES="${RES//$'\r'/}"
V_RUN="${RES#RUN=}"; V_RUN="${V_RUN%%$'\n'*}"

if [ "$RC" -ge 2 ]; then
  # Unconfigured or misconfigured. A hook that silently does nothing is the
  # failure this project exists to prevent, so say so where it will be seen.
  MSG="never-again $ID: ${RES#ERROR=}"; MSG="${MSG%%$'\n'*}. Fix the \"verify\" block in state.json."
  if [ "$MANUAL" -eq 1 ] || [ "$NA_SOURCE" = "git" ]; then echo "$MSG" >&2; exit 1; fi
  "$NA_PY" -c 'import json,sys; print(json.dumps({"systemMessage": sys.argv[1]}))' "$MSG"
  exit 0
fi

# Fresh, and not asked to run by hand: nothing to do.
[ "$RC" -eq 0 ] && [ "$MANUAL" -eq 0 ] && exit 0

# Under git after Claude Code already asked about this same commit, the
# person has answered; do not run a long check a second time.
if [ "$MANUAL" -eq 0 ] && [ "$NA_SOURCE" = "git" ] && na_pending; then
  exit 0
fi

# Run the command. Output goes to a file so a chatty suite is never copied
# through a shell variable; the manual path streams it to the terminal.
TMP="$(mktemp 2>/dev/null || echo "${TMPDIR:-/tmp}/na-verify.$$")"
if [ "$MANUAL" -eq 1 ]; then
  (cd "$NA_ROOT" && bash -c "$V_RUN") 2>&1 | tee "$TMP"; PASS=${PIPESTATUS[0]}
else
  (cd "$NA_ROOT" && bash -c "$V_RUN") >"$TMP" 2>&1; PASS=$?
fi

if [ "$PASS" -eq 0 ]; then
  if REC="$("$NA_PY" "$HELPER" commit "$NA_ROOT" "$NA_STATE" "$ID" 2>&1)"; then
    rm -f "$TMP"
    [ "$MANUAL" -eq 1 ] && echo "never-again $ID: check passed, $REC."
    exit 0
  fi
  rm -f "$TMP"
  MSG="never-again $ID: the check passed but the result could not be recorded (${REC%%$'\n'*}). It will run again next commit."
  if [ "$MANUAL" -eq 1 ] || [ "$NA_SOURCE" = "git" ]; then echo "$MSG" >&2; exit 1; fi
  "$NA_PY" -c 'import json,sys; print(json.dumps({"systemMessage": sys.argv[1]}))' "$MSG"
  exit 0
fi

if [ "$MANUAL" -eq 1 ]; then
  rm -f "$TMP"
  echo "never-again $ID: check failed, nothing recorded." >&2
  exit 1
fi
DETAIL="$(grep -v '^$' "$TMP" | tail -4 | tr '\n' ';' | cut -c1-300)"
rm -f "$TMP"
na_fire "$RULE  [$V_RUN failed: $DETAIL]"
