# never-again

**Your coding agent keeps making the same mistake. Stop writing it a reminder —
take the mistake away.**

`never-again` captures each bug you fix and asks one question: *can this be
enforced instead of remembered?* If it can, it writes a hook that blocks the
wrong path automatically. If it can't, it files one short line. Nothing else.

MIT licensed. Local. No account, no telemetry, no network calls.

**macOS, Linux, WSL** — needs git, bash, Python 3.7+

```bash
git clone --depth 1 https://github.com/malaysherasia-ai/claude-never-again.git
bash claude-never-again/install.sh .
```

**Windows** — needs Git for Windows and Python 3.7+

```powershell
git clone --depth 1 https://github.com/malaysherasia-ai/claude-never-again.git
& "C:\Program Files\Git\bin\bash.exe" claude-never-again/install.sh .
```

Run it with `bash`, not `./install.sh`. The executable bit does not survive a
ZIP download and is unreliable on Windows checkouts; `bash` always works.

**Run it yourself, from a terminal.** Claude Code's auto mode refuses to run
an installer it has not seen before, refuses to edit its own
`.claude/settings.json`, and refuses to write into `.git/hooks/`, even when
you approve. That is Claude Code protecting you, not a bug in either tool.
If you must install from inside Claude Code, turn auto mode off first, or
expect to apply these two pieces by hand afterwards:

```jsonc
// .claude/settings.json — merge into "hooks"; keep everything else
"PostToolUse":        [{ "matcher": "Bash", "hooks": [{ "type": "command", "if": "Bash(git commit *)", "command": "\"$CLAUDE_PROJECT_DIR\"/.claude/hooks/na/_after.sh" }] }],
"PostToolUseFailure": [{ "matcher": "Bash", "hooks": [{ "type": "command", "if": "Bash(git commit *)", "command": "\"$CLAUDE_PROJECT_DIR\"/.claude/hooks/na/_after.sh" }] }]
```

```sh
# .git/hooks/pre-commit — create if you have none; otherwise add the last two lines to yours
#!/bin/sh
r="$(git rev-parse --show-toplevel)/.claude/hooks/na/pre-commit"
[ -f "$r" ] || exit 0
exec "$r" "$@"
```

The same applies to `na`: in auto mode Claude Code may refuse to run it. It
is a stats script; run it from a terminal.

**Three things to check in your repo.** The installer looks for each and says
so, but they are worth knowing in advance:

- If `.gitignore` ignores `.claude/`, the hooks and their modes stay on your
  machine and are not shared through git. `LESSONS.md` still is. The installer
  prints the un-ignore lines to add if you want the hooks shared.
- If the repo root is served as a static site (Vercel, Netlify, GitHub Pages),
  `/LESSONS.md` and `/.claude/` become public URLs, hooks and settings
  included. Add `.claude`, `LESSONS.md` and `CLAUDE.md` to `.vercelignore`,
  publish a subdirectory, or accept that they are readable.
- If the repo already has a `LESSONS.md` somewhere other than the root, in its
  own format, it is left alone: `na` only manages the root file and files
  that carry the tool's marker comment.

---

## Why not just put it in CLAUDE.md?

Because `CLAUDE.md` is advice, and advice has two problems.

It is **paid for on every turn.** A 200-line instructions file is 200 lines of
context in every message you send, forever, whether it is relevant or not.
Prompt caching makes that cheap in money. It does not make it cheap in
attention, and attention is what compliance runs on.

And it is **optional.** The longer a session runs, the more likely an
instruction is drifted past. Plenty of people have written the rule down and
watched the same bug ship anyway.

A hook is neither. It costs one line until it fires. In block mode it returns
a denial the agent cannot talk its way around; in warn mode it asks you, and
records what you answered.

```
             cost per turn     can be ignored
CLAUDE.md      every line           yes
hook            one line             no
```

`never-again` is the bridge between the two: it decides which of your lessons
belongs in which place, and writes the hook for you.

---

## What it actually does

**1. You fix a bug.** Then you say "never again", or Claude notices the
correction itself.

