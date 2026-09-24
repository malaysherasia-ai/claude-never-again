#!/usr/bin/env bash
# never-again hook L007: a subprocess read as text names its encoding.
#
# Python's text mode decodes a child's output with the locale's code page,
# which on Windows is cp1252. Git prints commit messages and paths as UTF-8,
# so the first em dash or accented letter in a message raised
# UnicodeDecodeError inside subprocess's reader thread and `na review`
# crashed on the tool's own history. The installer had the same bug on
# CLAUDE.md in 0.1.0. Every text-mode subprocess call passes
# encoding="utf-8", errors="replace" on the same line as text=True.
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/na-lib.sh"

ID="L007"
RULE="a subprocess read as text passes encoding=\"utf-8\", errors=\"replace\" on the same line as text=True: Windows decodes with cp1252 otherwise"
TRIGGER="commit"
WATCH=""                        # scripts/na has no extension

na_begin "$ID" "$TRIGGER"

# --- CHECK ------------------------------------------------------------------
VIOLATION=0
DETAIL=""

while IFS= read -r f; do
  [ -f "$NA_ROOT/$f" ] || continue
  case "$f" in *.py|scripts/na|.claude/never-again/na|templates/*) ;; *) continue ;; esac
  # A text-mode subprocess call with no encoding on the same line.
  if grep -nE '(text|universal_newlines)=True' "$NA_ROOT/$f" | grep -vq 'encoding='; then
    VIOLATION=1; DETAIL="$DETAIL $f"
  fi
done < <(na_changed_files)
# ----------------------------------------------------------------------------

[ "$VIOLATION" -eq 1 ] || exit 0
na_fire "$RULE:$DETAIL"
