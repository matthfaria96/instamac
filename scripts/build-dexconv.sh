#!/usr/bin/env bash
# Compila o tradutor dex->JVM (com.macapk.dex) a partir do vendor + os nossos
# overlays em src/dex, no mesmo alvo do runtime: Java 21.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VENDOR="$ROOT/vendor/macapk/runtime/java/com/macapk/dex"
SRC="$ROOT/build/dexsrc"
CLASSES="$ROOT/build/classes"
JDK="${INSTAMAC_JDK:-/opt/homebrew/opt/openjdk@25}"
JAVAC="$JDK/bin/javac"
JAR="$JDK/bin/jar"

if [ ! -x "$JAVAC" ]; then
  echo "erro: javac nao encontrado em $JAVAC" >&2
  echo "       instale com 'brew install openjdk@25' ou aponte INSTAMAC_JDK" >&2
  exit 1
fi
if [ ! -d "$VENDOR" ]; then
  echo "erro: vendor/macapk ausente; rode 'git submodule update --init --recursive'" >&2
  exit 1
fi

rm -rf "$SRC" "$CLASSES"
mkdir -p "$SRC" "$CLASSES"
cp -R "$VENDOR/." "$SRC/"

# Overlays: cada arquivo em src/dex substitui o homonimo do vendor.
shopt -s nullglob
for f in "$ROOT"/src/dex/*.java; do
  cp "$f" "$SRC/$(basename "$f")"
  echo "overlay: $(basename "$f")"
done

"$JAVAC" --release 21 -nowarn -d "$CLASSES" "$SRC"/*.java

"$JAR" --create --file "$ROOT/build/macapk-dexconv-patch.jar" -C "$CLASSES" .

echo "ok: $CLASSES ($(find "$CLASSES" -name '*.class' | wc -l | tr -d ' ') classes)"
echo "ok: $ROOT/build/macapk-dexconv-patch.jar"
