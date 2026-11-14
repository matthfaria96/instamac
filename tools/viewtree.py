#!/usr/bin/env python3
"""viewtree.py <log> [opções] -- lê o último dump de árvore de views do runtime.

O runtime (MACAPK_DUMP_TREE_EVERY) escreve uma linha por view, indentada por
profundidade, com bounds RELATIVOS ao pai. Este script reconstrói as posições
absolutas (somando left/top e a translação `tr=` dos ancestrais) e imprime a
árvore, para responder "onde esta view está na janela?".

  --all            inclui views GONE/zero (padrão: só as visíveis com área)
  --grep REGEX     só linhas que casam (classe, id, texto)
  --off            só views visíveis que caem fora da janela (total ou parcial)
  --depth N        limita a profundidade
  --nth K          usa o K-ésimo dump a partir do fim (1 = último)
"""
import argparse
import re
import sys

LINE = re.compile(
    r"ViewCanvasDriver: (?P<ind> *)(?P<cls>[\w.$]+)@(?P<hash>[0-9a-f]+) "
    r"\[(?P<l>-?\d+),(?P<t>-?\d+)-(?P<r>-?\d+),(?P<b>-?\d+)\] vis=(?P<vis>\d+)(?P<rest>.*)$")
TR = re.compile(r"\btr=(-?[\d.]+),(-?[\d.]+)")
SC = re.compile(r"\bscroll=(-?\d+),(-?\d+)")


def load_dumps(path):
    dumps, cur = [], None
    for raw in open(path, errors="replace"):
        m = LINE.search(raw)
        if not m:
            continue
        depth = len(m.group("ind")) // 2
        if depth == 0:
            cur = []
            dumps.append(cur)
        if cur is None:
            continue
        cur.append((depth, m))
    return dumps


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("log")
    ap.add_argument("--all", action="store_true")
    ap.add_argument("--grep")
    ap.add_argument("--off", action="store_true")
    ap.add_argument("--depth", type=int, default=999)
    ap.add_argument("--nth", type=int, default=1)
    a = ap.parse_args()

    dumps = [d for d in load_dumps(a.log) if len(d) > 5]
    if len(dumps) < a.nth:
        sys.exit("nenhum dump de árvore no log")
    dump = dumps[-a.nth]
    root = dump[0][1]
    win_w, win_h = int(root.group("r")), int(root.group("b"))
    pat = re.compile(a.grep) if a.grep else None

    # stack[d] = (abs_x, abs_y, visível-até-aqui, scroll_x, scroll_y)
    stack = []
    for depth, m in dump:
        del stack[depth:]
        l, t, r, b = (int(m.group(k)) for k in "ltrb")
        rest = m.group("rest")
        px, py, pvis, psx, psy = stack[-1] if stack else (0, 0, True, 0, 0)
        tx = ty = 0.0
        mt = TR.search(rest)
        if mt:
            tx, ty = float(mt.group(1)), float(mt.group(2))
        ax, ay = px + l - psx + tx, py + t - psy + ty
        vis = pvis and m.group("vis") == "0"
        ms = SC.search(rest)
        sx, sy = (int(ms.group(1)), int(ms.group(2))) if ms else (0, 0)
        stack.append((ax, ay, vis, sx, sy))
        w, h = r - l, b - t
        if depth > a.depth:
            continue
        shown = vis and w > 0 and h > 0
        if not a.all and not shown:
            continue
        off = shown and (ax + w <= 0 or ay + h <= 0 or ax >= win_w or ay >= win_h
                         or ax < 0 or ay < 0 or ax + w > win_w or ay + h > win_h)
        if a.off and not off:
            continue
        line = "%s%s@%s abs=%d,%d %dx%d%s%s" % (
            "  " * depth, m.group("cls"), m.group("hash"), ax, ay, w, h,
            "" if vis else " (oculta)", rest)
        if off:
            line += "   <-- FORA DA JANELA %dx%d" % (win_w, win_h)
        if pat and not pat.search(line):
            continue
        print(line[:400])


if __name__ == "__main__":
    main()
