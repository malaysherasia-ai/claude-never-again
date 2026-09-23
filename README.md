# never-again

**Your coding agent keeps making the same mistake. Stop writing it a reminder.
Take the mistake away.**

`never-again` catches each bug you fix and asks one question: can a script
stop this next time? If it can, it writes a hook that blocks the wrong action.
If it cannot, it writes one short line in a rules file. That is all.

MIT licensed. Runs on your machine. No account, no tracking. It talks to
GitHub twice, both times about releases: `na upgrade` when you run it, and a
once-a-day check for a newer version after a commit. That check sends nothing
but the request. `"updates": "off"` in `state.json` stops it.

Built for Claude Code. Works the same with Codex, Gemini CLI, GitHub Copilot
and Google Antigravity: see [Other agents](#other-agents).

**macOS, Linux, WSL:** needs git, bash and Python 3.7 or newer.

```bash
git clone --depth 1 https://github.com/malaysherasia-ai/claude-never-again.git
bash claude-never-again/install.sh .
```

**Windows:** needs Git for Windows and Python 3.7 or newer.

```powershell
git clone --depth 1 https://github.com/malaysherasia-ai/claude-never-again.git
& "C:\Program Files\Git\bin\bash.exe" claude-never-again/install.sh .
```

Run it with `bash`, not `./install.sh`. A ZIP download loses the file's
run permission, and Windows checkouts are unreliable about it. `bash` always
works.

**Already installed?** `.claude/never-again/na upgrade` fetches the newest
release and runs its installer in this repo. `na upgrade --check` only says
whether there is one. Each repo moves when you say so, never under you.

**Staying current.** After a commit, at most once a day, the after-commit
hook asks GitHub for the newest release and remembers the answer. The next
commit, and `na` itself, then say one line: *never-again 1.4.0 is out: na
upgrade*. Nothing is installed for you. Offline, it stays quiet and asks
again the next day. A repo that only commits from a terminal sees the line
when someone runs `na`. Turn it off with `"updates": "off"` in `state.json`.

That line is a reminder, and an agent that runs git in a terminal nobody
reads commits straight past it; one did. `"updates": "block"` makes the
stale release a stop instead: the next commit is refused, from any agent or
a shell, with the one command that clears it, `na upgrade`. When now is not
the time, `na upgrade --later` lets commits through until tomorrow or the
next release. A repo that registers Antigravity gets `"block"` at install,
because that IDE has never been seen running the hook and only the git side
can reach it; change it in `state.json` and the installer leaves it alone.

**Run the installer yourself, from a terminal.** Claude Code's auto mode will
not run an installer it has never seen. It also will not edit its own
`.claude/settings.json` or write into `.git/hooks/`, even when you say yes.
That is Claude Code protecting you, not a bug. If you must install from
inside Claude Code, turn auto mode off first. Otherwise, add these two pieces
by hand afterwards:

```jsonc
// .claude/settings.json: merge into "hooks"; keep everything else
"PreToolUse":         [{ "matcher": "Bash", "hooks": [{ "type": "command", "timeout": 600, "command": "\"$CLAUDE_PROJECT_DIR\"/.claude/hooks/na/dispatch" }] }],
"PostToolUse":        [{ "matcher": "Bash", "hooks": [{ "type": "command", "command": "\"$CLAUDE_PROJECT_DIR\"/.claude/hooks/na/_after.sh" }] }],
"PostToolUseFailure": [{ "matcher": "Bash", "hooks": [{ "type": "command", "command": "\"$CLAUDE_PROJECT_DIR\"/.claude/hooks/na/_after.sh" }] }]
```

No `if` filter on those entries. `Bash(git commit *)` only matches a command
that begins with `git commit`, so `git add . && git commit` never reached the
hook. The scripts read the command themselves, and a call with no commit in
it exits before any interpreter starts.

```sh
# .git/hooks/pre-commit: create it if you have none; otherwise add the last two lines to yours
#!/bin/sh
r="$(git rev-parse --show-toplevel)/.claude/hooks/na/pre-commit"
[ -f "$r" ] || exit 0
exec "$r" "$@"
```

```sh
# .git/hooks/commit-msg: the same, for the capture check, which needs the message
#!/bin/sh
r="$(git rev-parse --show-toplevel)/.claude/hooks/na/commit-msg"
[ -f "$r" ] || exit 0
exec "$r" "$@"
```

The same goes for `na`, the stats command. In auto mode Claude Code may
refuse to run it. Run it from a terminal.

**Three things to check in your repo.** The installer looks for each one and
tells you. It helps to know them ahead of time:

- If `.gitignore` hides the `.claude/` folder, the hooks and their settings
  stay on your machine. They do not reach git. `LESSONS.md` still does. The
  installer prints the lines to use if you want the hooks shared. Do not share
  `.claude/settings.json` itself: other tools write machine-specific paths
  into it. The installer registers the hooks on each clone instead.
- If your repo root is served as a website (Vercel, Netlify, GitHub Pages),
  then `/LESSONS.md` and `/.claude/` become public web pages, hooks and
  settings included. Add `.claude`, `LESSONS.md` and `CLAUDE.md` to
  `.vercelignore`, publish a subfolder instead, or accept that people can read
  them.
- If your repo already has a `LESSONS.md` somewhere other than the root, in
  its own format, it is left alone. `na` only manages the root file and files
  that carry the tool's marker comment.

---

## Why not just put it in CLAUDE.md?

Because `CLAUDE.md` is advice, and advice has two problems.

You **pay for it on every turn.** A 200-line instructions file is 200 lines
of context in every message you send, forever, whether it matters right now
or not. Prompt caching makes that cheap in money. It does not make it cheap
in attention, and attention is what makes rules get followed.

And it is **optional.** The longer a session runs, the more likely a rule
gets skipped. Plenty of people have written the rule down and watched the same
bug ship anyway.

A hook is neither. It costs one line until it fires. In block mode it says no,
and the agent cannot talk its way past that. In warn mode it asks you, and it
writes down what you answered.

```
             cost per turn     can be ignored
CLAUDE.md      every line           yes
hook            one line             no
```

`never-again` is the bridge between the two. It decides which of your lessons
belongs where, and it writes the hook for you.

---

## What it actually does

**1. You fix a bug.** Then you say "never again", or Claude notices the
correction on its own. And if neither happens, the commit does: a commit
whose message says it is a fix (`fix`, `bug`, `revert`, `regression`,
`broken`) and that carries no lesson gets one question before it lands,
from the agent's own hook and from git's `commit-msg` hook alike:

```
never-again capture asks: this commit looks like a fix (fix nav font) and files no lesson.
Use the never-again skill to capture what went wrong, or run .claude/never-again/na none
if there is nothing to learn
```

The agent answers by running the skill, or by `na none <why>` when the fix
teaches nothing. The mark clears once the commit lands, so it cannot silence
the next one. A commit that mentions a typo is left alone. `"capture": "off"`
in `state.json` turns the question off; `"block"` makes it refuse instead.
It is the one part of the loop that used to depend on the agent reading
`CLAUDE.md`, and the field showed what that was worth: four real lessons sat
in a repo until someone typed a prompt asking for them.

**2. It sorts the lesson.** Four options, first fit wins:

| | | |
|---|---|---|
| Already covered | a linter or tsconfig flag catches it | turn that on, file nothing |
| Hook-shaped | you can say it as "before X, fail if Y" | write a hook |
| Judgement | a script cannot make the call | one line in `LESSONS.md` |
| Not worth it | a one-off, or already impossible | file nothing |

That last row matters. Most tools file everything. This one is allowed to say
no, because every line it writes is rent you pay forever.

**3. The hook starts in warn mode.** Instead of blocking, it shows you a
prompt with the reason, and you choose. One thing to know before you rely on
that: in Claude Code's auto mode, the harness answers the prompt for you and
you never see it. The hook still records the fire, and it now also hands the
reason to the model as a system message so the model can stop itself, but
only block mode stops a commit when nobody is watching. If you run in auto
mode, promote the hooks you trust and read `na` now and then. Your choice is written down without
any work from you. If the commit went ahead, the fire is marked *proceeded*.
If you stopped, it is marked *declined*, and a declined fire counts as
correct. You can overrule the record when you want:

```bash
na ok L001        # that fire was right
na wrong L001     # false alarm; narrow the check, the streak resets
```

Grades attach to real fires. After five correct in a row, `na` tells you, and
you promote it yourself:

```bash
na promote L001
```

Never automatic. A hook that blocks wrongly on day one gets the whole tool
uninstalled. Who may promote is a setting in `state.json`. The default is by
pull request: `na promote` refuses on the default branch, so the change gets
reviewed like code. The other options are anyone, or a list of names.
[`docs/TEAMS.md`](docs/TEAMS.md) covers teams: what travels with git, who
grades, who promotes, and packs.

**4. It guards every commit, not only Claude's.** The same script runs from
git's own pre-commit and pre-merge-commit hooks, and the capture check from
its commit-msg hook. A commit or a merge from a terminal, another agent, or
a different tool meets the same rule. Warn mode prints and lets it through.
Block mode refuses it.

What it does not cover, so you know the edge: `git cherry-pick` and
`git rebase` create commits without running those git hooks, and a merge
done on GitHub (`gh pr merge`, the merge button) happens on their server. If
a rule must hold there too, it belongs in CI as well.

---

## Before and after

A real one: the bug this tool came out of.

Every button on a page went dead. The cause was a `let` used before its
declaration. That is a temporal dead zone error. It stops the script at
startup, so no click handler ever attaches. `node --check` passed, because it
only checks syntax.

**What most setups do** is add a line to `CLAUDE.md`:

```
Always test in a real browser before shipping.
```

That line gets read on every turn until the end of the project. It gets
followed when the context window is short and the agent is paying attention.

**What `never-again` does** is file this instead:

```
- [web] [hook] Boot the build in a real browser, not `node --check` — when: before commit (L001)
```

It also writes `.claude/hooks/na/L001.sh`. That script compares every source
file against the last browser boot that passed. If anything changed, it runs
the boot itself. It refuses the commit only if the page does not boot.

The rule now cannot be skipped, and it costs one line to carry. The full
worked example is in [`examples/browser-boot/`](examples/browser-boot/).

---

## Stats, counted not generated

The block below is **sample output from a mature install**, not results from
this project. It shows the shape of the report. To see what your own repo has
recorded, run `na` there. `na report` prints the same numbers as a Markdown
page, with every lesson, every hook's record and which agents ever called
the hook, so a write-up for someone else can be counted rather than written:
the first field report an agent produced about this tool said hooks were
"preventing regressions" in a repo whose fire log did not exist.

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
  capture nudges  6   (a fix committed with no lesson filed: 4 stopped, 2 went ahead)

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

This is a Python script counting lines in files. **No model is involved.**
That is the point. A tool that spends tokens to tell you how many tokens it
saved has argued itself out of a job.

"Prevented" counts block-mode denials plus warn-mode fires where the person
stopped. One stopped mistake can fire twice if the agent retries, so read it
as an upper bound. "Warned past" is the honest column: prompts that were
approved anyway.

The token figure is an estimate built on one number you control: what a
repeated debug-and-fix cycle costs you. The default of 8,000 is on the low
side on purpose. Change it in `state.json`.

**Nothing is sent anywhere.** If you want to share your number, copy it into
a post. There is no phone-home, and there never will be. A tool that reads
your repo has no business opening a network connection.

---

## Monorepos and parallel agents

Lessons belong to the nearest `LESSONS.md`. A rule about `packages/api` lives
in `packages/api/LESSONS.md` and costs nothing while you work on the web app.

Parallel agents each write to the file nearest their own working folder, so
two writers never touch one file. Hooks are shared, so the skill re-reads
`state.json` to claim an id, and it merges into `settings.json` instead of
replacing it.

---

## Other agents

never-again grew up on Claude Code, but the guard is not tied to it. The
check runs from git's own pre-commit hook, and every agent that commits goes
through git. So Codex, Gemini CLI, GitHub Copilot and Google Antigravity get
the git-side guard the moment you run the installer. Nothing to set up.

The second half, the prompt that stops an agent *before* it runs `git commit`,
needs one entry in that agent's hook file. The installer writes it:

```bash
bash claude-never-again/install.sh --agent codex .
```

The names are `codex`, `gemini`, `copilot` and `antigravity`. Repeat the flag
or join them with commas. An agent whose folder is already in the repo
(`.codex/`, `.gemini/`, `.github/copilot-instructions.md`,
`.agents/hooks.json`) is registered without the flag. The choice is kept in
`state.json`, so a re-run and a fresh clone keep it.

For each agent the installer does three things:

- **Writes two entries** into the agent's hook file, one for the dispatcher
  and one for the after-commit recorder. Merged, never replaced.
- **Puts the same rules block** into the file that agent reads: `AGENTS.md`
  for Codex and Antigravity, `GEMINI.md` for Gemini CLI,
  `.github/copilot-instructions.md` for Copilot.
- **Copies the skill** into that agent's skills folder (`.agents/skills`,
  `.gemini/skills`, `.github/skills`), so "never again" means the same thing
  at every keyboard.

