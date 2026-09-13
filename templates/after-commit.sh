#!/usr/bin/env bash
# never-again — runs after a git commit tool call under Claude Code.
# Registered by install.sh on PostToolUse and PostToolUseFailure for
# Bash(git commit *). Installed as .claude/hooks/na/_after.sh.
#
# A warn-mode hook cannot see what the person chose at the prompt. This can:
# if the tool call ran at all, the person proceeded past the warning. Any fire
# still pending for this call is marked "proceeded". A fire that never reaches
# here is settled as "declined" the next time anything looks at the log.
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/na-lib.sh"

NA_ROOT="$(na_native_path "${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}")"
NA_CLI="$NA_ROOT/.claude/never-again/na"
[ -f "$NA_CLI" ] || exit 0
PY="$(na_python)" || exit 0

TOOL_USE_ID="$("$PY" -c 'import json,sys
try: print(json.load(sys.stdin).get("tool_use_id",""))
except Exception: print("")' 2>/dev/null || true)"

if [ -n "$TOOL_USE_ID" ]; then
  "$PY" "$NA_CLI" _proceeded --tool-use-id "$TOOL_USE_ID" >/dev/null 2>&1
else
  "$PY" "$NA_CLI" _proceeded >/dev/null 2>&1
fi
exit 0
