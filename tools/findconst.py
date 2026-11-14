#!/usr/bin/env python3
"""findconst.py <classes.jar> <const>[,<const>...] -- classes que usam uma constante.

Procura no constant pool de cada .class do jar por inteiros (0x7f0b4097, ids de
recurso) ou, com o prefixo `s:`, por strings UTF-8 (s:tab_bar). Serve para
achar o código do app que mexe numa view ou lê um recurso, sem descompilar o
jar inteiro. Depois: `javap -c -p -cp <jar> <classe>`.
"""
import struct
import sys
import zipfile

jar, wanted = sys.argv[1], sys.argv[2].split(",")
needles = []
for w in wanted:
    if w.startswith("s:"):
        needles.append((w, w[2:].encode()))
    else:
        needles.append((w, b"\x03" + struct.pack(">i", int(w, 0) - (1 << 32) if int(w, 0) >= 1 << 31 else int(w, 0))))

with zipfile.ZipFile(jar) as z:
    for info in z.infolist():
        if not info.filename.endswith(".class"):
            continue
        data = z.read(info)
        hits = [name for name, n in needles if n in data]
        if hits:
            print(info.filename[:-6].replace("/", "."), " ".join(hits))
