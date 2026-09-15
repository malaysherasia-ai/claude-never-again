#!/usr/bin/env bash
# never-again shared hook library. Installed at .claude/hooks/na/na-lib.sh and
# sourced by every hook, so the parts that are easy to get wrong live once.
#
#   source "$(dirname "$0")/na-lib.sh"
#   na_begin "L017" "commit"        # id, trigger
#   ... set VIOLATION=1 and a reason ...
#   na_fire "$REASON"               # or: exit 0
#
# Two ways a hook gets run, one code path:
#   Claude Code   PreToolUse, JSON payload on stdin, JSON decision on stdout.
#   git           pre-commit via .claude/hooks/na/pre-commit, NA_EVENT=git,
#                 no stdin; warn prints to stderr and allows, block exits 1.
#
# Environment:
#   NA_PYTHON     interpreter to use instead of probing python3/python/py
#   NA_EVENT      "git" when run from the git pre-commit runner
#   NA_DRY_RUN=1  decide, but write nothing to fires.log (for self-tests)

# Resolve a Python that actually runs. On Windows `command -v python3` finds
# the Microsoft Store stub, which exists, is on PATH, and exits 49 having run
# nothing. Existence is never the test; running a statement is.
na_python() {
  local c
  for c in "${NA_PYTHON:-}" python3 python py; do
    [ -n "$c" ] || continue
    if "$c" -c 'import sys' >/dev/null 2>&1; then
      command -v "$c"
      return 0
    fi
  done
  return 1
}

# na_native_path PATH — Git Bash reports /c/Users/...; Python and Node on
# Windows cannot open that. Return a path every runtime here understands.
na_native_path() {
  case "$(uname -s 2>/dev/null)" in
    MINGW*|MSYS*|CYGWIN*) command -v cygpath >/dev/null 2>&1 && cygpath -m "$1" && return 0 ;;
  esac
  printf '%s\n' "$1"
}

# na_env — the environment every hook needs: NA_ROOT, NA_STATE, NA_CLI,
# NA_SOURCE and NA_PY. Returns 1 when no interpreter runs. na_begin calls
# this; a hook that runs without a payload (a manual --run) calls it directly.
na_env() {
  NA_ROOT="$(na_native_path "${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}")"
  NA_STATE="$NA_ROOT/.claude/never-again/state.json"
  NA_CLI="$NA_ROOT/.claude/never-again/na"
  NA_SOURCE="claude"
  [ "${NA_EVENT:-}" = "git" ] && NA_SOURCE="git"
  if [ -n "${NA_PY:-}" ] && "$NA_PY" -c 'import sys' >/dev/null 2>&1; then
    return 0
  fi
  NA_PY="$(na_python)"
}

# na_begin ID TRIGGER
# Sets NA_ID plus everything na_env sets, then NA_CMD, NA_FILE, NA_TOOL_USE_ID.
# Exits 0 (silently, never blocking) when this hook has nothing to do: the
# command is not the trigger, or no interpreter is available.
na_begin() {
  NA_ID="$1"
  NA_TRIGGER="${2:-commit}"
  if ! na_env; then
    if [ "$NA_SOURCE" = "git" ]; then
      echo "never-again: no working python found; hook $NA_ID did not run. Install Python 3.7+ or set NA_PYTHON." >&2
    else
      # No interpreter to build JSON with, so hand-write it. The call proceeds,
      # but a silently dead hook is the failure this project exists to prevent.
      printf '{"systemMessage":"never-again: no working python found; hook %s did not run. Install Python 3.7+ or set NA_PYTHON."}\n' "$NA_ID"
    fi
    exit 0
  fi

  NA_CMD=""; NA_FILE=""; NA_TOOL_USE_ID=""
  if [ "$NA_SOURCE" = "claude" ]; then
    NA_PAYLOAD="$(cat)"
    eval "$(printf '%s' "$NA_PAYLOAD" | "$NA_PY" -c '
import json, sys, shlex
try:
    d = json.load(sys.stdin)
except Exception:
    d = {}
ti = d.get("tool_input") or {}
print("NA_CMD=%s" % shlex.quote(str(ti.get("command", ""))))
print("NA_FILE=%s" % shlex.quote(str(ti.get("file_path", ""))))
print("NA_TOOL_USE_ID=%s" % shlex.quote(str(d.get("tool_use_id", ""))))
' 2>/dev/null || true)"
    # The `if` filter in settings.json is the first gate, but it has been seen
    # to let unrelated commands through. Decide from the command text too, and
    # do it properly: a commit is a `git ... commit` segment, not the substring.
    if [ "$NA_TRIGGER" = "commit" ] && ! na_is_commit "$NA_CMD"; then
      exit 0
    fi
  fi
}

