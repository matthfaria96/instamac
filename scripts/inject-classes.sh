#!/usr/bin/env bash
# inject-classes.sh <dir-de-classes> <runtime>/lib  -- injeta classes compiladas
# nos jars do runtime (android-framework.jar e macapk-loader.jar).
#
# Cada jar recebe as classes que ele JÁ contém (pelo nome da classe externa, para
# que classes internas novas acompanhem). Algumas classes vivem nos dois jars
# (com.macapk.loader.*): as duas cópias são atualizadas, senão o classpath serve
# a antiga. Classe que não existe em nenhum jar entra em android-framework.jar (e,
# se for de com.macapk.loader, também em macapk-loader.jar).
#
# Usado por build-instamac.sh (bundle novo) e, direto, para aplicar um patch Java
# no app instalado sem rebuild:
#   scripts/build-framework.sh
#   scripts/inject-classes.sh build/framework-classes \
#       /Applications/Instamac.app/Contents/Resources/runtime/lib
set -euo pipefail

CLASSES="${1:?uso: inject-classes.sh <classes> <runtime/lib>}"
LIB="${2:?uso: inject-classes.sh <classes> <runtime/lib>}"
JDK="${INSTAMAC_JDK:-/opt/homebrew/opt/openjdk@25}"
JARS=(android-framework.jar macapk-loader.jar)

[ -d "$CLASSES" ] || { echo "erro: $CLASSES não existe" >&2; exit 1; }
for j in "${JARS[@]}"; do
  [ -f "$LIB/$j" ] || { echo "erro: $LIB/$j não existe" >&2; exit 1; }
done

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
for j in "${JARS[@]}"; do unzip -Z1 "$LIB/$j" | sort > "$TMP/$j.list"; done

cd "$CLASSES"
find . -name '*.class' | sed 's|^\./||' | sort > "$TMP/all"
: > "$TMP/android-framework.jar.pick"; : > "$TMP/macapk-loader.jar.pick"
while IFS= read -r c; do
  outer="${c%%\$*}"; outer="${outer%.class}.class"
  placed=0
  for j in "${JARS[@]}"; do
    if grep -qxF "$outer" "$TMP/$j.list"; then echo "$c" >> "$TMP/$j.pick"; placed=1; fi
  done
  if [ "$placed" -eq 0 ]; then
    echo "$c" >> "$TMP/android-framework.jar.pick"
    # com.macapk.loader.* vive nos dois jars: a classe nova acompanha as vizinhas.
    case "$c" in com/macapk/loader/*) echo "$c" >> "$TMP/macapk-loader.jar.pick" ;; esac
  fi
done < "$TMP/all"

for j in "${JARS[@]}"; do
  n="$(wc -l < "$TMP/$j.pick" | tr -d ' ')"
  [ "$n" -gt 0 ] || continue
  args=()
  while IFS= read -r c; do args+=("$c"); done < "$TMP/$j.pick"
  chmod u+w "$LIB/$j"
  "$JDK/bin/jar" --update --file "$LIB/$j" "${args[@]}"
  echo "   $j: $n classe(s)"
done
