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
wrong path. Enforced rules cost zero tokens until they fire.
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
| **1. Existing gate** | A linter rule, tsconfig flag, or test already covers this | Turn it on. File nothing. |
| **2. Hook** | The mistake is detectable by a script at a known moment | Write a hook (§3) |
| **3. Rule line** | It needs judgement a script cannot make | One line in `LESSONS.md` (§4) |
| **4. Nothing** | One-off, environment-specific, or already impossible | Say so and move on |

Rung 4 is a real answer. Use it.

**A mistake is hook-shaped if you can describe the check in one sentence
beginning with "before" or "after".** "Before committing, fail if the build was
never booted in a browser." That is a hook. "Prefer clear names" is not.

### 3. If it is a hook

Hooks live in `.claude/hooks/na/` and are registered in `.claude/settings.json`.

**Every new hook starts in warn mode. No exceptions.** A hook that blocks on
day one will block something legitimate and the user will delete the whole
tool. Warn mode is also how the lesson proves itself.

1. Read `.claude/never-again/state.json` to get the next lesson id (`L###`).
2. Write `.claude/hooks/na/<id>.sh` from `.claude/never-again/hook-template.sh`
   and `chmod +x` it. The script reads the hook payload on stdin and prints a
   JSON decision with exit 0:
   - warn mode → `permissionDecision: "ask"` — the user sees a prompt with the
     reason, and can proceed or not
   - block mode → `permissionDecision: "deny"` — the call is cancelled and
     Claude is told why
   - any other mode → no output, exit 0 (this is how retire silences a hook)

   Do not use stderr + exit 0 to warn. That output goes only to the debug log;
   nobody sees it.
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
   For `Edit|Write` matchers, the field to inspect is `tool_input.file_path`.
4. Add the entry to `state.json` with `"mode": "warn"`, `"fires": 0`,
   `"correct": 0`.
5. Write the full story to `.claude/never-again/archive/<id>.md`.
6. Add **one line** to `LESSONS.md` marked `[hook]` so the user can see it
   exists without reading the script.

Scope the matcher as narrowly as you can. A hook that fires on every write
will be resented within a day.

If the check needs something to have *happened* (a test run, a boot, a build),
the hook alone cannot know. Write the companion script that performs the check
and writes a stamp file, and have the hook test the stamp. A hook that can
never be satisfied is worse than no hook.

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

Each time a warn-mode hook fires, the user answers the prompt. Afterwards, ask
once whether the fire was right, and record it:

```
.claude/never-again/na ok L017       # correct — counts toward promotion
.claude/never-again/na wrong L017    # false positive — resets the count
```

After five correct fires, offer promotion once:

```
L017 has fired 5 times, all correct. Promote to blocking? (na promote L017)
```

On a false positive, do not offer promotion — narrow the check instead. A hook
that cries wolf gets uninstalled along with everything else.

Promotion is always reversible: `na demote L017`.

## Monorepos and parallel agents

**Scope by package.** A lesson about `packages/api` belongs in
`packages/api/LESSONS.md`, not the root. Claude reads the root file plus the
one nearest the files it is touching, so a rule about the API never costs
tokens while working on the web app.

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
- Do not generate statistics yourself. Run `.claude/never-again/na`; a script
  counting lines costs nothing, and you reasoning about counts costs a lot.
- Do not rewrite `CLAUDE.md` outside the marked block.

## Files this skill owns

```
LESSONS.md                          the rules Claude reads (small, capped)
.claude/never-again/state.json      lesson index, hook modes, fire counts
.claude/never-again/archive/L###.md the full story, read on demand only
.claude/never-again/fires.log       one line per hook fire, for stats
.claude/hooks/na/L###.sh            the enforcement scripts
```
