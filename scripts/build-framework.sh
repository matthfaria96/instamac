#!/usr/bin/env bash
# Compila as classes Java NOSSAS do runtime, no mesmo alvo de bytecode dele
# (Java 21), para build/framework-classes:
#
#   1. o overlay de src/framework/** (arquivos inteiros que substituem a classe);
#   2. todo .java de vendor/macapk/runtime/java que difere do commit fixado (ou é novo) do
#      submódulo -- os patches locais (identidade Android, ResourceIndex, ...).
#      Um arquivo com overlay em src/framework vence o do vendor.
#
#   scripts/build-framework.sh
#
# scripts/inject-classes.sh põe o resultado nos jars do runtime (os dois:
# android-framework.jar e macapk-loader.jar); build-instamac.sh o chama.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RT="${INSTAMAC_RUNTIME:-$HOME/Library/Application Support/Mac.apk/runtime}"
JDK="${INSTAMAC_JDK:-/opt/homebrew/opt/openjdk@25}"
SRC="$ROOT/src/framework"
CLASSES="$ROOT/build/framework-classes"

die() { printf 'erro: %s\n' "$*" >&2; exit 1; }

[ -x "$JDK/bin/javac" ] || die "javac não encontrado em $JDK/bin/javac"
[ -d "$SRC" ] || die "$SRC não existe"
# Mesma cadeia de busca do build-instamac: o runtime instalado do Mac.apk, o
# runtime do repositório, ou o runtime de um Instamac já instalado.
if [ ! -f "$RT/lib/android-framework.jar" ]; then
  for cand in "$ROOT/runtime" "/Applications/Instamac.app/Contents/Resources/runtime" \
              "$ROOT/build/Instamac.app/Contents/Resources/runtime"; do
    if [ -f "$cand/lib/android-framework.jar" ]; then RT="$cand"; break; fi
  done
fi
[ -f "$RT/lib/android-framework.jar" ] || die "runtime ausente (nem em ~/Library nem no repositório)"

SRCS=()
while IFS= read -r f; do SRCS+=("$f"); done < <(find "$SRC" -name '*.java' | sort)
VENDOR="$ROOT/vendor/macapk"
VJAVA="runtime/java"
if [ -e "$VENDOR/.git" ]; then
  while IFS= read -r rel; do
    [ -n "$rel" ] || continue
    # Overlay em src/framework com o mesmo caminho de classe: ele manda.
    [ -f "$SRC/${rel#"$VJAVA"/}" ] && continue
    [ -f "$VENDOR/$rel" ] && SRCS+=("$VENDOR/$rel")
  done < <({ git -C "$VENDOR" diff --name-only HEAD -- "$VJAVA"
             git -C "$VENDOR" ls-files --others --exclude-standard -- "$VJAVA"; } | grep '\.java$' || true)
fi
[ "${#SRCS[@]}" -gt 0 ] || die "nenhum .java em $SRC nem patch em $VENDOR/$VJAVA"

rm -rf "$CLASSES"
mkdir -p "$CLASSES"

# O classpath é o PRÓPRIO framework do runtime: o overlay compila contra as
# classes reais (AndroidKeyStoreAuthPolicy, MacApkKeyStoreBackend, ...), então
# não existe cópia divergente da API aqui.
"$JDK/bin/javac" --release 21 -nowarn \
  -cp "$RT/lib/android-framework.jar:$RT/lib/macapk-loader.jar" \
  -d "$CLASSES" "${SRCS[@]}"

find "$CLASSES" -name '*.class' | sed "s|$CLASSES/||" | sort | sed 's/^/  /'
echo "ok: $CLASSES ($(find "$CLASSES" -name '*.class' | wc -l | tr -d ' ') classes)"
