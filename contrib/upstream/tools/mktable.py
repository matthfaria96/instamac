#!/usr/bin/env python3
"""Gera um .smali no formato "tabela de strings" (o X/0000.A00 do Instagram):
um switch com N casos, cada caso devolvendo uma string constante.

Uso: tools/mktable.py <saida.smali> [n_casos]

O metodo passa de 65.535 bytes de bytecode JVM por volta de 6.000 casos, que e
o gatilho do SwitchTableEmitter.
"""

import sys

out = sys.argv[1]
n = int(sys.argv[2]) if len(sys.argv) > 2 else 8000

lines = [
    ".class public Lcom/instamac/repro/StringTable;",
    ".super Ljava/lang/Object;",
    "",
    "# Forma do X/0000.A00: um unico switch, cada caso const-string + return.",
    ".method public static table(I)Ljava/lang/String;",
    "    .registers 2",
    "",
    "    packed-switch p0, :pswitch_data",
    "",
    "    const-string v0, \"default\"",
    "    return-object v0",
    "",
]

for i in range(n):
    lines.append("    :pswitch_%d" % i)
    lines.append("    const-string v0, \"s%d\"" % i)
    lines.append("    return-object v0")
    lines.append("")

lines += ["    :pswitch_data", "    .packed-switch 0x0"]
for i in range(n):
    lines.append("        :pswitch_%d" % i)
lines += ["    .end packed-switch", ".end method", ""]

with open(out, "w") as f:
    f.write("\n".join(lines) + "\n")
print(f"{out}: {n} casos (~{n * 6 + n * 4} bytes de bytecode JVM)")
