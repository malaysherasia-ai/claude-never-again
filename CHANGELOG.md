# Changelog

All notable changes to never-again are recorded here.

## [Unreleased]

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