The hook scripts never change. They all speak one dialect. The dispatcher
reads each agent's payload and answers in that agent's shape.

| Agent | Hook file | Warn mode shows as | Block mode |
|---|---|---|---|
| Claude Code | `.claude/settings.json` | a prompt, plus a message | denied |
| Codex | `.codex/hooks.json` | context the model reads (Codex has no "ask") | denied |
| Gemini CLI | `.gemini/settings.json` | a message on screen | denied |
| Copilot | `.github/hooks/never-again.json` | a prompt | denied |
| Antigravity | `.agents/hooks.json` | a prompt | denied |

Things to know:

- **Codex asks you to trust the hook once.** Run `/hooks` in Codex after the
  installer. Trust is tied to the entry in the hook file, which does not
  change between releases.
- **Copilot fails closed.** A hook that crashes blocks the tool call. The
  dispatcher always answers on that path, even when it has nothing to say.
- **Antigravity reads its hook file at startup.** Restart it after the
  installer, then ask it "which hooks are installed?" to confirm.
- **The entries hold no path, no quote and no substitution.** Each one runs
  `~/.never-again/launch`, a small launcher the installer puts outside every
  repo, which finds the repo from the payload's own working directory. Three
  things made that necessary: Antigravity runs hooks from `.agents/` itself;
  PowerShell 5.1 strips the quotes off a path it hands to a native program;
  and a committed hook file must not carry one machine's path. A clone whose
  owner has not run the installer has no launcher, and the entry exits clean
  rather than failing closed. On Windows the entry names Git's `bash.exe` by
  its full path, because a process an agent spawns has WSL's bash on PATH,
  or none; never Git's.
