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

---

## Why not just put it in CLAUDE.md?

Because `CLAUDE.md` is advice, and advice has two problems.

It is **paid for on every turn.** A 200-line instructions file is 200 lines of
context in every message you send, forever, whether it is relevant or not.

And it is **optional.** The longer a session runs, the more likely an
instruction is drifted past. Plenty of people have written the rule down and
watched the same bug ship anyway.

A hook is neither. It costs nothing until it fires, and when it fires it
returns a denial the agent cannot talk its way around.

```
             cost per turn     can be ignored
CLAUDE.md      every turn           yes
hook              zero               no
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
permission prompt with the reason, and you choose. Each time, you record
whether it was right:

```bash
na ok L001        # it caught a real one
na wrong L001     # false positive — narrow it, count resets
```

After five correct fires you promote it yourself:

```bash
na promote L001
```

Never automatic. A hook that blocks wrongly on day one gets the whole tool
uninstalled.

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

...and writes `.claude/hooks/na/L001.sh`, which checks whether any source file
is newer than the last successful headless boot and refuses the commit if so.

The rule is now unskippable and costs nothing to carry. Full worked example in
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

  prevented       23 block-mode fires
  est. tokens     ~184,000 saved
                  (at 8,000/repeat — edit in state.json)

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

"Prevented" counts fires in block mode. A single stopped mistake can fire
twice if the agent retries, so read it as an upper bound.

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

## What gets installed

```
LESSONS.md                          the rules Claude reads (small, capped, ordered)
CLAUDE.md                           one marked block appended — never overwritten
.claude/skills/never-again/         the skill
.claude/hooks/na/L###.sh            the enforcement scripts
.claude/never-again/
  ├── na                            the stats CLI
  ├── state.json                    lesson index, hook modes, fire counts
  ├── archive/L###.md               the full story, read only when asked
  └── fires.log                     local, gitignored
```

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
  remove   .claude/hooks/na/                  4 file(s)
  remove   .claude/never-again/               9 file(s)
  edit     CLAUDE.md                          strip the never-again block, keep the rest
  edit     .claude/settings.json              remove 2 hook entries, keep everything else
  edit     .gitignore                         remove the never-again section
  keep     LESSONS.md                         your rules outlive the tool
```

Three things it will not do. It does not rewrite `CLAUDE.md`, only cuts the
block between the `never-again` markers and leaves the rest of your file alone.
It does not replace `.claude/settings.json`, only drops the hook entries that
point at `.claude/hooks/na/`, so your own hooks and settings stay. And it does
not delete `LESSONS.md`: those rules are yours, they read perfectly well
without the tool that enforced them, and deleting a stranger's notes is not an
uninstaller's job. Remove it yourself if you want it gone.

Running it twice is fine. The second run has nothing to do and says so.

`tests/uninstall.sh` asserts all of the above against a repo that already has
its own `CLAUDE.md` sections, its own hooks in `settings.json` and its own
`.gitignore` entries, because the property worth testing is not that uninstall
deletes things but that it deletes only its own.

---

## The cap, and why it's a cap

Every benchmark on instruction density agrees on the direction: compliance
falls as the list of simultaneous instructions grows, and the model quietly
drops rules rather than bending them. IFScale (Distyl AI, 2025) measured 20
models from 10 to 500 concurrent instructions; even the best reached only 68%
at the top end, and models followed earlier instructions more reliably than
later ones. That is the "I wrote the rule down and it ignored it anyway"
experience, measured.

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
na retire L001    # drop the line, keep the archive
na demote L001    # blocking back to warn
```

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