**2. It triages.** Four rungs, first fit wins:

| | | |
|---|---|---|
| Already enforceable | a linter or tsconfig flag covers it | turn that on, file nothing |
| Hook-shaped | describable as "before X, fail if Y" | write a hook |
| Judgement | a script can't make the call | one line in `LESSONS.md` |
| Not worth it | one-off, or already impossible | file nothing |

That fourth row matters. Most tools file everything. This one is allowed to say
no, because every line it writes is rent you pay forever.

**3. The hook starts in warn mode.** Instead of blocking, it raises a
permission prompt with the reason, and you choose. What you chose is recorded
without you doing anything: if the commit went ahead the fire is marked
*proceeded*, if you stopped it is marked *declined*, and a declined fire counts
as correct. Overrule the record when you want to:

```bash
na ok L001        # that fire was right
na wrong L001     # false positive — narrow it, streak resets
```

Grades attach to real fires. After five correct in a row, `na` says so, and
you promote it yourself:

```bash
na promote L001
```

Never automatic. A hook that blocks wrongly on day one gets the whole tool
uninstalled.

**4. It guards every commit, not only Claude's.** The same script runs from
git's own pre-commit hook, so a commit from a terminal, another agent, or a
different tool meets the same rule. Warn mode prints and lets it through;
block mode refuses it.

---

## Before and after

A real one — the bug this tool came out of.

Every button on a page went dead. The cause was a `let` used before its
declaration: a temporal dead zone error that aborts the script at boot, so no
event listener ever attaches. `node --check` passed, because it only parses.

**What most setups do** — add a line to `CLAUDE.md`:

```
Always test in a real browser before shipping.
```

Read on every turn from now until the end of the project. Followed when the
context window is short and the agent is paying attention.

**What `never-again` does** — files this instead:

```
- [web] [hook] Boot the build in a real browser, not `node --check` — when: before commit (L001)
```

...and writes `.claude/hooks/na/L001.sh`, which compares every source file
against the last successful headless boot, runs the boot itself if anything
changed, and refuses the commit only if the page does not boot.

The rule is now unskippable and costs one line to carry. Full worked example in
[`examples/browser-boot/`](examples/browser-boot/).

---

## Stats, counted not generated

The block below is **illustrative sample output from a mature install**, not
results measured by this project. It is here to show the shape of the report.
For what this repository has actually recorded, run `na` in your own checkout.

```
$ na

  never-again
  ----------------------------------------------
  rules           12 across 2 files  (cap 40 per file)
  loaded here     9  (warn above 60)
  hooks           7  (4 blocking, 3 warn)
  hook fires      38

  prevented       23  (19 denied, 4 declined at the prompt)
  warned past     9   (asked, and the person went ahead)
  est. tokens     ~184,000 saved
                  (at 8,000/repeat — edit in state.json)

  per hook        fires  denied  declined  proceeded  ok  wrong  streak
    L001             14      11         2          1   0      0       5
    L004              6       6         0          0   0      0       6
    L009              3       0         2          1   1      0       3

  most-hit
    L001  ████████████████··   14  Boot the build in a real browser
    L004  ███████···········    6  Never read-modify-write settings.json
    L009  ████··············    3  dvh, not vh, for keyboard-adjacent UI

  ready to promote: L009
    na promote L009
```

This is a Python script counting lines in files. **No model is involved**, which
is the point — a tool that spends tokens telling you how many tokens it saved
has argued itself out of existence.

"Prevented" counts block-mode denials plus warn-mode fires where the person
stopped. A single stopped mistake can fire twice if the agent retries, so read
it as an upper bound. "Warned past" is the honest column: prompts that were
approved anyway.

The token figure is an estimate from one constant you control: what a repeated
debug-and-fix cycle costs you. The default of 8,000 is deliberately
conservative. Change it in `state.json`.

**Nothing is sent anywhere.** If you want to share your number, copy it into a
post. There is no phone-home, and there never will be — a tool that reads your
repo has no business opening a socket.

