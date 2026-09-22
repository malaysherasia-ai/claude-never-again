# Lessons

Rules earned from real bugs in this repo. Read before writing code.

Format: `- [scope] Rule - when: trigger (L###)`
Lines marked `[hook]` are also enforced by a script in `.claude/hooks/na/`.

Cap: 40 rules per file (configurable). At the cap, retire or promote one.
Ordered most-hit first by `na sort` - do not reorder by hand.
The reasoning behind any rule lives in `.claude/never-again/archive/L###.md`.

<!-- rules below - managed by the never-again skill, one line each -->
- [shell] [hook] No heredoc inside $(...): bash 3.2 on macOS cannot parse it; capture its output outside the substitution — when: writing or changing a shell script (L001)
- [tests] grep -c exits 1 on zero matches, so never chain `|| echo 0` after it; test the file, then `|| true` the grep — when: writing a test helper (L002)
- [hooks] Evidence that something happened must be a file that changes for that reason only, never a shared index — when: writing a check that looks for a side effect (L003)
- [hooks] Before a commit-time check ships, walk it through merge, amend, -v, no -m, a custom commentChar and the first commit, and test each — when: writing a pre-commit or commit-msg check (L004)
