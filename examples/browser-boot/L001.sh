#!/usr/bin/env bash
# never-again L001 — boot the build in a real browser before committing.
# Register: PreToolUse, matcher "Bash", if "Bash(git commit *)"
set -uo pipefail

PY="${NA_PYTHON:-$(command -v python3 || command -v python)}"

ID="L001"
RULE="Boot the build in a real browser before committing (run .claude/hooks/na/L001-mark-boot.sh)"

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