---

## Monorepos and parallel agents

Lessons scope to the nearest `LESSONS.md`. A rule about `packages/api` lives in
`packages/api/LESSONS.md` and costs nothing while you work on the web app.

Parallel agents each append to the file nearest their own working directory, so
two writers never touch one file. Hooks are shared, so the skill re-reads
`state.json` to claim an id and merges into `settings.json` rather than
replacing it.

---

## Two things every hook gets right for you

Hooks source one shared library, `.claude/hooks/na/na-lib.sh`, so the parts
that went wrong in the first release live in one place.

**It decides from the command, not a substring.** `git -C . commit`,
`git  commit` and `git add -A && git commit` all count as a commit.
`echo "git commit"` does not.

**It never asks "did you run X?"** A `PreToolUse` hook sees the repository as
it was before the tool call, so a hook that checks for a stamp fires every time
the stamp is written in the same command as the commit. Six of the first nine
real fires were exactly that. If a rule is "X must have run", the hook runs X
itself when it is stale, and fires only when X fails.

It also looks at the files that changed rather than the whole tree, records
what happened after it fired, and stays out of `fires.log` during self-tests
(`NA_DRY_RUN=1`).

---

## What gets installed

```
LESSONS.md                          the rules Claude reads (small, capped, ordered)
CLAUDE.md                           one marked block appended — never overwritten
.claude/skills/never-again/         the skill
.claude/hooks/na/L###.sh            the enforcement scripts
.claude/hooks/na/na-lib.sh          shared by every hook
.claude/hooks/na/na-verify.sh       the "X must pass before commit" engine, plus na-manifest.py
.claude/hooks/na/_after.sh          records that a warned commit went ahead
.claude/hooks/na/pre-commit         runs commit hooks from git itself
.claude/settings.json               _after.sh registered on PostToolUse — merged, never replaced
.git/hooks/pre-commit               a two-line stub, only if you had none
.claude/never-again/
  ├── na                            the stats CLI  (na.cmd for PowerShell)
  ├── state.json                    lesson index, hook modes
  ├── archive/L###.md               the full story, read only when asked
  ├── verified/                     one manifest per verify hook — local, gitignored
  └── fires.log                     every fire, its outcome and grade — local, gitignored
```

**Already have notes?** Most repositories do: a `CLAUDE.md` full of rules, a
`NOTES.md`, a `docs/lessons.md`, a `.cursorrules`. `na import` lists them,
with how many lines of notes each holds and which were imported before. Tell
Claude once, *"import the existing notes with the never-again skill"*, and
each note goes through the same triage as a fresh bug: the mechanical ones
become hooks in warn mode, the judgement ones become one-liners, the rest are
skipped. The source files are never edited; the tool only remembers which
were imported, so the next `na import` shows only what changed.

**Already have a `LESSONS.md`?** It is left exactly as it is, and Claude keeps
reading it. But notes in your own words are invisible to `na`: not counted,
not capped, not sorted, not enforced. The installer says so when it finds
them. To bring them in, tell Claude once: *"read LESSONS.md and refile each
note through the never-again skill"*. Each note goes through the same triage;
the mechanical ones become hooks, the judgement ones become one-liners, and
the rest are dropped. Your original stays in git history.

**What a fresh clone gets, and what it does not.** `LESSONS.md`, the hook
scripts, `state.json` and the archive travel with git, so a clone has every
rule in the mode the team earned. The wiring does not travel: git never
clones its own hooks folder, and `.claude/settings.json` is only shared if
your `.gitignore` allows it. So after cloning, run the installer once. It is
safe to re-run, changes nothing that already matches, and takes a second.

`install.sh` backs up `CLAUDE.md` before touching it and is safe to re-run.
`LESSONS.md` and the hooks are meant to be committed — they are team knowledge,
and a new hire inherits every scar the team has earned.

---

## Uninstall

```bash
.claude/never-again/na uninstall          # or: bash install.sh --uninstall .
```