- **Did the agent call the hook at all?** `.claude/never-again/calls.log`
  gets one line per commit the dispatcher saw, with the agent's name and
  whether anything fired. Local, gitignored. If a commit went through and
  no line appeared, the agent never ran the entry.
- **Warn mode cannot pause Gemini.** It has no "ask". Only block mode stops
  a commit there when nobody is watching. The git-side hook still records
  every fire.

Uninstall removes exactly these entries, files and blocks, and keeps anything
else in those files.

---

## Two things every hook gets right for you

Hooks all load one shared library, `.claude/hooks/na/na-lib.sh`, so the parts
that went wrong in the first release now live in one place.

**It decides from the command, not from a word in it.** `git -C . commit`,
`git  commit` and `git add -A && git commit` all count as a commit.
`echo "git commit"` does not.

**It never asks "did you run X?"** A `PreToolUse` hook sees the repo as it
was before the tool call. So a hook that checks for a stamp file fires every
time the stamp is written in the same command as the commit. Six of the first
nine real fires were exactly that. If a rule says "X must have run", the hook
runs X itself when things are stale, and fires only when X fails.

It also looks only at the files that changed, not the whole tree, so what
was already in the tree when a hook was written stays there until `na sweep
L001` runs the same check over every file once. It records
what happened after it fired. And it stays out of `fires.log` during
self-tests (`NA_DRY_RUN=1`).

