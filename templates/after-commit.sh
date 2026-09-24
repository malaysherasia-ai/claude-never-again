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

NA_PAYLOAD="$(cat)"
# No `if` filter on the entry: leave before any interpreter starts unless
# the payload can hold a commit at all.
case "$NA_PAYLOAD" in *commit*) ;; *) exit 0 ;; esac
NA_PY="$(na_python)" || exit 0
NA_CMD=""; NA_FILE=""; NA_TOOL_USE_ID=""; NA_CWD=""
eval "$(na_payload_vars "$NA_PAYLOAD")"
na_root_from "$NA_CWD"

# The command text decides; no entry carries a filter any more.
[ -z "$NA_CMD" ] || na_is_commit "$NA_CMD" || exit 0

NA_ROOT="$(na_native_path "${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}")"
NA_CLI="$NA_ROOT/.claude/never-again/na"
[ -f "$NA_CLI" ] || exit 0

if [ -n "$NA_TOOL_USE_ID" ]; then
  WENT="$("$NA_PY" "$NA_CLI" _proceeded --tool-use-id "$NA_TOOL_USE_ID" 2>/dev/null)"
else
  WENT="$("$NA_PY" "$NA_CLI" _proceeded 2>/dev/null)"
fi
WENT="${WENT//$'\r'/}"

# A warning that the commit went past counts for nothing until it is
# graded, and the agent that read the reason and made the diff is the one
# who can grade it, now, once. One line back; the skill says what to do
# with it. After a tool call only additionalContext reaches the model (a
# systemMessage goes to the person), so Claude Code and Codex get that;
# Gemini reads a systemMessage. Copilot has no channel after a tool, and
# Antigravity has never been seen running this. A commit that failed
# (this hook also runs on PostToolUseFailure) landed nothing to grade.
case "$NA_PAYLOAD" in *PostToolUseFailure*) WENT="" ;; esac
if [ -n "$WENT" ]; then
  IDS="$(printf '%s' "$WENT" | tr '\n' ' ')"; IDS="${IDS% }"
  MSG="never-again: $IDS warned and this commit went ahead. Grade it from the reason and the diff, once: .claude/never-again/na ok L### if the warning was right, na wrong L### if it was a false positive; leave it if unsure."
  case "${NA_AGENT:-claude}" in
    copilot|antigravity) ;;
    gemini) printf '{"systemMessage":"%s"}\n' "$MSG" ;;
    *) printf '{"hookSpecificOutput":{"hookEventName":"PostToolUse","additionalContext":"%s"}}\n' "$MSG" ;;
  esac
fi

# The commit is done, so this is the one place a network request costs
# nobody a wait: at most once a day, ask GitHub for the newest release. The
# answer is cached; the next commit's dispatcher names it. Off with
# "updates": "off" in state.json.
[ -n "${NA_DRY_RUN:-}" ] || "$NA_PY" "$NA_CLI" _check-update >/dev/null 2>&1
exit 0
