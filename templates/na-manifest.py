#!/usr/bin/env python3
"""Verification manifest for verify-shaped hooks. Installed as
.claude/hooks/na/na-manifest.py and driven by na-verify.sh.

A hook of the shape "X must pass before commit" needs to know whether anything
X depends on has changed since X last passed. This records one sha256 per
watched file, written only when X passes, and reports what differs.

    na-manifest.py check  <root> <state.json> <id>
    na-manifest.py commit <root> <state.json> <id>

check   reads the lesson's "verify" block from state.json, prints the command
        to run as its first line (RUN=<command>), then one `reason<TAB>path`
        line per difference. It leaves the digests it computed in
        <manifest>.next so a passing run does not hash the tree again.
        exit 0 fresh · 1 stale · 2 no verify block · 3 verify block malformed
commit  turns <manifest>.next into <manifest>, re-hashing only files whose
        size or mtime moved since check. exit 0 on success.

Files come from `git ls-files` (tracked plus untracked-but-not-ignored), so
dist/, vendor/, venv/ and anything else in .gitignore never count. Each line
carries size and mtime, and a file whose stat is unchanged is not re-read.

The manifest lives at <root>/.claude/never-again/verified/<id>.
"""
import hashlib
import json
import os
import subprocess
import sys

ALWAYS_SKIP = {'.git', '.claude', 'node_modules'}


def load_config(state_path, lid):
    """Return (config, error). Lists may be given as a string too."""
    try:
        with open(state_path, encoding='utf-8') as fh:
            lesson = json.load(fh)['lessons'][lid]
    except Exception as exc:
        return None, 'cannot read %s for %s (%s)' % (state_path, lid, exc)
    v = lesson.get('verify')
    if not v:
        return None, None
    if not isinstance(v, dict):
        return None, '"verify" must be an object'
    run = v.get('run')
    if not isinstance(run, str) or not run.strip():
        return None, '"verify.run" must be a non-empty command string'

    def as_list(name):
        x = v.get(name, [])
        if isinstance(x, str):
            x = [p for p in x.replace(',', ' ').split() if p]
        if not isinstance(x, list) or not all(isinstance(p, str) for p in x):
            raise ValueError('"verify.%s" must be a list of strings' % name)
        return x
    try:
        watch = as_list('watch')
        skip = as_list('skip')
    except ValueError as exc:
        return None, str(exc)
    if not watch:
        return None, '"verify.watch" must name at least one extension'
    exts = tuple(e if e.startswith('.') else '.' + e for e in watch)
    return {'run': run, 'exts': exts, 'skip': set(ALWAYS_SKIP) | set(skip)}, None


def candidates(root):
    """Every path git would consider part of the tree: tracked, plus untracked
    that is not ignored. Falls back to a walk when git is unavailable."""
    try:
        p = subprocess.run(['git', '-C', root, 'ls-files', '-z', '--cached', '--others',
                            '--exclude-standard'], capture_output=True)
        if p.returncode == 0:
            return [s.decode('utf-8', 'replace') for s in p.stdout.split(b'\0') if s]
    except OSError:
        pass
    out = []
    for base, dirs, files in os.walk(root):
        dirs[:] = [d for d in dirs if not d.startswith('.')]
        for f in files:
            out.append(os.path.relpath(os.path.join(base, f), root).replace(os.sep, '/'))
    return out


def tracked(root, cfg):
    """Watched files: the right extension, not under .claude/, and not under a
    skipped path. Skips are path prefixes from the root ("scripts" skips
    scripts/ but not src/scripts/), so a nested directory that happens to
    share a name is still watched."""
    prefixes = tuple(s.strip('/') + '/' for s in cfg['skip'] if s not in ALWAYS_SKIP)
    out = []
    for rel in candidates(root):
        top = rel.split('/', 1)[0]
        if top in ALWAYS_SKIP or rel.startswith(prefixes):
            continue
        if rel.endswith(cfg['exts']):
            out.append(rel)
    return sorted(set(out))


def digest(path):
    h = hashlib.sha256()
    with open(path, 'rb') as fh:
        for chunk in iter(lambda: fh.read(65536), b''):
            h.update(chunk)
    return h.hexdigest()


