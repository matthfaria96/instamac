#!/usr/bin/env bash
# Testa o SwitchTableEmitter ponta a ponta:
#   fixture/StringTable.dex  ->  classes convertidas  ->  execução verificada
#
# O fixture é um método no formato do X/0000.A00 do Instagram: um único switch
# com 8.000 casos, cada caso devolvendo uma string constante. Ele passa de
# 65.535 bytes de bytecode JVM, então antes do patch o método sai como stub que
# lança UnsupportedOperationException.
#
# Uso:
#   ./run.sh                      usa o runtime do Mac.apk instalado
#   DEX_CLASSPATH=... ./run.sh    usa um build do conversor (classes ou jar)
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
RT="${MACAPK_RUNTIME:-$HOME/Library/Application Support/Mac.apk/runtime}"
JAVA="${JAVA:-$RT/Resources/jre/bin/java}"
# O JRE embutido no runtime não traz javac; procura um JDK de verdade.
if [ -z "${JAVAC:-}" ]; then
  for c in "$(dirname "$JAVA")/javac" /opt/homebrew/opt/openjdk@*/bin/javac "$(command -v javac || true)"; do
    if [ -n "$c" ] && [ -x "$c" ]; then JAVAC="$c"; break; fi
  done
fi
[ -n "${JAVAC:-}" ] && [ -x "$JAVAC" ] || { echo "defina JAVAC=/caminho/javac (JDK 21+)" >&2; exit 1; }
CP="${DEX_CLASSPATH:-$RT/lib/macapk-loader.jar:$RT/lib/android-framework.jar}"

OUT="$(mktemp -d)"
trap 'rm -rf "$OUT"' EXIT

echo "== convertendo fixture"
"$JAVA" -Xmx2g -cp "$CP" com.macapk.dex.Main "$HERE/../fixture/StringTable.dex" "$OUT/table.jar"

echo "== compilando o verificador"
"$JAVAC" --release 21 -d "$OUT" "$HERE/TableCheck.java"

echo "== executando (com -Xverify:all)"
"$JAVA" -Xverify:all -cp "$OUT/table.jar:$OUT" TableCheck
