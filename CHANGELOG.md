# Changelog

All notable changes to never-again are recorded here.

## [0.4.0] — 2026-09-15

Two days of fixes from the first installs on repositories that were not ours,
and a seven-angle review of everything since 0.2.0. Re-run the installer: it
registers every hook from state.json, so settings.json no longer needs to
be shared.

### Fixed

From the first import run on a client repository (Windows 11):

- **The installer registers every hook from `state.json`** (`na _register`),
  so `.claude/settings.json` never has to be shared: it is often the home of
  other tooling and machine-specific paths, and sharing it broke a clone in
  the first client repo. A fresh clone runs the installer once and every
  hook is wired, with its timeout for verify hooks. The README states the
  rule: rules, hooks and state travel with git; the wiring does not.

- **An emoji in the commit message blinded every hook on Windows.** The
  command extractor printed through a cp1252 pipe and crashed, so the hook
  saw an empty command. Every Python the library spawns now writes UTF-8.
- **`na import --mark` never matched the listing for `CLAUDE.md`.** The
  listing hashed the file without the tool's own block, the mark hashed it
  raw. One function now feeds both.
- **A self-test set off the live hook.** The fake payload mentioned
  "git commit" inside quotes, and the command matcher counted it. Quoted
  text is now ignored (a commit hidden in quotes still meets the git
  runner), and the skill feeds self-test payloads from a file.
- **A branch check fired one command early** on `git checkout -b x && git
  commit`. `na_is_chain` and a skill rule: a check about repository state
  defers to the git runner when the command is a chain.

### Added

- **`na import`: lessons the repo already learned.** Finds the notes files a
  repository already holds (a `CLAUDE.md` full of rules, `NOTES.md`,
  `docs/lessons.md`, `.cursorrules` and the like), counts their lines of
  notes, and remembers which were imported and whether they changed since.
  The installer lists them. The skill has an import procedure: split each
  file into notes, run every note through the triage ladder, file what
  survives, never edit the source, mark the file. A repo's accumulated
  lessons count from day one instead of waiting for each bug to recur.

From a review of everything since 0.2.0, seven angles, before anything else
is built on it.

### Fixed

- **The un-ignore advice could not work.** Git never re-includes a path under
  an excluded directory, so `!.claude/hooks/na/` after `.claude/` did nothing.
  The installer now says to replace the `.claude/` line and prints a chain
  that re-includes each parent and excludes its other contents. The test
  applies the advice and asks git.
- **A declined warning could let an unverified commit through.** Under git,
  the verify engine skipped its command whenever any fire for the lesson was
  still pending, including one the person had declined an hour earlier, and
  marked it "proceeded". Fires now carry a fingerprint of the tree they were
  raised on; the skip applies only to the same tree, and pending fires are
  settled before the match.
- **A same-length edit with a preserved mtime passed as fresh.** Files
  modified within two seconds of the manifest are always re-read, the way
  git treats a racily-clean index.
- **Changing the command did not re-run it.** The manifest records a digest
  of `verify.run`; a changed rule counts as never verified. Files the command
  itself names are always watched.
- **A file deleted but not yet `git rm`ed kept the tree stale forever.**
  Files absent from disk are no longer reported unreadable.
- **A Python traceback in the helper read as "stale".** Internal errors exit
  with their own code and message.
- **Git-mode notices no longer block.** A misconfigured hook or a pass that
  could not be recorded prints and lets the commit through, as warn mode
  promises; Claude Code gets a systemMessage; `--run` exits 1.
- **`.gitignore` is round-tripped byte for byte.** Non-UTF-8 bytes and CRLF
  endings survive; a failure to update it is reported instead of swallowed,
  and `na uninstall` reads it the same way.
- **The git stub says when its runner is missing** instead of passing every
  commit in silence, and the installer upgrades a stub only when it is
  exactly one it wrote, so lines a person added survive.
- **A hook copied from the 0.2 example still writes `.last-boot`**, so that
  line stays in the local-only block.

### Changed