**One process, however many hooks.** Claude Code runs one entry, the
dispatcher. It reads the commit once, finds Python once, lists the changed
files once, and asks `na index` which hooks exist, in which mode, watching
which file types. A hook that watches `.css` does not run for a commit that
touched none. Ten hooks or two hundred cost one setup. Only the checks that
apply run, and their answers come back as one decision.

---

## What gets installed

```
LESSONS.md                          the rules Claude reads (small, capped, ordered)
CLAUDE.md                           one marked block added at the end; never overwritten
.claude/skills/never-again/         the skill
.claude/hooks/na/L###.sh            the hook scripts
.claude/hooks/na/dispatch           the one registered hook: runs the others from na index
.claude/hooks/na/na-lib.sh          shared by every hook
.claude/hooks/na/na-verify.sh       the "X must pass before commit" engine, plus na-manifest.py
.claude/hooks/na/_after.sh          records that a warned commit went ahead
.claude/hooks/na/_capture.sh        asks when a fix is committed with no lesson filed
.claude/hooks/na/pre-commit         runs commit hooks from git itself
.claude/hooks/na/commit-msg         runs the capture check from git, where the message shows
.claude/settings.json               two entries, dispatch and _after.sh; merged, never replaced
AGENTS.md, GEMINI.md,
  .github/copilot-instructions.md   the same block, only for the agents you registered
.codex/hooks.json, .gemini/settings.json,
  .agents/hooks.json,
  .github/hooks/never-again.json    two entries each, only for the agents you registered
.agents/skills/, .gemini/skills/,
  .github/skills/                   the skill, copied for that agent
~/.never-again/launch               outside the repo: what those entries run; same on every machine
.git/hooks/pre-commit               a short stub, only if you had none; pre-merge-commit and commit-msg likewise
.claude/never-again/
  ├── na                            the stats command  (na.cmd for PowerShell)
  ├── state.json                    lesson index, hook modes, the capture setting
  ├── archive/L###.md               the full story, read only when asked
  ├── verified/                     one record per verify hook; local, gitignored
  ├── fires.log                     every fire, its outcome and grade; local, gitignored
  ├── calls.log                     one line per commit the dispatcher saw; local, gitignored
  ├── .capture-none                 the `na none` mark, cleared by the next commit; local, gitignored
  └── .update-check                 the once-a-day release check; local, gitignored
```

