# Changelog

All notable changes to never-again are recorded here.

## [0.2.0] — 2026-09-13

Found by auditing the first day of real use: nine warn-mode fires, none of
which caught an unverified commit, none graded, and a per-commit hook cost of
fifteen seconds. The fixes below are structural, and every one carries a test.

### Changed

- **Hooks that need something to have run now run it.** The browser-boot
  example tested a stamp written by a separate command. `PreToolUse` sees the
  repository as it was before the tool call, so `mark-boot && git commit` in
  one command fired every time, and six of the first nine real fires were
  that. Each was approved within seconds, which is how a prompt stops meaning
  anything. `L001.sh` now runs the boot itself when the tree has changed and
  fires only when the boot fails. The skill says so for every hook of that
  shape, and the settings snippet carries a `timeout` for it.
- **Commit hooks also run from git.** A hook registered only on Claude Code's
  Bash tool did nothing for a commit made from a terminal, another tool, or
  `git -C . commit`. `install.sh` now drops a two-line stub into
  `.git/hooks/pre-commit` (only if you had none; otherwise it tells you the
  line to add) that hands the commit to `.claude/hooks/na/pre-commit`, which
  runs every commit-trigger hook with `NA_EVENT=git`. Warn prints and allows;
  block refuses. When Claude Code already asked about the same commit, the
  git pass stays silent and records the answer instead of asking twice.
- **The outcome of a warn prompt is recorded.** Grading was a counter with no
  fire behind it: five `na ok` calls on an empty log made a hook "ready to
  promote", and in practice nobody ran it once. Now the hook logs the fire as
  *pending*; `_after.sh`, registered on `PostToolUse` at install, marks it
  *proceeded* if the call ran; a fire that never reaches that point is settled
  as *declined*. Declined counts as correct. `na ok` / `na wrong` grade the
  latest real fire and refuse when there is none. `na` shows fires, denied,
  declined, proceeded, ok, wrong and the streak per hook. The `fires` and
  `correct` fields in `state.json` are no longer written.
- **Hooks decide from the command, not a substring.** `git -C . commit`,
  `git  commit` and `git add -A && git commit` now count; `echo "git commit"`
  does not. The `if` filter in `settings.json` was seen to spawn hooks on
  unrelated commands, so the script decides too.
- **Hooks look at changed files, not the whole tree.** `na_changed_files`
  lists what the commit could carry. A whole-tree scan with a backtracking
  regex cost 11 seconds per commit on a 60 KB page.
- **`na retire` now deregisters the hook** from `settings.json` and moves its
  scripts to the archive. Before, a retired hook still spawned and ran its
  full check on every commit, then exited silently.
- **One library for every hook.** `templates/na-lib.sh`, installed at
  `.claude/hooks/na/na-lib.sh`, holds the interpreter resolver, payload
  parsing, the commit matcher, mode lookup, fire logging and the decision.
  Hooks written from the template contain only their check. This closes
  issue #1 (the resolver had been copied into four files and drifted).

### Fixed

- **Reinstall crashed on non-English text in `CLAUDE.md`.** The block merge
  opened files with Python's default encoding, cp1252 on Windows, which
  cannot decode byte 0x81 (the second byte of "Ł", among others). Explicit
  UTF-8 throughout.
- **Self-tests polluted the fire log.** Piping a fake payload through a hook
  appended a real fire, and the log was hand-edited four times in one session
  to remove them, once deleting real entries. `NA_DRY_RUN=1` decides without
  writing.
- **`na` could not be run from PowerShell or cmd.** `na.cmd` next to it can.
- **Package-level `LESSONS.md` was not counted on Windows** when the drive
  letter case differed between the working directory and the project root.

### Added

- **`tests/hooks.sh`.** 44 assertions: a hook built from the template through
  Claude Code's payload and a real `git commit`, the commit matcher, dry run,
  outcome recording, grading, block and warn from git, the no-double-fire
  rule, retire, and reinstall with a non-cp1252 byte. Both test scripts now
  refuse to run inside the source checkout.

