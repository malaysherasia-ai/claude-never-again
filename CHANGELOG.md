# Changelog

All notable changes to never-again are recorded here.

## [1.9.0] — 2026-09-24

A hook proves itself through fires. A rule line proves nothing on its own,
and nothing in the tool ever asked whether one was still earning its place
on every turn. Memory tools decay by a clock; this release decays by
evidence, and spends the agent's tokens at the moments that matter (filing,
grading, reviewing) so the per-turn block can stay small.

### Added

- **`na review`**: every proposal the record supports, on one page,
  counted and never applied. Stale lessons, rules that say the same thing,
  hooks ready to promote, warned-past fires nobody graded, hooks graded
  wrong twice or more, and the cost line. The skill acts on it item by
  item; retiring and promoting stay the person's word.
- **`na stale [--commits N]`**: lessons with no trace in the last N
  commits (default 50): no fire, no grade, no mention of the id in a commit
  message, no change to the archive entry. A lesson younger than the window
  is not judged.
- **`na dup "text"`** and **`na dup L017`**: existing rules with the same
  content words. The skill runs it before filing a rule line and sharpens
  the existing rule instead of adding a second.
- **Grading handed back.** After a commit goes past a warning, the
  after-commit hook returns one system message naming the ids; the agent
  that read the reason and made the diff grades them once with `na ok` or
  `na wrong`, or leaves them. A proceeded fire counted for nothing until
  graded, and almost none were.
- **The skill spends tokens at filing.** Read the code path that failed,
  name the input, ask whether the first cause is the cause, write the rule
  at the altitude of the next case. Filed once, read forever: the cheap
  place to be thorough.