**Already have notes?** Most repos do: a `CLAUDE.md` full of rules, a
`NOTES.md`, a `docs/lessons.md`, a `.cursorrules`. `na import` lists them,
with how many lines of notes each one holds and which were imported before.
Tell Claude once, *"import the existing notes with the never-again skill"*.
Each note then goes through the same sorting as a fresh bug. The ones a
script can check become hooks in warn mode. The judgement calls become
one-liners. The rest are skipped. The source files are never edited. The tool
only remembers which files were imported, so the next `na import` shows only
what changed.

**Already have a `LESSONS.md`?** It stays exactly as it is, and Claude keeps
reading it. But notes in your own words are invisible to `na`: not counted,
not capped, not sorted, not enforced. The installer says so when it finds
them. To bring them in, tell Claude once: *"read LESSONS.md and refile each
note through the never-again skill"*. Each note goes through the same sorting.
Your original stays in git history.

**What a fresh clone gets, and what it does not.** `LESSONS.md`, the hook
scripts, `state.json` and the archive travel with git. So a clone has every
rule, in the mode the team earned. The wiring does not travel. Git never
clones its own hooks folder, and `.claude/settings.json` is yours; it often
holds other tools and paths that only work on one machine, so we do not ask
you to share it. After cloning, run the installer once. It registers every
hook in `state.json` with Claude Code and with every other agent the repo
uses, and installs the git stub. It is safe to run again, changes nothing
that already matches, and takes a second. After that, `na upgrade` is the
same installer, fetched for you.

`install.sh` backs up `CLAUDE.md` before touching it and is safe to re-run.
`LESSONS.md` and the hooks are meant to be committed. They are team knowledge.
A new hire inherits every scar the team has earned.

---

## Uninstall

```bash
.claude/never-again/na uninstall          # or: bash install.sh --uninstall .
```

It prints exactly what it will do and waits for a yes. Pass `--yes` to skip
the prompt. Anything other than `y` removes nothing. A closed stdin also
removes nothing, so it is safe to pipe.

