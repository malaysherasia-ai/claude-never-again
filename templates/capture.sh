#!/usr/bin/env bash
# never-again capture check. Installed as .claude/hooks/na/_capture.sh and
# run on every commit: by the dispatcher under Claude Code and the other
# agents, and by .claude/hooks/na/commit-msg from git itself, which is the
# first moment git shows the message.
#
# The one step of never-again that ran on a reminder was the first one:
# noticing that a fix just happened and filing the lesson. A line in
# CLAUDE.md asked for it, and a line in CLAUDE.md is what this tool exists
# to replace. A field run showed the cost: four real lessons sat in a repo
# until someone typed a prompt asking for them. So this check asks, at the
# one moment every agent passes through. A commit whose message says it is
# a fix, carrying no lesson, with no `na none` since the last commit, gets
# a warning that names the skill. It does not decide what the lesson is.
#
# "capture" in state.json: "warn" (the default), "block", or "off".
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/na-lib.sh"

na_begin "capture" "commit"
[ -f "$NA_CLI" ] || exit 0
NA_LABEL="asks"

# Not a commit of its own: a merge's message names a branch whose commits
# already answered, and an amend re-asks about a commit that was asked.
if [ "$NA_SOURCE" = "git" ]; then
  [ -n "${NA_MSG_FILE:-}" ] && [ -f "$NA_MSG_FILE" ] || exit 0   # pre-commit has no message
  [ -f "$(git -C "$NA_ROOT" rev-parse --git-path MERGE_HEAD 2>/dev/null)" ] && exit 0
else
  case " $NA_CMD " in *" --amend "*|*" --amend="*) exit 0 ;; esac
fi

# One interpreter start: the mode, and the message only when it looks like
# a fix. From git the message file is read the way git will, without the
# comment lines and nothing below the scissors line `git commit -v` adds.
if [ "$NA_SOURCE" = "git" ]; then
  CC="$(git -C "$NA_ROOT" config --get core.commentChar 2>/dev/null)"; CC="${CC:-#}"; [ "$CC" = auto ] && CC="#"
  OUT="$("$NA_PY" "$NA_CLI" _capture --file "$NA_MSG_FILE" --comment-char "$CC" 2>/dev/null)"
else
  OUT="$("$NA_PY" "$NA_CLI" _capture --cmd "$NA_CMD" 2>/dev/null)"
fi
OUT="${OUT//$'\r'/}"
NA_MODE="${OUT%%$'\n'*}"; MSG="${OUT#*$'\n'}"
[ "$NA_MODE" = "off" ] && exit 0
[ -n "$MSG" ] && [ "$MSG" != "$OUT" ] || exit 0

# An amend from git keeps the message it had; that commit was asked already.
if [ "$NA_SOURCE" = "git" ] && [ "$(git -C "$NA_ROOT" log -1 --format=%B 2>/dev/null | tr -s '[:space:]' ' ' | sed 's/ $//')" = "$MSG" ]; then
  exit 0
fi

# A lesson is being filed with it: the archive entry, the rule line or a hook
# script. Any one of them is the answer this check wants. Not state.json: it
# changes for other reasons too (a setting, an agent), and an edit to it left
# uncommitted would silence every fix after it.
if na_changed_files | grep -qE '(^|/)LESSONS\.md$|^\.claude/never-again/archive/|^\.claude/hooks/na/L[0-9]+\.sh$'; then
  exit 0
fi

# Or the person said there is nothing to learn: `na none` records HEAD, and
# the mark holds until the commit lands. In the same command as the commit,
# PreToolUse cannot see the file yet, so the command text counts too.
NONE="$NA_ROOT/.claude/never-again/.capture-none"
if [ -f "$NONE" ]; then
  HEAD_NOW="$(git -C "$NA_ROOT" rev-parse --verify -q HEAD 2>/dev/null)"; HEAD_NOW="${HEAD_NOW:-initial}"
  [ "$(head -n 1 "$NONE" | tr -d '\r')" = "$HEAD_NOW" ] && exit 0
fi
if [ "$NA_SOURCE" != "git" ] && [[ "$NA_CMD" =~ (^|[\;\&\|[:space:]/])na[[:space:]]+none([[:space:]]|$) ]]; then
  exit 0
fi

SHORT="$(printf '%s' "$MSG" | cut -c1-72)"
na_fire "this commit looks like a fix ($SHORT) and files no lesson. Use the never-again skill to capture what went wrong, or run .claude/never-again/na none if there is nothing to learn"