- **Nothing already written down goes to waste.** `na import` now also
  finds Claude Code's memory for the project (`~/.claude/projects/<slug>/
  memory/*.md`, the feedback and facts the person already gave an agent)
  and the rules folders of Cursor, Windsurf, Cline, Roo, Copilot, Kiro,
  Junie and Gemini; front matter is not counted as notes. `na` and `na
  review` name the files not yet imported until they are. The skill
  writes an import ledger in the archive, one line per note with what
  became of it, so a skipped note keeps its reason instead of vanishing.

### Fixed

- `na` read git's output through the locale's code page, cp1252 on
  Windows, so a commit message with an em dash crashed the first `na
  review` on this repo. Every git call now decodes UTF-8 with replacement.
  Filed as L007, a warn hook in this repo that checks every changed Python
  file for a text-mode subprocess call with no encoding.

## [1.8.0] — 2026-09-23

An Antigravity session ran on a repo that was a release behind and never
noticed. The release nudge had been delivered twice: as a hook answer the
IDE never asks for, and as one line on the stderr of a `git commit` that
succeeded, in a terminal nobody reads. Both are reminders. The agent's own
proposal was a third reminder, a rule in `AGENTS.md` to read the logs; the
same file already tells it to file lessons, and it files them when
prompted. The fix is the one this tool is built on: a notice an agent must
act on is a stopped command. Filed here as L006.

### Added

- **`"updates": "block"`** in `state.json`: when the once-a-day check has
  found a newer release, the next commit is refused, from every agent's
  hook and from git's own pre-commit, with the one command that clears it.
  A stopped commit is a fired call in `calls.log`; the nudge never was.
- **`na upgrade --later`**: now is not the time. Commits go ahead until
  tomorrow or until a newer release than the deferred one appears; then the
  stop is back. Retrying the commit unchanged does not get past it.
- **Antigravity repos get `"block"` at install.** The IDE has never been
  seen calling the hook, so the git side is the only channel, and the line
  there is invisible. Set once, when the agent joins the repo; a value the
  person changes afterwards stands. `na` says which mode is on and whether
  a deferral is running. The skill says what to do when a commit is
  stopped for this reason.

## [1.7.0] — 2026-09-23

From the sixth field run, a client site built with Antigravity, and the
first real catch: a warn-mode hook found staging URLs in a homepage schema
at commit time. Three things around that catch were wrong. The agent's
own write-up said the hook had "blocked" a commit that had landed and
named itself as a caller when every call had come from git. The catch
was logged as a clean commit in `calls.log`. And eight older copies of
the same mistake stayed in the tree, because a hook only ever looks at
what a commit changes.

### Added

- **`na report`**: the stats as a Markdown page, counted from `state.json`,
  `LESSONS.md`, `fires.log` and `calls.log`. Every lesson with its record,
  every hook's fires and grades, who called the hook and how often, which
  registered agents never did, and what each column means. Hand this over
  instead of a summary written from memory. The skill now says so.
- **`na sweep L017`**: run one hook's check over every tracked file, once,
  and print the hits; nothing is recorded and no fire is logged. A verify
  hook's sweep runs its command by hand. `NA_ALL=1 bash L017.sh` does the
  same without the CLI. The skill asks for a sweep right after a hook is
  written; the hook template says why.

### Fixed

- A warn fire under git was written to `calls.log` as `clean`. The
  dispatcher took the hook's exit code as the verdict, and a warn under git
  exits 0 so the commit can go ahead. It now takes what the hook printed as
  the verdict, the same test the Claude Code branch uses. `fires.log` and
  `na` were right all along; only the call line was wrong.

## [1.6.0] — 2026-09-21

From the fifth field run, on a site built with Antigravity: four real
lessons sat in the repo until someone typed a prompt asking for them. The
one step of never-again that still ran on a reminder was the first one,
noticing that a fix just happened. A line in `CLAUDE.md` asked the agent to
invoke the skill, and a line in `CLAUDE.md` is what this tool exists to
replace.

### Added

- **The capture check.** Before a commit whose message says it is a fix
  (`fix`, `bug`, `revert`, `regression`, `broken` and the like) and that
  carries no lesson file, the agent is asked, in the same shape as a
  warn-mode hook: file the lesson with the skill, or say there is nothing
  to learn. A commit that mentions a typo is left alone. The check runs
  from the dispatcher under every agent, and from git's own `commit-msg`
  hook, which is the first moment git shows the message, so a commit from
  a terminal or from an agent whose hook never ran meets it too. One
  question per commit: git stays quiet after the agent's hook already asked
  about the same tree, a merge is not asked (its commits already were),
  and neither is an amend. Under git the message is read the way git
  reads it: no comment lines, nothing below the scissors line that
  `git commit -v` adds.
- **`na none [why]`** marks the next commit as nothing to learn. The mark
  is HEAD, so it clears once the commit lands and cannot silence the next
  fix. In the same command as the commit, the command text counts, since
  the hook cannot see the file yet.
- **`"capture"` in `state.json`**: `"warn"` (the default, also when the key
  is missing), `"block"` to refuse such a commit, `"off"` to turn the check
  off. `na` shows the nudges on their own line; they never count toward a
  streak or the prevented total.
- A `commit-msg` stub next to the `pre-commit` one. The installer writes
  it, uninstall removes it, the README's by-hand snippet includes it.

## [1.5.0] — 2026-09-18

From the fourth Antigravity run, which also settled that the Antigravity
IDE on that Windows machine runs no PreToolUse hook at all: a canary hook
never fired either. That one is Google's; the git side guards there. But
the same run showed a bug of ours: PowerShell 5.1 strips the quotes off a
path it hands to a native program, so `cd "C:/…"` arrived in pieces. Any
agent that spawns hooks through PowerShell on Windows, Copilot among them,
would have run nothing.

### Changed

- **Agent entries run a launcher instead of carrying a path.** The
  installer puts `~/.never-again/launch` outside every repo; each entry is
  `bash -c "test -f ~/.never-again/launch && exec bash ~/.never-again/launch --agent X; exit 0"`.
  No quote, no `$(…)`, no machine path inside, so it survives cmd,
  PowerShell 5.1, a direct spawn and a Unix shell alike, and a committed
  hook file stays the same on every machine. The launcher finds the repo
  from the payload's working directory, with the process directory as the
  fallback. A missing launcher exits 0 from the entry itself, so an agent
  that fails closed on hook errors is never locked out. Entries from
  earlier releases are rewritten in place.
- Uninstall lists the launcher as kept, since other repos on the machine
  share it.
- On Windows CI the Copilot powershell entry is now run by PowerShell 5.1
  itself, with a payload on stdin, and must answer. That run found one more
  thing: PowerShell 5.1 puts a byte-order mark in front of what it pipes,
  which made the payload unreadable. A leading mark is now ignored.

## [1.4.1] — 2026-09-18

From the third Antigravity run: the IDE runs a hook with `.agents/` as its
working directory, so a repo-relative script path found nothing and the
hook failed silently.

### Fixed

- **No agent entry depends on the working directory any more.** Each one
  is `bash -c "cd <git root> && exec bash .claude/hooks/na/… --agent …"`,
  with the root found by `git rev-parse --show-toplevel`, which works from
  any directory inside the checkout. The quoting is the same for cmd,
  PowerShell, a direct spawn and a Unix shell; Copilot's powershell field
  uses PowerShell's own escape. Existing entries are rewritten in place on
  the next install or `na upgrade`. The tests now run each entry's exact
  command from `.agents/` and from a nested directory.

## [1.4.0] — 2026-09-18

The first `calls.log` from the field showed a commit that only git's side
saw. The commit was `git add … && git commit …`, and Claude Code's `if:
Bash(git commit *)` filter matches only a command that begins with `git
commit`. So the prompt before the commit never ran.

### Changed

- **No `if` filter on the Claude Code entries.** The dispatcher and the
  after-commit hook now run on every Bash call and decide from the command
  text, which they already did. A call whose payload holds no `commit`
  exits before any interpreter starts, so the ordinary call costs a shell
  start and nothing more.
- **Entries an earlier release wrote lose the filter in place** on the
  next install or `na upgrade`.
- The README's by-hand snippet now includes the dispatcher entry it had
  been missing.

## [1.3.1] — 2026-09-18

### Fixed

- **The hosting warning ignored a `.vercelignore` written with leading
  slashes** (`/.claude/`), so a repo that had already excluded everything
  was warned on every install.
- **`calls.log` no longer names an agent for a commit git saw.** The git
  side does not know who committed; the column says `-` there.

## [1.3.0] — 2026-09-17

Releases are frequent now, and a repo that nobody upgrades stays on the
release it was installed with. This makes the newer one visible.

### Added

- **A once-a-day release check, after a commit.** The after-commit hook
  asks GitHub for the newest release, at most once a day, never on the
  commit path, and caches the answer in `.claude/never-again/.update-check`
  (local, gitignored). The next commit's dispatcher and `na` itself then say
  one line: *never-again 1.4.0 is out: na upgrade*. Nothing is installed
  for you. `"updates": "off"` in `state.json` stops the check; new installs
  get `"updates": "check"`.
- `na _check-update [--cached]` (internal) does the check; `NA_UPDATE_URL`
  points it elsewhere, which is how the tests cover it without GitHub.

### Changed

- The README says what the tool sends and when: two requests to GitHub,
  both about releases, one of them daily and switchable off.

## [1.2.2] — 2026-09-17

From the second Antigravity run: the 1.2.1 installer left the old entry in
place, and the hook still never ran.

### Fixed

- **An entry of ours that an older release wrote is now rewritten** when
  its command differs, for every agent. Before, "already registered" meant
  "left as it was".
- **Windows entries name Git's `bash.exe` by its full path.** A process an
  agent spawns on Windows has WSL's bash on PATH or none at all, so a bare
  `bash` ran nothing. Copilot's file carries both a bash and a powershell
  form, since it has a field for each.

### Added

- **`.claude/never-again/calls.log`**: one line per commit the dispatcher
  saw, with the agent's name and whether anything fired. Local and
  gitignored. It answers the question the field reports could not: did the
  agent call the hook at all?

## [1.2.1] — 2026-09-17

From the first Antigravity run on a real site: the git side fired, the
dry run answered, Antigravity itself never called the hook.

### Fixed

- **Antigravity's answer shape** now follows the IDE's own docs:
  `decision` (`allow`, `deny`, `ask`) with `reason`. The `allow_tool` and
  `deny_reason` keys from the CLI write-ups are still sent alongside. A warn
  is now a real prompt there, not a note on stderr.
- **Antigravity's working directory** sits inside the tool arguments
  (`toolCall.args.Cwd`); the dispatcher reads it there, so the repo is
  found from any working directory.
- **The hook entry is workspace-relative** (`bash .claude/hooks/na/dispatch
  --agent antigravity`), as the IDE docs show, so `.agents/hooks.json` is no
  longer tied to one machine and can be committed.
- The installer tells you to restart Antigravity after registering.

## [1.2.0] — 2026-09-17

Releases are frequent now, and every project moves by re-running the
installer. This makes that one command.

### Added

- **`na upgrade`** fetches the newest release from GitHub and runs its
  installer in this repo. `--check` only reports. `--yes` skips the prompt.
  `--from DIR|TARBALL` installs from a local copy, which is also how the
  tests cover it without the network. It refuses to move backwards and
  unpacks nothing outside its own temp folder.
- The README no longer says "no network calls"; it says which one there is.

## [1.1.0] — 2026-09-17

The same hooks under Codex, Gemini CLI, GitHub Copilot and Google
Antigravity. Prompted by an Antigravity session that said it could not run
the hooks and would rebuild them in its own framework; it did not have to.

### Added

- **`--agent codex|gemini|copilot|antigravity`** on the installer. It writes
  the dispatcher and after-commit entries into that agent's hook file,
  merged and never replaced; puts the rules block into the file that agent
  reads (`AGENTS.md`, `GEMINI.md`, `.github/copilot-instructions.md`); and
  copies the skill into its skills folder. Agents whose folders are already
  in the repo are registered without the flag. The choice is kept in
  `state.json` under `agents`, so a re-run and a clone keep it.
- **The dispatcher and `_after.sh` take `--agent NAME`.** They read all five
  payload shapes, find the repo from the payload's `cwd` when
  `CLAUDE_PROJECT_DIR` is not set, and answer in the caller's dialect: Codex
  gets `additionalContext` for a warn since it has no "ask"; Gemini gets a
  `systemMessage`; Copilot gets a top-level `permissionDecision`;
  Antigravity gets `allow_tool` and `deny_reason`. Without the flag the
  agent is guessed from the payload.
- **`na _agents`** (internal): the remembered agents, `--add` and `--detect`.
- **`fires.log` records the agent** in the source column: `codex`, `gemini`,
  `copilot`, `antigravity`, alongside `claude` and `git`.
- Uninstall removes the entries, the block and the skill copy for every
  agent, and keeps whatever else those files hold.
- 40 more test assertions, run on all three platforms.

### Changed

- The local-only `.gitignore` block also lists the backups of the other
  rules files. An older block is upgraded in place, as before.
- `na import` no longer lists a file that holds nothing but our own block,
  whichever file it is.
- The hook scripts are unchanged. The fire log columns, `state.json` fields
  and hook stub are as frozen at 1.0.

## [1.0.1] — 2026-09-16

From the first field report: a client site, two days, two false fires, one
real lesson filed minutes after a production bug.

### Fixed

- **A warn was invisible in auto mode.** The harness answered the prompt and
  the person found both fires a day later in the log. A warn now also
  carries a `systemMessage` with the reason, so the model reads it whatever
  the mode and can stop itself. The README says plainly that only block mode
  stops a commit when nobody is watching.
- **Merges ran no hook.** The installer now also writes a `pre-merge-commit`
  stub, and uninstall removes it. Cherry-pick and rebase still run neither
  git hook, and merges on GitHub happen on their server; the README lists
  that edge.
- **`na --help` and `na --version`** are answered instead of parsed as a
  lesson id.
- **`na.cmd` ships with LF endings**, so git stops warning on every add.

### Changed

- The hook template carries the chain guard as a line to uncomment for any
  check that reads repository state.
- The archive entry gets a **What would have gone red** line, taken from the
  field report's best lesson: when the answer is "nothing", the fix belongs
  in the code, not in a new check.
- The repo checks say not to share `.claude/settings.json`, and why.

## [1.0.0] — 2026-09-15

What 1.0 means here: the formats are frozen. The `fires.log` columns, the
`state.json` fields, the five-line hook stub over `na-lib.sh` and
`na-verify.sh`, the one dispatcher entry, and the `LESSONS.md` rule line will
not change without a major version bump. Everything below was built and
tested on three platforms in the run-up; what has not yet happened is a hook
promoted to blocking on a real project, and that is the honest state of it.


### Added

- **Promotion rights in repo config.** `state.json` carries `"promotion"`:
  `"pull-request"` (the default for new installs: `na promote` and
  `na demote` refuse on the default branch of a repository with a remote, so
  the change is reviewed like code), `"anyone"`, or a list of names or
  emails matched against the git identity. Never automatic in any mode.
- **`docs/TEAMS.md`.** What travels with git and what stays local, who
  grades, who promotes, a proposal for opt-in shared fire history, a
  proposal for shared packs, and why many hooks need an index rather than a
  database.

### Changed

- **One dispatcher instead of one entry per hook.** `.claude/hooks/na/dispatch`
  is the only PreToolUse entry. It reads the payload once, resolves Python
  once, lists the changed files once, reads every hook's mode in one call
  (`na _index`), runs only the hooks whose `TRIGGER` and `WATCH` match the
  change, and merges their answers into one decision: deny beats ask,
  reasons joined. The git runner hands the commit to the same dispatcher.
  Filing a hook no longer touches `settings.json`; `na _register` installs
  the dispatcher entry and drops the per-hook entries earlier releases
  wrote. `na index` shows what will run. On a repo with four hooks this
  takes per-commit hook cost from four setups to one; with two hundred it
  stays one.
- Hook scripts may declare `WATCH=".css .html"`; the dispatcher skips them
  when no such file changed.

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
