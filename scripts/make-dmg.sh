#!/usr/bin/env bash
# Empacota build/Instamac.app num DMG de arrastar para Applications.
#
#   scripts/make-dmg.sh            -> build/Instamac-<versão>.dmg
# A cópia que entra no DMG passa por release-clean.sh: sem identidade, preferências nem
# caminhos de quem compilou; abre no modo Celular.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/build/Instamac.app"
VERSION="$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$ROOT/build/Instamac.app/Contents/Info.plist")"
DMG="$ROOT/build/Instamac-$VERSION.dmg"
STAGE="$ROOT/build/dmg"

[ -d "$APP" ] || { echo "erro: $APP não existe; rode scripts/build-instamac.sh primeiro" >&2; exit 1; }

[ -d "$STAGE" ] && chmod -R u+w "$STAGE"
rm -rf "$STAGE" "$DMG"
mkdir -p "$STAGE"
ditto "$APP" "$STAGE/Instamac.app"
"$ROOT/scripts/release-clean.sh" "$STAGE/Instamac.app"
codesign --force --sign - "$STAGE/Instamac.app"
ln -s /Applications "$STAGE/Applications"

# Layout simples: o app e o atalho para Applications, nada mais.
hdiutil create -volname "Instamac" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
[ -f "$DMG" ] || { echo "erro: hdiutil não produziu $DMG" >&2; exit 1; }

echo "pronto: $DMG ($(du -sh "$DMG" | cut -f1))"
echo "abra e arraste o Instamac para Applications."
