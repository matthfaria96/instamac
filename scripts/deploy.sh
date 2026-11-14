#!/usr/bin/env bash
# Recompila e instala por cima do Instamac em /Applications.
#
#   scripts/deploy.sh                 reusa o APK que já está no app instalado
#   INSTAMAC_APK=... scripts/deploy.sh   usa outro APK
#
# Fluxo: fecha o app -> compila -> preserva os dados do app instalado (sessão,
# cache convertido) -> assina -> substitui /Applications/Instamac.app -> abre.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TARGET="/Applications/Instamac.app"
BUILD="$ROOT/build/Instamac.app"

say() { printf '\n== %s\n' "$*"; }

# 1. De onde vem o APK
APK="${INSTAMAC_APK:-}"
# 1º lugar: payload/ no repositório (é o que sobrevive a qualquer build)
if [ -z "$APK" ] && [ -d "$ROOT/payload" ]; then
  APK="$(find "$ROOT/payload" -maxdepth 1 -type f \
          \( -name '*.apk' -o -name '*.xapk' -o -name '*.apkm' \) | head -1)"
fi
if [ -z "$APK" ] && [ -d "$TARGET/Contents/app/embedded" ]; then
  APK="$(find "$TARGET/Contents/app/embedded" -maxdepth 1 -type f \
          \( -name '*.apk' -o -name '*.xapk' -o -name '*.apkm' \) | head -1)"
fi
if [ -z "$APK" ] && [ -d "$BUILD/Contents/app/embedded" ]; then
  APK="$(find "$BUILD/Contents/app/embedded" -maxdepth 1 -type f \
          \( -name '*.apk' -o -name '*.xapk' -o -name '*.apkm' \) | head -1)"
fi
[ -n "$APK" ] && [ -f "$APK" ] || {
  echo "erro: não achei o APK do Instagram." >&2
  echo "       rode: INSTAMAC_APK=/caminho/instagram.apk scripts/deploy.sh" >&2
  exit 1
}
# O build apaga build/Instamac.app, então o APK não pode morar dentro dele:
# copia para um lugar estável antes.
mkdir -p "$ROOT/build"
STAGED="$ROOT/build/payload-$(basename "$APK")"
cp "$APK" "$STAGED"
APK="$STAGED"
echo "APK: $APK"

say "1/5 fechando o app instalado"
pkill -f "/Applications/Instamac.app/Contents" 2>/dev/null || true
pkill -f "Instamac.app/Contents/Resources" 2>/dev/null || true
sleep 2

# O build sempre preseeda. Preservar o código antigo do app instalado parece
# economia, mas envelhece o bundle: o `.source-mtime` da árvore antiga não
# corresponde ao APK recém-embutido, e o próximo lançamento reinstala e
# reconverte na máquina de quem usa -- exatamente o que o preseed existe para
# evitar. Custa ~1 min de build; economiza a abertura de todo mundo.
say "2/5 compilando (com preseed)"
INSTAMAC_APK="$APK" "$ROOT/scripts/build-instamac.sh" >/dev/null

# 3. Preserva o que é do usuário sem cruzar keystore.
#
# O que NÃO se copia por padrão: `data/data`, `data/system*`, `user_de`. Uma
# árvore de app traz `.androidkeystore` e prefs cifradas que só abrem com a
# chave mestra da raiz onde nasceram; colar essas prefs numa raiz recém-preseedada
# faz o Instagram morrer no boot (`IllegalArgumentException` em
# AndroidKeyStoreCipherSpi -> FatalDexError -> System.exit(10)) antes de existir
# atividade. Medido neste deploy. `INSTAMAC_KEEP_APP_DATA=1` força a cópia para
# quem sabe que está movendo a chave junto.
SAFE_DIRS="sdcard"
if [ "${INSTAMAC_KEEP_APP_DATA:-0}" = "1" ]; then
  SAFE_DIRS="$SAFE_DIRS data/data data/system data/system_ce data/user_de"
fi
if [ -d "$TARGET/Contents/android" ]; then
  say "3/5 preservando dados do app instalado ($SAFE_DIRS)"
  chmod -R u+w "$TARGET/Contents/android" 2>/dev/null || true
  # O destino também precisa de escrita ANTES da cópia: o preseed deixa
  # data/data/.../lib-compressed em 0555 (armazenamento de device), e o ditto
  # falha tentando sobrescrever arquivo em diretório sem bit de escrita.
  chmod -R u+w "$BUILD/Contents/android" 2>/dev/null || true
  for d in $SAFE_DIRS; do
    [ -e "$TARGET/Contents/android/$d" ] || continue
    mkdir -p "$BUILD/Contents/android/$(dirname "$d")"
    ditto "$TARGET/Contents/android/$d" "$BUILD/Contents/android/$d" \
      || { echo "erro: preservar $d falhou" >&2; exit 1; }
  done
  chmod -R u+w "$BUILD/Contents/android" 2>/dev/null || true
else
  say "3/5 sem dados anteriores (nada a preservar)"
fi

say "4/5 assinando e instalando em $TARGET"
# A cópia trouxe de volta os links absolutos do app instalado; relativizar
# depois da cópia é o que mantém o bundle portátil e assinável.
"$ROOT/scripts/link-relativize.sh" "$BUILD"
codesign --force --sign - "$BUILD" 2>&1 | tail -1
codesign --verify --strict "$BUILD"
chmod -R u+w "$TARGET" 2>/dev/null || true
rm -rf "$TARGET"
ditto "$BUILD" "$TARGET"

say "5/5 abrindo"
open "$TARGET"
echo "ok: $TARGET"
