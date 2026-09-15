# never-again on a team

How the tool behaves when more than one person, on more than one machine,
commits to the same repository. Part of this is built; part is a proposal
waiting for agreement. Each section says which.

## What travels with git, and what does not

Built. This is the ground everything else stands on.

| Travels with the repo | Stays on each machine |
|---|---|
| `LESSONS.md` in every package: the rules | `fires.log`: every fire, its outcome and grade |
| `.claude/hooks/na/L###.sh`: the hook scripts | `.claude/never-again/verified/`: verify manifests |
| `state.json`: each lesson's mode, scope, file, verify block | `.git/hooks/pre-commit`: git never clones it |
| `archive/L###.md`: the full story of each lesson | `.claude/settings.json`: yours, often shared with other tooling |

A fresh clone has every rule in the mode the team earned. It runs the
installer once, which wires git's side and registers the dispatcher. Nothing
else is needed.

## Who grades

Built, with one gap.

Grading is automatic and per machine. When a warn-mode hook fires, the
outcome is recorded on the machine where it fired: *declined* if the person
stopped, *proceeded* if they went ahead. `na ok` and `na wrong` override. The
streak that makes a hook eligible for promotion is computed from that
machine's log.

The gap: a team's evidence is split across laptops. Alice's five declines and
Bob's three do not add up anywhere, and a hook that fires wrongly for Bob
only shows up in Bob's log.

**Proposal: shared history, opt in.** A command, `na share`, appends a
one-line-per-fire summary (date, lesson, outcome, grade, initials, no
commands or paths) to `.claude/never-again/history/<initials>.tsv`, which is
committed. `na` reads every history file plus the local log, so streaks and
false-positive counts become the team's. Nothing leaves the repository, and
nothing is shared until someone runs the command. Cost: one small committed
file per person that grows by a line per fire.

## Who promotes

Built. Promotion is a change to `state.json`, so it travels exactly like any
other change to the repo. The `promotion` setting in `state.json` says who
may make it:

```json
"promotion": "pull-request"
```

- `"pull-request"` (the default for new installs): `na promote` refuses to
  run on the default branch of a repository with a remote. Make a branch,
  promote there, open a pull request. The change is reviewed like code, and
  a branch rule on `main` makes that impossible to skip. Add a
  `CODEOWNERS` line for `.claude/never-again/state.json` if a particular
  group must approve.
- `"anyone"`: `na promote` runs wherever it is called. Right for a
  single-person repo.
- a list of names or emails: `na promote` runs only when the git identity
  of the person running it is in the list.

Demotion and retirement follow the same setting: they are also changes to a
committed file and are just as visible.

Never automatic, in every mode. The tool reports when a streak reaches
five; a person makes the change.

## Shared packs

Proposal. A pack is a set of lessons that many repositories want: "web
front-end" (boot the page, no opacity dimming, contrast floor), "Python
service" (tests pass, no secrets, migrations reversible). Today the browser
boot example is copied by hand.

**Design.** A pack is a directory, in any git repository, with the same
shape as a lesson archive: one `L###.sh` per hook, one `L###.md` per story,
a `pack.json` naming the pack and its lessons. `na pack add <git url or
path>` copies the scripts in under the next free ids, files each lesson in
warn mode with its origin recorded, and appends the one-liners. `na pack
update` re-reads the source and shows a diff before applying. Nothing is
fetched without the command, and a pack never arrives in block mode: every
repo earns its own promotions.

Packs are how the "why is this repo different" question gets a short
answer: the pack name and version are in each lesson's record.

## Many hooks

Built. One dispatcher entry runs every hook from an index (`na index`); a
hook that watches `.css` is not run for a commit that touched none. Two
hundred hooks cost the same setup as two. Grouping is by scope in the index;
a database is not needed and would add an install step for nothing.

## What to agree on

1. Shared history: opt in by command, or on by default with a way to turn it
   off? Opt in is proposed.
2. Packs: worth building before a second repository asks for one? The
   proposal is to wait for that request.
