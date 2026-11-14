#!/usr/bin/env bash
# Atualiza o Instamac instalado SEM tocar no Instagram instalado dentro dele.
#
#   scripts/patch-app.sh
#
# Troca só o que é código nosso: o launcher, o runtime embutido (incluindo os
# jars patchados) e o Info.plist. `Contents/android` (dados, sessão, classes
# convertidas) e `Contents/app` (payload) ficam intactos -- é o que mantém o
# login e o "instalado por natureza".
#
# Use scripts/deploy.sh quando o APK embutido mudar ou quando o tradutor mudar
# (aí o código convertido precisa ser refeito). Aqui não se reconverte nada.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TARGET="${INSTAMAC_TARGET:-/Applications/Instamac.app}"
BUILD="$ROOT/build/Instamac.app"

say() { printf '\n== %s\n' "$*"; }
die() { printf 'erro: %s\n' "$*" >&2; exit 1; }

[ -d "$BUILD" ] || die "sem $BUILD; rode scripts/build-instamac.sh primeiro"
[ -f "$TARGET/Contents/android/.macapk/code"/*/classes.jar ] 2>/dev/null \
  || [ -d "$TARGET/Contents/android" ] || die "$TARGET não parece o Instamac instalado"

say "1/4 fechando o app"
pkill -f "$TARGET/Contents" 2>/dev/null || true
pkill -f "macapk-runtime" 2>/dev/null || true
sleep 3

say "2/4 trocando runtime, launcher e Info.plist"
chmod -R u+w "$TARGET" 2>/dev/null || true
ditto "$BUILD/Contents/Resources" "$TARGET/Contents/Resources"
ditto "$BUILD/Contents/MacOS" "$TARGET/Contents/MacOS"
cp "$BUILD/Contents/Info.plist" "$TARGET/Contents/Info.plist"
# Ícone e plist de identidade viajam no ditto acima; o que NÃO se toca é
# Contents/android (dados + código convertido) e Contents/app (payload).
#
# Uma exceção, e é cache: o Instagram desenha os emojis da fileira rápida com o
# texto do runtime e guarda o resultado em disco (emoji_*). Um runtime novo
# precisa redesenhá-los -- medido: as tiras com quadradinhos sobreviviam à
# correção dos emojis. O app as refaz na primeira vez que precisa.
rm -f "$TARGET"/Contents/android/data/data/*/cache/images.stash/clean/emoji_* 2>/dev/null || true

say "3/4 links relativos + assinatura"
"$ROOT/scripts/link-relativize.sh" "$TARGET"
codesign --force --sign - "$TARGET" 2>&1 | tail -1
codesign --verify --strict "$TARGET" && echo "   assinatura ok"

say "4/4 abrindo"
open "$TARGET"
echo "ok: $TARGET (dados e login preservados)"
