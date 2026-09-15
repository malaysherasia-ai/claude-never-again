#!/usr/bin/env bash
# never-again verify-shaped hook template
#
# For rules of the shape "X must have passed before commit": a test suite, a
# smoke command, a build, a browser boot. Copy to .claude/hooks/na/<id>.sh,
# set ID and RULE, and put the configuration in state.json under the lesson:
#
#   "L017": {
#     "form": "hook", "mode": "warn", "hook": ".claude/hooks/na/L017.sh",
#     "verify": {
#       "run":   "npm test --silent",          # any command; non-zero = failed
#       "watch": [".ts", ".tsx", ".json"],     # files whose change makes it stale
#       "skip":  ["dist", "coverage"]          # directories never watched
#     }
#   }
#
# How it behaves:
#   fresh   every watched file matches what was verified   -> silent
#   stale   something changed                             -> runs "run" now;
#           passes -> writes the manifest, silent; fails -> fires with the tail
#
# It never asks "did you run it?". PreToolUse sees the tree from before the
# tool call, so testing a stamp written by another command fires every time.
#
# Run the check by hand and record it:   bash .claude/hooks/na/<id>.sh --run
# Give the settings entry a "timeout" longer than the check takes.
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/na-lib.sh"

ID="L000"                       # <-- lesson id
RULE="the check must pass before committing"   # <-- shown when this fires
TRIGGER="commit"

# --- manual run: verify now, record on success, no payload ----------------
if [ "${1:-}" = "--run" ]; then
  NA_EVENT=manual
fi

if [ "${NA_EVENT:-}" = "manual" ]; then
  NA_ROOT="$(na_native_path "${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}")"
  NA_PY="$(na_python)" || { echo "never-again: no working python" >&2; exit 1; }
  NA_STATE="$NA_ROOT/.claude/never-again/state.json"
else
  na_begin "$ID" "$TRIGGER"
fi

MANIFEST="$NA_ROOT/.claude/never-again/verified/$ID"
HELPER="$NA_ROOT/.claude/hooks/na/na-manifest.py"

# Configuration from state.json. Defaults keep an unconfigured hook harmless.
eval "$("$NA_PY" - "$NA_STATE" "$ID" <<'PYEOF' 2>/dev/null || true
import json, shlex, sys
try:
    v = json.load(open(sys.argv[1], encoding="utf-8"))["lessons"][sys.argv[2]].get("verify") or {}
except Exception:
    v = {}
print("V_RUN=%s"   % shlex.quote(str(v.get("run", ""))))
print("V_WATCH=%s" % shlex.quote(",".join(v.get("watch", []))))
print("V_SKIP=%s"  % shlex.quote(",".join(v.get("skip", []))))
PYEOF
)"
if [ -z "${V_RUN:-}" ] || [ -z "${V_WATCH:-}" ]; then
  [ "${NA_EVENT:-}" = "manual" ] && echo "never-again $ID: no verify.run / verify.watch in state.json" >&2
  exit 0
fi

verify_now() {
  (cd "$NA_ROOT" && bash -c "$V_RUN") 2>&1
}

if [ "${NA_EVENT:-}" = "manual" ]; then
  if OUT="$(verify_now)"; then
    "$NA_PY" "$HELPER" write "$NA_ROOT" "$MANIFEST" "$V_WATCH" "$V_SKIP" >/dev/null
    echo "never-again $ID: check passed, recorded."
    exit 0
  fi
  printf '%s\n' "$OUT" | tail -20 >&2
  echo "never-again $ID: check failed, nothing recorded." >&2
  exit 1
fi

# Fresh: nothing watched has changed since the check last passed.
if "$NA_PY" "$HELPER" check "$NA_ROOT" "$MANIFEST" "$V_WATCH" "$V_SKIP" >/dev/null 2>&1; then
  exit 0
fi

# Stale: run the check now. Passing means the commit proceeds in silence.
if OUT="$(verify_now)"; then
  "$NA_PY" "$HELPER" write "$NA_ROOT" "$MANIFEST" "$V_WATCH" "$V_SKIP" >/dev/null 2>&1
  exit 0
fi

DETAIL="$(printf '%s' "$OUT" | grep -v '^$' | tail -4 | tr '\n' ';' | cut -c1-300)"
na_fire "$RULE  [$V_RUN failed: $DETAIL]"
