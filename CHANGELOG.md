# Changelog

All notable changes to never-again are recorded here.

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