It prints exactly what it will do and waits for a yes. Pass `--yes` to skip the
prompt. Anything other than `y` removes nothing, and so does a closed stdin, so
it is safe to pipe.

```
  remove   .claude/skills/never-again/        12 file(s)
  remove   .claude/hooks/na/                  7 file(s)
  remove   .claude/never-again/               9 file(s)
  remove   .git/hooks/pre-commit              git pre-commit stub
  edit     CLAUDE.md                          strip the never-again block, keep the rest
  edit     .claude/settings.json              remove 4 hook entries, keep everything else
  edit     .gitignore                         remove the never-again section
  keep     LESSONS.md                         your rules outlive the tool
```

Four things it will not do. It does not rewrite `CLAUDE.md`, only cuts the
block between the `never-again` markers and leaves the rest of your file alone.
It does not replace `.claude/settings.json`, only drops the hook entries that
point at `.claude/hooks/na/`, so your own hooks and settings stay. It does not
touch a git `pre-commit` hook it did not write. And it does not delete
`LESSONS.md`: those rules are yours, they read perfectly well without the tool
that enforced them, and deleting a stranger's notes is not an uninstaller's
job. Remove it yourself if you want it gone.

Running it twice is fine. The second run has nothing to do and says so.

`tests/uninstall.sh` asserts all of the above against a repo that already has
its own `CLAUDE.md` sections, its own hooks in `settings.json`, its own git
`pre-commit` and its own `.gitignore` entries, because the property worth
testing is not that uninstall deletes things but that it deletes only its own.
`tests/hooks.sh` runs a hook built from the template through both Claude Code's
payload and a real `git commit`, and checks the fire log, the grading, retire,
and reinstall. Run both with `bash tests/hooks.sh && bash tests/uninstall.sh`.

---

## The cap, and why it's a cap

The direction is well supported: compliance falls as the list of simultaneous
instructions grows, and models drop rules quietly rather than refusing.
IFScale (Distyl AI, 2025) measured 20 models on 10 to 500 concurrent
instructions in a report-writing task; even the best reached only 68% at the
top end, and earlier instructions were followed more reliably than later ones.
That task is not coding, and nobody has measured the same curve for rules in a
`CLAUDE.md`. What `never-again` borrows is the direction and the primacy
effect, not a number. The "I wrote the rule down and it ignored it anyway"
experience is real; the exact threshold for your repo is not in any paper.

So `never-again` does three things the research supports and one it doesn't
claim:

- **Capped.** 40 rules per file by default. Not a magic number — it's the
  largest file a person still reads top to bottom. Change `cap` in
  `state.json` if your team disagrees.
- **Ordered.** `na sort` puts the most-fired rules first, because primacy is
  real and free.
- **Scoped.** Rules load per package, not per repo. The number that matters is
  *rules loaded per turn*; `na` reports it as "loaded here" and warns above 60
  (`loadedWarn`). When it warns, split, retire, or promote. Don't raise it.
- **Not claimed:** that 40, or 60, is the right number for you. The evidence
  says fewer and ordered; it doesn't name a threshold. Yours will show up in
  your own fire log.

`na` is short for `.claude/never-again/na` — alias it.

```bash
na sort           # most-fired rules first, in every LESSONS.md
na why L001       # read the full story behind a rule
na retire L001    # drop the line, deregister the hook, keep the archive
na demote L001    # blocking back to warn
na import         # notes files already in the repo, and what was imported
```

On Windows, `.claude\never-again\na.cmd` runs the same thing from PowerShell
or cmd.

---

## Prior art

This stands on two well-established ideas and joins them.

The `lessons.md` pattern — a file the agent writes discoveries into mid-task —
is widely used and well documented. So are Claude Code hooks, where the settled
wisdom is that rules shape behaviour and hooks enforce it.

What has been missing is the step between: deciding which lessons deserve
enforcement, and generating the hook. That is all this does.

## License

MIT.

---

`never-again` is an independent open-source project. Not affiliated with,
endorsed by, or sponsored by Anthropic. Claude and Claude Code are trademarks
of Anthropic, PBC.