# na_is_commit CMD — true when CMD contains a git commit as a command segment.
# Accepts global options between git and commit (-C dir, -c k=v, --no-pager),
# extra whitespace, and chaining (&&, ;, |). Rejects an echo of the words.
na_is_commit() {
  local re='(^|[;&|(]|then |do |exec |sudo )[[:space:]]*git([[:space:]]+(-[cC][[:space:]]+[^[:space:]]+|--?[A-Za-z-]+(=[^[:space:]]+)?))*[[:space:]]+commit([[:space:]]|$)'
  [[ "$1" =~ $re ]]
}

# na_changed_files [ext ...] — the files a commit could carry, one per line.
# From git: what is staged. From Claude Code: everything different from HEAD,
# staged or not, because `git add -A && git commit` is one tool call and at
# PreToolUse time nothing is staged yet. Never the whole tree.
na_changed_files() {
  local list
  if [ "$NA_SOURCE" = "git" ]; then
    list="$(git -C "$NA_ROOT" diff --cached --name-only --diff-filter=ACMR 2>/dev/null)"
  else
    list="$(git -C "$NA_ROOT" status --porcelain=v1 -uall 2>/dev/null \
      | awk '$1 !~ /D/ { sub(/^.. /, ""); sub(/.* -> /, ""); print }')"
  fi
  [ -z "$list" ] && return 0
  if [ $# -eq 0 ]; then printf '%s\n' "$list"; return 0; fi
  local ext pat=""
  for ext in "$@"; do pat="${pat:+$pat|}${ext//./\\.}"; done
  printf '%s\n' "$list" | grep -E "($pat)\$" || true
}

# na_lesson_field FIELD [DEFAULT] — one top-level field of this lesson's
# record in state.json, or DEFAULT when the file, the lesson or the field is
# missing. The one place hooks read their own record from.
na_lesson_field() {
  local v
  v="$("$NA_PY" -c 'import json,sys
try:
    x = json.load(open(sys.argv[1], encoding="utf-8"))["lessons"][sys.argv[2]][sys.argv[3]]
    print(x if isinstance(x, str) else json.dumps(x))
except Exception:
    print(sys.argv[4])' "$NA_STATE" "$NA_ID" "$1" "${2:-}" 2>/dev/null)" || v="${2:-}"
  printf '%s' "$v"
}

# na_mode — the hook's mode from state.json: warn, block, or retired.
na_mode() {
  na_lesson_field mode warn
}

# na_pending — under git, after Claude Code's PreToolUse hook already asked
# about this same commit: the person has answered. Records that they went
# ahead and returns 0, so the caller can stay quiet instead of asking twice.
na_pending() {
  [ "$NA_SOURCE" = "git" ] || return 1
  [ -z "${NA_DRY_RUN:-}" ] && [ -f "$NA_CLI" ] || return 1
  "$NA_PY" "$NA_CLI" _proceeded --id "$NA_ID" --if-pending >/dev/null 2>&1
}

# na_fire REASON — the mistake is about to happen. Records the fire and emits
# the decision for whichever runner we are under, then exits.
na_fire() {
  local reason="$1" mode decision label
  mode="$(na_mode)"
  case "$mode" in
    warn)  decision="ask";  label="would block" ;;
    block) decision="deny"; label="blocked" ;;
    *)     exit 0 ;;   # retired or unknown: silent
  esac

  if [ "$NA_SOURCE" = "git" ]; then
    # The git runner is the second look at a commit Claude Code already asked
    # about; record the answer and stay quiet rather than warn twice.
    na_pending && exit 0
    if [ -z "${NA_DRY_RUN:-}" ] && [ -f "$NA_CLI" ]; then
      "$NA_PY" "$NA_CLI" _fired "$NA_ID" "$mode" git "" >/dev/null 2>&1
    fi
    echo "never-again $NA_ID $label: $reason" >&2
    [ "$mode" = "block" ] && exit 1
    exit 0
  fi

  if [ -z "${NA_DRY_RUN:-}" ] && [ -f "$NA_CLI" ]; then
    "$NA_PY" "$NA_CLI" _fired "$NA_ID" "$mode" claude "$NA_TOOL_USE_ID" >/dev/null 2>&1
  fi

  "$NA_PY" -c '
import json, sys
print(json.dumps({"hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": sys.argv[1],
    "permissionDecisionReason": sys.argv[2]}}))
' "$decision" "never-again $NA_ID $label: $reason"
  exit 0
}
