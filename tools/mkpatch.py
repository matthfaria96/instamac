#!/usr/bin/env python3
"""mkpatch.py OUT DESC_FILE SPEC...   SPEC = path  |  path:1,4,7 (hunks, 1-based)  |  path:~regex (hunks matching)
Monta um patch publicado a partir do diff do submódulo vendor/macapk."""
import re, subprocess, sys
out, desc, specs = sys.argv[1], sys.argv[2], sys.argv[3:]
import os
V = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'vendor', 'macapk')
body = open(desc).read().rstrip() + '\n\n'
for spec in specs:
    path, _, sel = spec.partition(':')
    d = subprocess.run(['git', '-C', V, 'diff', '-U3', '--', path], capture_output=True, text=True).stdout
    if not d and subprocess.run(['git', '-C', V, 'ls-files', '--others', '--exclude-standard', '--', path],
                                capture_output=True, text=True).stdout.strip():
        # arquivo novo (não rastreado): o diff contra /dev/null, com os caminhos a/ b/
        d = subprocess.run(['git', '-C', V, 'diff', '--no-index', '-U3', '--', '/dev/null', path],
                           capture_output=True, text=True).stdout
        d = re.sub(r'(?m)^\+\+\+ b/.*$', '+++ b/' + path, d)
        d = re.sub(r'(?m)^diff --git a/\S+ b/\S+$', f'diff --git a/{path} b/{path}', d)
    if not d: sys.exit(f'sem diff: {path}')
    parts = re.split(r'(?m)^(?=@@ )', d)
    head, hunks = parts[0], parts[1:]
    head = '\n'.join(l for l in head.splitlines() if not l.startswith('index ')) + '\n'
    if sel.startswith('~'):
        rx = re.compile(sel[1:]); keep = [h for h in hunks if rx.search(h)]
    elif sel:
        want = {int(x) for x in sel.split(',')}; keep = [h for i, h in enumerate(hunks, 1) if i in want]
    else:
        keep = hunks
    if not keep: sys.exit(f'nenhum trecho selecionado: {spec}')
    body += head + ''.join(keep)
    print(f'  {path}: {len(keep)}/{len(hunks)} trecho(s)')
open(out, 'w').write(body)
