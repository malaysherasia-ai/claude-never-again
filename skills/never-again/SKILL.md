---
name: never-again
description: Capture a bug or mistake as a permanent guardrail so it cannot happen twice. Use this skill whenever a bug is fixed, a test fails and is repaired, the user says "you did that again", "don't do that", "remember this", "never do X", or any correction is made that a future session would otherwise forget. Also use when the user asks to review, promote, or clean up existing lessons and hooks.
---

# Never Again

Turn a mistake into something that cannot happen again.

Most memory tools write a note and hope it gets read. A note costs tokens on
every single turn and can still be drifted past in a long session. This skill
asks a different question first:

> **Can this be enforced instead of remembered?**

If yes, it becomes a hook — a script that runs automatically and blocks the
wrong path. Enforced rules cost nothing per turn beyond their one line.
If no, it becomes one short line in `LESSONS.md`.

## The rule that governs this skill

**This skill must not cost more than it saves.** Every line added to
`LESSONS.md` is paid for on every future turn. Be ruthless. If you would not
pay 30 tokens per turn forever to prevent this bug, do not file it.

## Workflow

### 1. Establish the lesson

You need three things. Get them from the conversation first; ask only for what
is genuinely missing.

- **Symptom** — what was observed going wrong
- **Cause** — the actual root cause, not the surface
- **Rule** — the instruction that prevents it, written as an imperative

If the cause is still unknown, stop. A lesson without a cause becomes a
superstition, and superstitions never expire.

### 2. Triage: enforceable or not?

Work down this ladder and stop at the first rung that fits.

| Rung | Use when | Result |
|---|---|---|
| **1. Existing gate** | A linter rule, tsconfig flag, test, or git hook already covers this | Turn it on. File nothing. |
| **2. Hook** | The mistake is detectable by a script at a known moment | Write a hook (§3) |
| **3. Rule line** | It needs judgement a script cannot make | One line in `LESSONS.md` (§4) |
| **4. Nothing** | One-off, environment-specific, or already impossible | Say so and move on |

Rung 4 is a real answer. Use it.

**A mistake is hook-shaped if you can describe the check in one sentence
beginning with "before" or "after".** "Before committing, fail if the page does
not boot." That is a hook. "Prefer clear names" is not.

### 3. If it is a hook

Hooks live in `.claude/hooks/na/` and are registered in `.claude/settings.json`.
Commit-time hooks also run from git's own pre-commit hook, so they apply to
commits made from any tool or terminal, not only Claude Code's Bash tool.

**Every new hook starts in warn mode. No exceptions.** A hook that blocks on
day one will block something legitimate and the user will delete the whole
tool. Warn mode is also how the lesson proves itself.

1. Read `.claude/never-again/state.json` to get the next lesson id (`L###`).
2. Write `.claude/hooks/na/<id>.sh` from `.claude/never-again/hook-template.sh`
   and `chmod +x` it. Fill in `ID`, `RULE`, `TRIGGER` and the CHECK section.
   The template sources `na-lib.sh`, which reads the payload, decides whether
   the command is really a commit, reads the mode from `state.json`, records
   the fire, and prints the decision. You write only the check.

   Four rules for the check. Each one was a real failure:

   - **Look at what changed, not the whole tree.** `na_changed_files .css .html`
     lists the files this commit could carry. A hook that scans every file in
     the repo cost 11 seconds per commit on a small site.
   - **Keep it under a second.** People wait on it every commit, forever.
   - **If the rule is "X must pass before commit" (a test suite, a smoke
     command, a build, a browser boot), do not write a check at all.** Copy
     `.claude/never-again/hook-verify-template.sh` instead, set `ID` and
     `RULE`, and put the command and the watched files in `state.json`:

     ```json
     "verify": { "run": "npm test --silent", "watch": [".ts", ".tsx"], "skip": ["dist"] }
     ```

     That hook stays silent while nothing watched has changed, runs the
     command itself when something has, and fires only when it fails. It
     never asks "did you run it?": `PreToolUse` sees the repository as it is
     *before* the tool call, so a stamp written by a separate command is
     always stale and `run-x && git commit` fires every time. Give the
     settings entry a `"timeout"` longer than the command takes. Running it
     by hand: `bash .claude/hooks/na/L017.sh --run`.
   - **Self-test with `NA_DRY_RUN=1`.** Pipe a fake payload through the script
     four ways: a non-commit command (silent), a clean tree (silent), the bug
     reintroduced (`ask`, naming the file), and `git -C . commit` (still
     `ask`). Without `NA_DRY_RUN` every test run lands in `fires.log` and
     counts toward promotion.

3. Register it. Read `.claude/settings.json`, merge this into the existing
   `hooks` object, write it back. **Never replace the file.** Use the `if`
   field so the process only spawns for the commands that matter:

   ```json
   {
     "hooks": {
       "PreToolUse": [
         {
           "matcher": "Bash",
           "hooks": [
             {
               "type": "command",
               "if": "Bash(git commit *)",
               "command": "\"$CLAUDE_PROJECT_DIR\"/.claude/hooks/na/L017.sh"
             }
           ]
         }
       ]
     }
   }
   ```

   Events you will actually use: `PreToolUse` (before a tool runs; can block),
   `PostToolUse` (after; cannot undo), `Stop` (when Claude finishes a turn).
   For `Edit|Write` matchers set `TRIGGER="any"` and inspect `$NA_FILE`.
