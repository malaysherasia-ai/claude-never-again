#!/usr/bin/env bash
# never-again — runs after a git commit tool call under Claude Code, or
# under Codex, Gemini CLI, Copilot or Antigravity with --agent NAME.
# Registered by `na _register` on the after-tool event. Installed as
# .claude/hooks/na/_after.sh.
#
# A warn-mode hook cannot see what the person chose at the prompt. This can:
# if the tool call ran at all, the person proceeded past the warning. Any fire
# still pending for this call is marked "proceeded". A fire that never reaches
# here is settled as "declined" the next time anything looks at the log.
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/na-lib.sh"

NA_AGENT="${NA_AGENT:-}"
while [ $# -gt 0 ]; do
  case "$1" in
    --agent) NA_AGENT="${2:-}"; shift ;;
    --agent=*) NA_AGENT="${1#--agent=}" ;;
  esac
  shift
done

NA_PY="$(na_python)" || exit 0
NA_CMD=""; NA_FILE=""; NA_TOOL_USE_ID=""; NA_CWD=""
eval "$(na_payload_vars "$(cat)")"
na_root_from "$NA_CWD"

# Claude Code's `if: Bash(git commit *)` filter keeps this to commits. The
# other agents have no such filter, so the command text decides here.
[ -z "$NA_CMD" ] || na_is_commit "$NA_CMD" || exit 0

NA_ROOT="$(na_native_path "${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}")"
NA_CLI="$NA_ROOT/.claude/never-again/na"
[ -f "$NA_CLI" ] || exit 0

if [ -n "$NA_TOOL_USE_ID" ]; then
  "$NA_PY" "$NA_CLI" _proceeded --tool-use-id "$NA_TOOL_USE_ID" >/dev/null 2>&1
else
  "$NA_PY" "$NA_CLI" _proceeded >/dev/null 2>&1
fi

# The commit is done, so this is the one place a network request costs
# nobody a wait: at most once a day, ask GitHub for the newest release. The
# answer is cached; the next commit's dispatcher names it. Off with
# "updates": "off" in state.json.
[ -n "${NA_DRY_RUN:-}" ] || "$NA_PY" "$NA_CLI" _check-update >/dev/null 2>&1
exit 0