- **A lesson records its file.** `state.json` entries carry `"file"`, and
  `na` manages a package `LESSONS.md` because a lesson names it, not only
  because it carries the marker. The marker check reads the header only, and
  the tree is walked once per run.
- **The static-host warning is host-neutral**: a site at the root
  (`index.html`, `CNAME`, or a Vercel, Netlify or Firebase config) triggers
  one message.
- Under the git runner the interpreter is resolved once, not once per hook;
  `check` prints the mode so a retired hook never runs its command; the
  `.next` sidecar is gone; the existing-`LESSONS.md` report and the stub body
  each live in one place.

## [0.3.0] — 2026-09-15

The hook format changed: verify-shaped hooks are five-line stubs over a shared
engine, and the gitignore block moved under `na`. Re-run the installer.

### Added

- **Verify-shaped hooks, configurable per lesson.** For rules of the shape
  "X must pass before commit": a test suite, a smoke command, a build, a
  browser boot. A hook is now five lines (`ID`, `RULE`, `TRIGGER`, a
  `source` of `na-verify.sh`); the command, the watched extensions and the
  skipped paths live in the lesson's `verify` block in `state.json`, so the
  same engine serves a web page, a Python package or a Go service. It stays
  silent while nothing watched has changed, runs the command itself when
  something has, records a pass under `.claude/never-again/verified/` (local,
  gitignored), and fires only on a failure. `--run` verifies by hand.
  Watched files come from `git ls-files`, so nothing in `.gitignore` counts;
  each manifest line carries size and mtime, so an unchanged file is not
  re-read; a passing run reuses the digests the check just computed. A
  missing, malformed or unwritable configuration is reported, never
  swallowed. Under git after Claude Code already asked about the same
  commit, the command is not run a second time. The browser-boot example is
  that five-line hook plus a `verify` block; its private helpers are gone.
- **`.gitignore` block owned by `na`.** One list in `na _gitignore`; the
  installer writes it fresh or upgrades an older one wholesale, uninstall
  removes it by the same shape, and the un-ignore advice for repos that
  ignore `.claude/` comes from the same list. The advice now also tells a
  repo whose hooks are force-added that new hooks will be dropped.
- **`na retire` removes the lesson's verify manifest.**

From the first install into a repository that was not ours: Windows 11, an
existing large `CLAUDE.md`, a gitignored `.claude/` used by other tooling, a
`docs/LESSONS.md` in a different format, and Vercel serving the repo root.

### Fixed

- **`na` adopted any `LESSONS.md` in the tree.** It walked the whole repo and
  counted a project's own `docs/LESSONS.md`, and `na sort` or `na retire`
  would have written to it had a line ever matched. Now only the root file
  and files carrying the template's marker comment are managed. The skill
  creates package-level files from `.claude/never-again/lessons-template.md`
  so they carry it.
- **A hand-deleted `.claude/` failed every commit.** The git stub exec'd a
  runner that no longer existed. It now exits 0 when the runner is missing.
- **`CLAUDE.md.bak` was left for `git add -A` to commit.** It is in the
  local-only block of `.gitignore` now; an older install gets the line added.

### Added, earlier in the cycle

- **The installer reports three repo conditions** it cannot fix for you: a
  gitignored `.claude/` (hooks stay local; it prints the un-ignore lines), a
  `vercel.json` or `netlify.toml` (a root `LESSONS.md` is a public URL), and,
  from before, a pre-existing `LESSONS.md` in your own words.
- **README: install from a terminal.** Claude Code's auto mode refuses to
  run the installer, to edit its own `settings.json`, and to write into
  `.git/hooks/`, even when approved. The README says so and carries the two
  snippets to apply by hand if you install from inside Claude Code anyway.
- Eleven more assertions in `tests/hooks.sh`.

### Changed

- **An existing `LESSONS.md` is reported, not just kept.** The installer
  always left a pre-existing file alone, but said so in one quiet line. Notes
  written in a person's own words are invisible to `na`: not counted, not
  capped, not sorted, not enforced. The installer now counts them, says so,
  and gives the one sentence to tell Claude to refile them through the skill.
  Four assertions in `tests/hooks.sh`.

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