def read_manifest(path):
    """{rel: (sha, size, mtime_ns)}; None when the file does not exist."""
    if not os.path.exists(path):
        return None
    seen = {}
    with open(path, encoding='utf-8') as fh:
        for line in fh:
            line = line.rstrip('\n')
            if not line or line.startswith('#'):
                continue
            parts = line.split('\t')
            if len(parts) == 4:
                seen[parts[3]] = (parts[0], int(parts[1]), int(parts[2]))
    return seen


def write_manifest(path, rows):
    os.makedirs(os.path.dirname(path) or '.', exist_ok=True)
    with open(path, 'w', encoding='utf-8', newline='\n') as fh:
        fh.write('# never-again: sha256, size, mtime_ns of every watched file when the check last passed.\n')
        fh.write('# Written only on a passing run. Local to this machine. Do not edit by hand.\n')
        for rel in sorted(rows):
            sha, size, mt = rows[rel]
            fh.write('%s\t%d\t%d\t%s\n' % (sha, size, mt, rel))


def snapshot(root, cfg, prior):
    """Current (sha, size, mtime_ns) for every watched file, reading only the
    files whose stat differs from `prior`."""
    now = {}
    unreadable = []
    for rel in tracked(root, cfg):
        full = os.path.join(root, rel)
        try:
            st = os.stat(full)
        except OSError:
            unreadable.append(rel)
            continue
        size, mt = st.st_size, st.st_mtime_ns
        old = prior.get(rel) if prior else None
        if old and old[1] == size and old[2] == mt:
            now[rel] = (old[0], size, mt)
            continue
        try:
            now[rel] = (digest(full), size, mt)
        except OSError:
            unreadable.append(rel)
    return now, unreadable


def paths(root, lid):
    m = os.path.join(root, '.claude', 'never-again', 'verified', lid)
    return m, m + '.next'


def check(root, state_path, lid):
    cfg, err = load_config(state_path, lid)
    if err:
        print('ERROR=%s' % err)
        return 3
    if cfg is None:
        print('ERROR=no verify block')
        return 2
    print('RUN=%s' % cfg['run'])
    manifest, nxt = paths(root, lid)
    before = read_manifest(manifest)
    now, unreadable = snapshot(root, cfg, before)
    write_manifest(nxt, now)
    if before is None:
        print('never-verified\t(the check has not passed yet)')
        return 1
    diffs = [('unreadable', r) for r in unreadable]
    for rel, (sha, _s, _m) in now.items():
        if rel not in before:
            diffs.append(('added', rel))
        elif before[rel][0] != sha:
            diffs.append(('changed', rel))
    for rel in before:
        if rel not in now:
            diffs.append(('deleted', rel))
    for reason, rel in sorted(diffs):
        print('%s\t%s' % (reason, rel))
    return 1 if diffs else 0


def commit(root, state_path, lid):
    cfg, err = load_config(state_path, lid)
    if err or cfg is None:
        print('ERROR=%s' % (err or 'no verify block'))
        return 3
    manifest, nxt = paths(root, lid)
    prior = read_manifest(nxt) or read_manifest(manifest) or {}
    # The check may itself have rewritten a watched file (a formatter, a
    # generated asset). Re-stat everything; only what moved is re-read.
    now, unreadable = snapshot(root, cfg, prior)
    write_manifest(manifest, now)
    try:
        os.remove(nxt)
    except OSError:
        pass
    print('recorded %d file(s)' % len(now))
    return 0


def main():
    # The shell splits our output on "\n". On Windows a text-mode stdout
    # would write "\r\n" and leave a "\r" glued to the command.
    if hasattr(sys.stdout, 'reconfigure'):
        sys.stdout.reconfigure(newline='\n')
    if len(sys.argv) != 5 or sys.argv[1] not in ('check', 'commit'):
        sys.stderr.write(__doc__)
        return 4
    mode, root, state_path, lid = sys.argv[1:]
    return check(root, state_path, lid) if mode == 'check' else commit(root, state_path, lid)


if __name__ == '__main__':
    sys.exit(main())
