#!/usr/bin/env bash
# Roda o tradutor dex->JVM (o NOSSO, de build/classes) sobre um APK, com o
# debug do divisor ligado. Nao abre o app, nao mexe no runtime instalado.
#
#   scripts/convert-apk.sh <arquivo.apk> [saida.jar]
#
# Variaveis:
#   DEX2JVM_SPLIT_DEBUG=1     log do divisor (preferido/recusado)
#   DEX2JVM_SPLIT_DUMP=A00    dump da geometria try/catch de metodos cujo tag
#                             contenha A00 (diagnostico do Instamac)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APK="${1:?uso: scripts/convert-apk.sh <apk> [saida.jar]}"
OUT="${2:-$ROOT/build/$(basename "${APK%.*}").jar}"
RT="${INSTAMAC_RUNTIME:-$HOME/Library/Application Support/Mac.apk/runtime}"
JAVA="$RT/Resources/jre/bin/java"

[ -x "$JAVA" ] || { echo "erro: runtime do Mac.apk nao instalado ($JAVA)" >&2; exit 1; }
[ -d "$ROOT/build/classes" ] || { echo "erro: rode scripts/build-dexconv.sh primeiro" >&2; exit 1; }

mkdir -p "$(dirname "$OUT")"

export DEX2JVM_SPLIT_DEBUG="${DEX2JVM_SPLIT_DEBUG:-1}"

echo "converter: $ROOT/build/classes (primeiro no classpath)"
echo "apk:       $APK"
"$JAVA" -Xmx6g \
  -cp "$ROOT/build/classes:$RT/lib/macapk-loader.jar:$RT/lib/android-framework.jar" \
  com.macapk.dex.Main "$APK" "$OUT"

echo "saida: $OUT"
