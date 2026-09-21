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

NA_MODE="$("$NA_PY" -c 'import json, sys
try:
    m = json.load(open(sys.argv[1], encoding="utf-8")).get("capture", "warn")
except Exception:
    m = "warn"
print(m if m in ("warn", "block", "off") else "warn")' "$NA_STATE" 2>/dev/null || echo warn)"
NA_MODE="${NA_MODE//$'\r'/}"
[ "$NA_MODE" = "off" ] && exit 0

# The message. From git it is the file commit-msg hands over; the pre-commit
# runner has none, and stays silent. From an agent it is the -m text in the
# command; a commit that opens an editor is silent here and met by git.
if [ "$NA_SOURCE" = "git" ]; then
  [ -n "${NA_MSG_FILE:-}" ] && [ -f "$NA_MSG_FILE" ] || exit 0
  MSG="$(grep -v '^#' "$NA_MSG_FILE" 2>/dev/null | head -c 4000)"
else
  MSG="$("$NA_PY" - "$NA_CMD" <<'PYEOF' 2>/dev/null || true
import re, sys
cmd = sys.argv[1]
m = re.search(r'(^|[;&|(]|then |do |exec |sudo )\s*git(\s+(-[cC]\s+\S+|--?[A-Za-z-]+(=\S+)?))*\s+commit(?=\s|$)', cmd)
if not m:
    sys.exit(0)
rest = cmd[m.end():]
# The commit's own arguments end at the first chain operator outside quotes,
# so a `&& git push origin fix/thing` after it is not read as the message.
out, q, i = [], None, 0
while i < len(rest):
    c = rest[i]
    if q:
        if c == "\\" and q == '"':
            out.append(rest[i:i + 2]); i += 2; continue
        if c == q:
            q = None
        out.append(c)
    elif c in ('"', "'"):
        q = c; out.append(c)
    elif c == "\\":
        out.append(rest[i:i + 2]); i += 2; continue
    elif rest.startswith(("&&", "||"), i) or c in ";|":
        break
    else:
        out.append(c)
    i += 1
args = "".join(out)
parts = re.findall(r'(?:^|\s)(?:-[a-zA-Z]*m|--message)[=\s]+("(?:[^"\\]|\\.)*"|\'[^\']*\'|\S+)', args)
print(" ".join(parts))
PYEOF
)"
fi
[ -n "$MSG" ] || exit 0

# A fix, by its own account. "typo" is the one word that says "not worth a
# lesson" on its own; everything else is for the person to decide.
if ! "$NA_PY" - "$MSG" <<'PYEOF' 2>/dev/null
import re, sys
msg = sys.argv[1]
fix = re.compile(r"\b(fix|fixes|fixed|fixing|bugfix|hotfix|bug|bugs|revert|reverts|reverted|regression|broke|broken|workaround)\b", re.I)
sys.exit(0 if fix.search(msg) and not re.search(r"\btypos?\b", msg, re.I) else 1)
PYEOF
then
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
  HEAD_NOW="$(git -C "$NA_ROOT" rev-parse HEAD 2>/dev/null || echo initial)"
  [ "$(head -n 1 "$NONE" | tr -d '\r')" = "$HEAD_NOW" ] && exit 0
fi
if [ "$NA_SOURCE" != "git" ] && [[ "$NA_CMD" =~ (^|[\;\&\|[:space:]/])na[[:space:]]+none([[:space:]]|$) ]]; then
  exit 0
fi

SHORT="$(printf '%s' "$MSG" | tr '\n\t' '  ' | sed -e 's/^ *//' | cut -c1-72)"
na_fire "this commit looks like a fix ($SHORT) and files no lesson. Use the never-again skill to capture what went wrong, or run .claude/never-again/na none if there is nothing to learn"