```
  remove   .claude/skills/never-again/        12 file(s)
  remove   .claude/hooks/na/                  7 file(s)
  remove   .claude/never-again/               9 file(s)
  remove   .git/hooks/pre-commit              git pre-commit stub
  remove   .git/hooks/commit-msg              git commit-msg stub
  edit     CLAUDE.md                          strip the never-again block, keep the rest
  edit     .claude/settings.json              remove 4 hook entries, keep everything else
  edit     .gitignore                         remove the never-again section
  keep     LESSONS.md                         your rules outlive the tool
```

Four things it will not do. It does not rewrite `CLAUDE.md`. It only cuts
the block between the `never-again` markers and leaves the rest alone. It
does not replace `.claude/settings.json`. It only drops the hook entries that
point at `.claude/hooks/na/`, so your own hooks and settings stay. It does not
touch a git `pre-commit` hook it did not write. And it does not delete
`LESSONS.md`. Those rules are yours, they read fine without the tool that
enforced them, and deleting a stranger's notes is not an uninstaller's job.
Remove it yourself if you want it gone.

Running it twice is fine. The second run has nothing to do and says so.

`tests/uninstall.sh` checks all of the above against a repo that already has
its own `CLAUDE.md` sections, its own hooks in `settings.json`, its own git
`pre-commit` and its own `.gitignore` entries. The point of the test is not
that uninstall deletes things, but that it deletes only its own.
`tests/hooks.sh` builds a hook from the template and runs it through both
Claude Code's payload and a real `git commit`. It checks the fire log, the
grading, retire, and reinstall. Run both with
`bash tests/hooks.sh && bash tests/uninstall.sh`. Every pull request runs
them on Ubuntu, macOS and Windows.

---

## The cap, and why it's a cap

The direction is well supported: the more rules a model is given at once,
the fewer it follows, and it drops them quietly instead of refusing. IFScale
(Distyl AI, 2025) tested 20 models on 10 to 500 rules at once in a
report-writing task. Even the best reached only 68% at the top end, and rules
given earlier were followed more reliably than later ones. That task is not
coding, and nobody has measured the same curve for rules in a `CLAUDE.md`.
What `never-again` borrows is the direction and the "earlier is better"
effect, not a number. The "I wrote the rule down and it ignored it anyway"
experience is real. The exact limit for your repo is not in any paper.

So `never-again` does three things the research supports, and one thing it
does not claim:

- **Capped.** 40 rules per file by default. Not a magic number. It is about
  the largest file a person still reads top to bottom. Change `cap` in
  `state.json` if your team disagrees.
- **Ordered.** `na sort` puts the most-fired rules first, because "earlier is
  better" is real and free.
- **Scoped.** Rules load per package, not per repo. The number that matters
  is *rules loaded per turn*. `na` reports it as "loaded here" and warns above
  60 (`loadedWarn`). When it warns, split, retire, or promote. Do not raise it.
- **Not claimed:** that 40, or 60, is the right number for you. The evidence
  says fewer and ordered. It does not name a limit. Yours will show up in your
  own fire log.

`na` is short for `.claude/never-again/na`. Alias it.

```bash
na --version      # which release is installed
na report         # the stats as a Markdown page, counted from the logs
na sweep L001     # run one hook's check over the whole tree, once
na sort           # most-fired rules first, in every LESSONS.md
na why L001       # read the full story behind a rule
na retire L001    # drop the line, unregister the hook, keep the archive
na demote L001    # blocking back to warn
na import         # notes files already in the repo, and what was imported
na index          # every live hook: mode, trigger, scope, watched extensions
```

On Windows, `.claude\never-again\na.cmd` runs the same thing from PowerShell
or cmd.

---

## Prior art

This stands on two well-known ideas and joins them.

The `lessons.md` pattern, a file the agent writes discoveries into mid-task,
is widely used and well documented. So are Claude Code hooks, where the
settled wisdom is that rules shape behaviour and hooks enforce it.

What was missing is the step between: deciding which lessons deserve
enforcement, and generating the hook. That is all this does.

## License

MIT.

---

`never-again` is an independent open-source project. It is not affiliated
with, endorsed by, or sponsored by Anthropic. Claude and Claude Code are
trademarks of Anthropic, PBC.