4. Add the entry to `state.json` with `"form": "hook"`, `"mode": "warn"`.
5. Write the full story to `.claude/never-again/archive/<id>.md`.
6. Add **one line** to `LESSONS.md` marked `[hook]` so the user can see it
   exists without reading the script.

Scope the matcher as narrowly as you can. A hook that fires on every write
will be resented within a day.

### 4. If it is a rule line

Append to the nearest `LESSONS.md` (§6) in exactly this format:

```
- [scope] Rule as an imperative — when: trigger condition (L###)
```

One line. No prose, no reasoning, no examples. All of that goes in
`.claude/never-again/archive/<id>.md`, which is only ever read when someone
asks why.

Before appending, **check for a near-duplicate.** If an existing rule already
covers it, sharpen that rule rather than adding a second one. Two overlapping
rules are worse than one, because neither gets trusted.

If `LESSONS.md` is at its cap (default 40 rules per file, `cap` in
`state.json`), you may not add another until one is promoted to a hook or
retired. Say this plainly and propose which one to retire.

**Order matters.** Models follow earlier instructions more reliably than later
ones, so the rules that fire most belong at the top. Do not reorder by hand;
`na sort` does it from the fire log. If the user asks why a rule keeps being
ignored, check where it sits in the file before anything else.

### 5. Report

One line to the user. Nothing more:

```
Filed L017 as a hook (warn mode) · 23 rules, 9 hooks
```

Do not print a summary, a table, or a celebration. Those are tokens. The stats
command exists for that and it is free.

## Promotion: warn → block

A hook earns its way up. The user decides, never you.

You will not see a warn-mode fire: the prompt goes to the person, not to the
model. So do not ask "was that right?" after commits. The record keeps itself:

- The hook logs the fire when it asks.
- If the tool call then runs, `_after.sh` marks the fire **proceeded**: the
  person went ahead despite the warning.
- If it never runs, the fire is settled as **declined**: the person stopped.
  A declined fire counts as correct on its own.
- `na ok L017` / `na wrong L017` grade the latest fire when the person wants
  to say otherwise, or to grade a proceeded one. Grades attach to real fires;
  there is nothing to grade until the hook has fired.

`na` shows per hook: fires, denied, declined, proceeded, ok, wrong, and the
current streak. After five correct in a row it says so. Offer promotion once,
when the user runs `na` or asks; do not nag:

```
L017 has five correct fires in a row. Promote to blocking? (na promote L017)
```

On a false positive, do not offer promotion — narrow the check instead. A hook
that cries wolf gets uninstalled along with everything else.

Promotion is always reversible: `na demote L017`. A hook that never fires is a
hook to retire: `na retire L017` removes the rule line, deregisters the hook,
and moves its script to the archive so it stops costing anything.

## Monorepos and parallel agents

**Scope by package.** A lesson about `packages/api` belongs in
`packages/api/LESSONS.md`, not the root. Claude reads the root file plus the
one nearest the files it is touching, so a rule about the API never costs
tokens while working on the web app.

When you create a package-level `LESSONS.md`, copy it from
`.claude/never-again/lessons-template.md` so it carries the marker comment
(`managed by the never-again skill`). `na` only counts, sorts and edits
non-root files that carry that marker. A project's own `docs/LESSONS.md` in
another format is left alone, and you must not append to it either.

The number that matters is not rules per file but rules *loaded per turn*:
root plus nearest package. `na` reports this as "loaded here" and warns above
`loadedWarn` (default 60). Compliance degrades as that number grows, and the
failure mode is silent omission, not visible refusal. When the warning fires,
split by package, retire, or promote; do not raise the threshold.

**One writer per file.** Parallel agents each append to the `LESSONS.md`
nearest their own working directory, so two agents never write to the same
file. If two agents genuinely must touch the root file, append with `>>` under
a lock — never read-modify-write, which is how lines get lost.

Hooks are shared and therefore need more care: before writing a hook, re-read
`state.json` to claim the next id, and merge into `settings.json` rather than
replacing it.

## What not to do

- Do not file a lesson for a typo, a one-off flake, or something the user
  clearly already knows.
- Do not write reasoning into `LESSONS.md`. That is what the archive is for.
- Do not auto-promote a hook to blocking.
- Do not edit `fires.log` by hand. Self-tests use `NA_DRY_RUN=1` so there is
  never a reason to.
- Do not generate statistics yourself. Run `.claude/never-again/na`; a script
  counting lines costs nothing, and you reasoning about counts costs a lot.
- Do not rewrite `CLAUDE.md` outside the marked block.

## Files this skill owns

```
LESSONS.md                          the rules Claude reads (small, capped)
.claude/never-again/state.json      lesson index, hook modes
.claude/never-again/archive/L###.md the full story, read on demand only
.claude/never-again/fires.log       one line per hook fire with its outcome and grade
.claude/never-again/hook-template.sh what a new hook starts from
.claude/hooks/na/L###.sh            the enforcement scripts
.claude/hooks/na/na-lib.sh          shared by every hook: payload, mode, logging, decision
.claude/hooks/na/_after.sh          records that a warned commit went ahead
.claude/hooks/na/pre-commit         runs commit hooks from git itself
```
