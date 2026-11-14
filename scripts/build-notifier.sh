#!/usr/bin/env bash
# build-notifier.sh <app> -- builds InstamacNotifier.app (tools/notifier/main.swift) into
# <app>/Contents/Helpers: the helper that posts Instamac's notifications to the macOS
# Notification Center (ADR 0037). Signed with the stable local identity
# (scripts/sign-identity.sh), so the notification permission survives rebuilds.
# The outer bundle must be signed again afterwards (codesign --force --sign - <app>).
set -euo pipefail
APP="${1:?uso: build-notifier.sh <Instamac.app>}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$APP/Contents/Helpers/InstamacNotifier.app"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

swiftc -O -o "$TMP/InstamacNotifier" "$ROOT/tools/notifier/main.swift" \
    -framework Cocoa -framework UserNotifications

# Só Helpers: um chmod -R u+w em Contents tira o 0444 dos módulos baixados do Instagram
# (data/data/<pkg>/modules/*/download.zip), e eles deixam de carregar (PEGADINHAS).
mkdir -p "$APP/Contents/Helpers"
chmod -R u+w "$APP/Contents/Helpers" 2>/dev/null || true
rm -rf "$OUT"
mkdir -p "$OUT/Contents/MacOS" "$OUT/Contents/Resources"
cp "$TMP/InstamacNotifier" "$OUT/Contents/MacOS/InstamacNotifier"
cp "$ROOT/assets/Instamac.icns" "$OUT/Contents/Resources/AppIcon.icns"
printf 'APPL????' > "$OUT/Contents/PkgInfo"
cat > "$OUT/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleIdentifier</key><string>dev.instamac.notifier</string>
  <key>CFBundleName</key><string>Instamac</string>
  <key>CFBundleDisplayName</key><string>Instamac</string>
  <key>CFBundleExecutable</key><string>InstamacNotifier</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSUIElement</key><true/>
  <key>NSPrincipalClass</key><string>NSApplication</string>
</dict>
</plist>
PLIST
SIGN_ID="$("$ROOT/scripts/sign-identity.sh")"
codesign --force -s "$SIGN_ID" --identifier dev.instamac.notifier "$OUT" 2>/dev/null
echo "ok: $OUT (assinatura: $SIGN_ID)"
