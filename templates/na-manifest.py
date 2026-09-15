#!/usr/bin/env python3
"""Content manifest for verify-shaped hooks.

A hook of the shape "X must have passed before commit" needs to know whether
anything X depends on has changed since X last passed. Timestamps answer the
wrong question (a restore, a checkout or a formatter bumps mtime without
changing bytes), so this records one sha256 per watched file, written only
when X passes, and reports what differs.

    python na-manifest.py write <root> <manifest> <ext,ext,...> [skip,dir,...]
    python na-manifest.py check <root> <manifest> <ext,ext,...> [skip,dir,...]

check exits 0 when the tree matches the manifest, 1 when it does not, printing
one `reason\tpath` line per difference.
"""
import hashlib
import os
import sys

ALWAYS_SKIP = {'.git', '.claude', 'node_modules'}


def tracked(root, exts, skip):
    out = []
    for base, dirs, files in os.walk(root):
        dirs[:] = [d for d in dirs if d not in skip and not d.startswith('.')]
        for f in files:
            if f.endswith(exts):
                full = os.path.join(base, f)
                rel = os.path.relpath(full, root).replace(os.sep, '/')
                out.append((rel, full))
    return sorted(out)


def digest(path):
    h = hashlib.sha256()
    with open(path, 'rb') as fh:
        for chunk in iter(lambda: fh.read(65536), b''):
            h.update(chunk)
    return h.hexdigest()


def read_manifest(path):
    if not os.path.exists(path):
        return None
    seen = {}
    with open(path, encoding='utf-8') as fh:
        for line in fh:
            line = line.strip()
            if not line or line.startswith('#'):
                continue
            parts = line.split('  ', 1)
            if len(parts) == 2:
                seen[parts[1]] = parts[0]
    return seen


def write(root, manifest, exts, skip):
    rows = [(rel, digest(full)) for rel, full in tracked(root, exts, skip)]
    os.makedirs(os.path.dirname(manifest) or '.', exist_ok=True)
    with open(manifest, 'w', encoding='utf-8', newline='\n') as fh:
        fh.write('# never-again: sha256 of every watched file when the check last passed.\n')
        fh.write('# Written only on a passing run. Do not edit by hand.\n')
        for rel, d in rows:
            fh.write('%s  %s\n' % (d, rel))
    return len(rows)


def check(root, manifest, exts, skip):
    before = read_manifest(manifest)
    if before is None:
        print('never-verified\t(the check has not passed yet)')
        return 1
    diffs = []
    now = {}
    for rel, full in tracked(root, exts, skip):
        try:
            now[rel] = digest(full)
        except OSError:
            diffs.append(('unreadable', rel))
    for rel, d in now.items():
        if rel not in before:
            diffs.append(('added', rel))
        elif before[rel] != d:
            diffs.append(('changed', rel))
    for rel in before:
        if rel not in now:
            diffs.append(('deleted', rel))
    for reason, rel in sorted(diffs):
        print('%s\t%s' % (reason, rel))
    return 1 if diffs else 0


def main():
    if len(sys.argv) < 5 or sys.argv[1] not in ('write', 'check'):
        sys.stderr.write(__doc__)
        return 2
    mode, root, manifest = sys.argv[1], sys.argv[2], sys.argv[3]
    exts = tuple(e if e.startswith('.') else '.' + e for e in sys.argv[4].split(',') if e)
    skip = set(ALWAYS_SKIP)
    if len(sys.argv) > 5:
        skip |= {s for s in sys.argv[5].split(',') if s}
    if mode == 'write':
        n = write(root, manifest, exts, skip)
        print('manifest written: %d file(s)' % n)
        return 0
    return check(root, manifest, exts, skip)


if __name__ == '__main__':
    sys.exit(main())
