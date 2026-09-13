#!/usr/bin/env bash
# never-again L001 — boot the build in a real browser before committing.
# Register: PreToolUse, matcher "Bash", if "Bash(git commit *)"
set -uo pipefail

ID="L001"
RULE="Boot the build in a real browser before committing (run .claude/hooks/na/L001-mark-boot.sh)"

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
if ! PY="$(na_python)"; then
  # There is no interpreter left to build JSON with, so hand-write it. The tool
  # call still proceeds, but a silently dead hook is exactly the failure this
  # project exists to prevent, so say so where the user will see it.
  printf '{"systemMessage":"never-again: no working python found; hook %s did not run. Install Python 3.7+ or set NA_PYTHON."}\n' "$ID"
  exit 0
fi

ROOT="${CLAUDE_PROJECT_DIR:-$(pwd)}"
STATE="$ROOT/.claude/never-again/state.json"
LOG="$ROOT/.claude/never-again/fires.log"
STAMP="$ROOT/.claude/never-again/.last-boot"

PAYLOAD="$(cat)"
CMD="$("$PY" -c 'import json,sys; print(json.load(sys.stdin).get("tool_input",{}).get("command",""))' <<<"$PAYLOAD" 2>/dev/null || true)"

case "$CMD" in *"git commit"*) ;; *) exit 0 ;; esac

VIOLATION=0
if [ ! -f "$STAMP" ]; then
  VIOLATION=1
else
  NEWEST="$(find "$ROOT/src" -type f \( -name '*.js' -o -name '*.html' -o -name '*.ts' \) \
            -newer "$STAMP" -print -quit 2>/dev/null || true)"
  [ -n "$NEWEST" ] && VIOLATION=1
fi
[ "$VIOLATION" -eq 0 ] && exit 0

MODE="warn"
if [ -f "$STATE" ]; then
  MODE="$("$PY" -c 'import json,sys
try: print(json.load(open(sys.argv[1]))["lessons"][sys.argv[2]]["mode"])
except Exception: print("warn")' "$STATE" "$ID" 2>/dev/null || echo warn)"
fi

case "$MODE" in
  warn)  DECISION="ask";  LABEL="would block" ;;
  block) DECISION="deny"; LABEL="blocked" ;;
  *)     exit 0 ;;
esac

mkdir -p "$(dirname "$LOG")"
printf '%s\t%s\t%s\n' "$(date -u +%FT%TZ)" "$ID" "$MODE" >>"$LOG"

"$PY" - "$DECISION" "never-again $ID $LABEL: $RULE" <<'PY'
import json, sys
print(json.dumps({"hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": sys.argv[1],
    "permissionDecisionReason": sys.argv[2]}}))
PY
exit 0
