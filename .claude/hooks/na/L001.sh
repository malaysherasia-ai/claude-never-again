#!/usr/bin/env bash
# never-again hook L001: no heredoc inside $(...) in a shell script.
#
# bash 3.2, which macOS still ships, reads the body of a command
# substitution by scanning for the closing paren and honouring quotes, so a
# heredoc with an apostrophe in it (any real Python has one) runs to the end
# of the file: "syntax error: unexpected end of file". The 1.6.0 capture
# check shipped that way and only the macOS CI job caught it. Write the
# heredoc's output to a file or a variable outside the substitution instead.
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/na-lib.sh"

ID="L001"
RULE="no heredoc inside \$(...): bash 3.2 on macOS cannot parse it; capture its output outside the substitution"
TRIGGER="commit"
WATCH=""                        # scripts here have no common extension

na_begin "$ID" "$TRIGGER"

# --- CHECK ------------------------------------------------------------------
VIOLATION=0
DETAIL=""

# A line that opens a substitution and a heredoc together, outside a comment.
PAT='^[^#]*\$\([^)]*<<-?["'"'"']?[A-Za-z_]+'
while IFS= read -r f; do
  [ -f "$NA_ROOT/$f" ] || continue
  case "$f" in *.sh|templates/*|install.sh|scripts/*) ;; *) continue ;; esac
  if grep -qE "$PAT" "$NA_ROOT/$f"; then VIOLATION=1; DETAIL="$DETAIL $f"; fi
done < <(na_changed_files)
# ----------------------------------------------------------------------------

[ "$VIOLATION" -eq 1 ] || exit 0
na_fire "$RULE:$DETAIL"