- **An uninstall path.** `na uninstall`, or `bash install.sh --uninstall .`.
  The tool asks a stranger to run a shell script against their repository and
  then writes a skill, hooks, a CLI, a rule file and a block in `CLAUDE.md`.
  Not documenting a way back out was a reason on its own not to try it.

  It prints what it will do and waits for a yes; `--yes` skips the prompt, and
  a closed stdin removes nothing. It strips only the marked block from
  `CLAUDE.md`, drops only the hook entries pointing at `.claude/hooks/na/` from
  `settings.json` rather than replacing the file, removes only the section it
  added to `.gitignore`, and keeps `LESSONS.md` on the grounds that the rules
  are yours and still read fine without the tool.

  The implementation lives in `na` rather than `install.sh`, because
  `install.sh` is in the clone and people delete the clone; `na` is in the
  repo. `install.sh --uninstall` delegates to it, so the two cannot drift over
  which files belong to never-again.

- **`tests/uninstall.sh`.** Asserts the above against a fixture repo that
  already has its own `CLAUDE.md` sections, its own hook in `settings.json`,
  its own `.gitignore` entries and its own `LESSONS.md` rule. 25 assertions.
  The property under test is that uninstall removes only what it owns.

## [0.1.2] — 2026-09-13

Found while building the launch site against this tool, and while auditing that
site before launch.

### Fixed

- **L001 fired on files that had not changed.** The browser-boot hook compared
  file mtimes against an empty stamp file, which answers "was anything
  touched?" rather than "is anything different?". Restoring a file from a
  backup, checking out the same revision, or a formatter rewriting a file
  byte-for-byte all bumped the mtime and all fired the hook over a no-op. The
  stamp is now a manifest of sha256 hashes written only when the boot passes,
  and the hook fires on a changed hash, a file that was never booted, or one
  that has gone. It also names what differs instead of only saying something
  did. This matters more than it sounds: it is the flagship lesson, and a hook
  that blocks a commit over a no-op on day one is the one that gets the whole
  tool uninstalled.
- **`na` counted every lesson as a hook.** `stats()` took the whole lessons
  dict as the hook set, which was correct only while every lesson carried a
  script. The first rule-only lesson made it report one hook too many. It now
  counts `form == "hook"` and reports rule-only lessons separately.

### Changed

- **One install command.** The README told you to run `./install.sh`, the
  website told you to run `bash install.sh`, and the two disagreed on
  `--depth 1`. `./install.sh` depends on an executable bit that does not
  survive a ZIP download and is unreliable on Windows checkouts, so `bash` is
  now the documented form everywhere, with an explicit Windows block.
- **The stats block in the README is labelled as sample output.** It shows 38
  fires and roughly 184,000 tokens, which is illustrative output from a mature
  install rather than anything this project has measured. Unlabelled, it read
  as a results claim, and the real block-mode fire count is zero.
- **Independence from Anthropic stated explicitly** in the README and on the
  website footer.

## [0.1.1] — 2026-09-13

Found by using never-again to build its own website. The first lesson filed
with the tool was the browser-boot hook, and proving that hook actually fired
is what surfaced every bug below — on Windows, the hooks had never run at all.

### Fixed

- **Hooks could never fire on Windows.** `command -v python3` resolves to the
  Microsoft Store stub, which is on `PATH`, exits 49 and runs nothing. The
  failure was swallowed and every hook exited 0, so enforcement was silently
  absent on the whole platform. The resolver now tries `$NA_PYTHON`, `python3`,
  `python` and `py` in order and accepts only an interpreter that executes
  `import sys` and exits 0 — existence is never the test. Fixed in
  `install.sh`, `templates/hook-warn.sh` and `examples/browser-boot/L001.sh`.
- **A hook with no interpreter now says so.** Previously it exited 0 in
  silence, which is the exact failure this project exists to prevent. It now
  prints a hand-written JSON `systemMessage` — no interpreter required — naming
  the hook that did not run. The tool call still proceeds; the failure is
  visible.
- **`na` would not start on Windows,** for the same stub reason via its
  `#!/usr/bin/env python3` shebang. It is now a `sh`/Python polyglot that
  re-execs under the first working interpreter, with usage text moved to an
  explicit `USAGE` constant since the shim occupies the docstring slot.
- **`na` crashed printing its own stats.** Windows consoles default to cp1252,
  which cannot encode the box-drawing bars and em dashes in its output
  (`UnicodeEncodeError`). `stdout`, `stderr` and every file read and write are
  now explicitly UTF-8.

### Requirements

- `na` requires **Python 3.7+** (`sys.stdout.reconfigure`).
- The `examples/browser-boot` boot check requires **Node 22+**, or a boot check
  of your own.

## [0.1.0] — 2026-09-12

First release. Hooks over reminders.
