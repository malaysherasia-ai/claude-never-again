#!/usr/bin/env python3
"""Content manifest for L001 — the shared half of the boot check.

L001 used to ask "is any source file newer than the last verified boot?", which
is a question about mtime, not about content. Restoring a file from a backup,
`cp`-ing it back, checking out the same bytes again, or a tool that rewrites a
file identically all bump the mtime and all fired the hook. That is the hook
crying wolf over a no-op, and a lesson whose flagship hook does that on day one
is the lesson that gets the whole tool uninstalled.

It now asks "does any source file differ from what was booted?", which is a
question about bytes. sha256 per file, stored in the manifest that replaced the
old empty stamp file.

Both `L001.sh` and `L001-mark-boot.sh` call this, rather than each carrying its
own copy of the walk and the hash. Two copies drift, and the drift is silent:
the writer and the checker would disagree about which files matter and the hook
would fire forever or never.

    python L001-manifest.py write <root> <manifest>
    python L001-manifest.py check <root> <manifest>

check exits 0 when the tree matches the manifest, 1 when it does not, printing
one `reason\tpath` line per difference.
"""
import hashlib
import os
import sys

# Everything the browser could load. Widen or narrow this to match whatever
# your own boot check actually exercises.
EXTS = ('.html', '.css', '.js', '.mjs', '.ts')
SKIP = {'.git', '.claude', 'node_modules', 'shots', '.lighthouse', '.vercel'}


def tracked(root):
    """Every source file whose content the boot actually exercised, sorted."""
    out = []
    for base, dirs, files in os.walk(root):
        dirs[:] = [d for d in dirs if d not in SKIP and not d.startswith('.')]
        for f in files:
            if f.endswith(EXTS):
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
    seen = {}
    if not os.path.exists(path):
        return None
    with open(path, encoding='utf-8') as fh:
        for line in fh:
            line = line.strip()
            if not line or line.startswith('#'):
                continue
            parts = line.split('  ', 1)
            if len(parts) == 2:
                seen[parts[1]] = parts[0]
    return seen


def write(root, manifest):
    rows = [(rel, digest(full)) for rel, full in tracked(root)]
    os.makedirs(os.path.dirname(manifest), exist_ok=True)
    with open(manifest, 'w', encoding='utf-8', newline='\n') as fh:
        fh.write('# never-again L001 — sha256 of every source file at the last verified boot.\n')
        fh.write('# Written only when boot-check passes. Do not edit by hand.\n')
        for rel, d in rows:
            fh.write('%s  %s\n' % (d, rel))
    return len(rows)


def check(root, manifest):
    before = read_manifest(manifest)
    if before is None:
        print('no-manifest\t(nothing has been booted yet)')
        return 1

    diffs = []
    now = {}
    for rel, full in tracked(root):
        try:
            now[rel] = digest(full)
        except OSError:
            # Unreadable right now; treat as changed rather than silently passing.
            diffs.append(('unreadable', rel))
    for rel, d in now.items():
        if rel not in before:
            diffs.append(('added', rel))
        elif before[rel] != d:
            diffs.append(('changed', rel))
    for rel in before:
        if rel not in now:
            # Deleting a stylesheet or a page is a real change to what the
            # browser loads, so it still wants a boot before the commit.
            diffs.append(('deleted', rel))

    for reason, rel in sorted(diffs, key=lambda x: (x[0], x[1])):
        print('%s\t%s' % (reason, rel))
    return 1 if diffs else 0


def main():
    if len(sys.argv) != 4 or sys.argv[1] not in ('write', 'check'):
        sys.stderr.write(__doc__)
        return 2
    mode, root, manifest = sys.argv[1], sys.argv[2], sys.argv[3]
    if mode == 'write':
        n = write(root, manifest)
        print('manifest written: %d file(s)' % n)
        return 0
    return check(root, manifest)


if __name__ == '__main__':
    sys.exit(main())
