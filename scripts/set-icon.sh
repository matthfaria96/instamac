#!/usr/bin/env bash
# set-icon.sh <arquivo.icns|arquivo.png> [--no-install]  -- troca o ícone do Instamac.
#
# A entrada é só a ARTE. O script garante as medidas do padrão Apple e gera todas
# as representações a partir de um único mestre:
#
#   1. pega a maior representação da entrada (1024 px);
#   2. confere contra a grade de ícones do macOS -- corpo de 824x824 centrado num
#      canvas de 1024 (tools/icongrid.swift) -- e normaliza se estiver fora
#      (ícone sangrado ganha máscara squircle e margem; margem errada é
#      reescalada);
#   3. gera TODAS as representações do .icns (16..1024) reduzindo esse mestre, de
#      modo que a proporção é a mesma em qualquer tamanho. Um .icns pronto pode
#      trazer as pequenas fora da grade (medido: 16, 32 e 48 px sangradas num
#      .icns cujo 1024 estava correto), e são elas que um monitor 1x usa.
#
# Depois atualiza todos os lugares onde o ícone vive:
#
#   assets/Instamac.icns                 -> Contents/Resources/AppIcon.icns
#                                           (Finder, Launchpad, Dock em repouso)
#   assets/instamac-icon-1024.png        -> Contents/Resources/InstamacIcon.png
#                                           (MACAPK_APP_ICON: Dock e Cmd-Tab com o
#                                           app rodando; o launcher liga
#                                           MACAPK_ICON_ROUND=0 porque o PNG já
#                                           está na grade)
#   runtime/Resources/macapk_default_icon.png  (fallback do runtime) -- no
#                                           repositório e no bundle
#
# e, salvo --no-install, aplica no app instalado (reassina só o bundle; o binário
# aninhado mantém as entitlements) e pede ao LaunchServices para reler o ícone.
set -euo pipefail

SRC="${1:?uso: set-icon.sh <arquivo.icns|arquivo.png> [--no-install]}"
INSTALL=1
[ "${2:-}" = "--no-install" ] && INSTALL=0
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUNDLE="${INSTAMAC_APP:-/Applications/Instamac.app}"

die() { printf 'erro: %s\n' "$*" >&2; exit 1; }
[ -f "$SRC" ] || die "$SRC não existe"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# 1. A maior representação da entrada.
case "$SRC" in
  *.icns)
    iconutil -c iconset "$SRC" -o "$TMP/in.iconset" >/dev/null 2>&1 \
      || die "$SRC não é um .icns válido (iconutil recusou)"
    RAW=""
    for cand in icon_512x512@2x.png icon_512x512.png icon_256x256@2x.png; do
      [ -f "$TMP/in.iconset/$cand" ] && { RAW="$TMP/in.iconset/$cand"; break; }
    done
    [ -n "$RAW" ] || die "o .icns não tem representação de 512 px ou maior"
    ;;
  *.png) RAW="$SRC" ;;
  *) die "entrada deve ser .icns ou .png" ;;
esac

# 2. Grade da Apple: mede e normaliza para um mestre de 1024.
GRID="$TMP/icongrid"
swiftc -O -o "$GRID" "$ROOT/tools/icongrid.swift" 2>/dev/null \
  || die "não consegui compilar tools/icongrid.swift (swiftc)"
echo "entrada:  $("$GRID" "$RAW" || true)"
MASTER="$TMP/master.png"
"$GRID" "$RAW" "$MASTER" >/dev/null || die "normalização do ícone falhou"
echo "mestre:   $("$GRID" "$MASTER")"

# 3. Todas as representações a partir do mestre.
SET="$TMP/Instamac.iconset"
mkdir -p "$SET"
for spec in 16:icon_16x16 32:icon_16x16@2x 32:icon_32x32 64:icon_32x32@2x \
            128:icon_128x128 256:icon_128x128@2x 256:icon_256x256 512:icon_256x256@2x \
            512:icon_512x512 1024:icon_512x512@2x; do
  px="${spec%%:*}"; name="${spec#*:}"
  if [ "$px" -eq 1024 ]; then cp "$MASTER" "$SET/$name.png"
  else sips -z "$px" "$px" "$MASTER" --out "$SET/$name.png" >/dev/null; fi
done
iconutil -c icns "$SET" -o "$TMP/Instamac.icns" || die "iconutil não gerou o .icns"
for name in icon_16x16 icon_32x32 icon_128x128 icon_512x512@2x; do
  printf '  %-18s %s\n' "$name" "$("$GRID" "$SET/$name.png" | sed 's/ -> .*//')"
done

mkdir -p "$ROOT/assets"
cp "$TMP/Instamac.icns" "$ROOT/assets/Instamac.icns"
cp "$MASTER" "$ROOT/assets/instamac-icon-1024.png"
echo "assets atualizados"

if [ -d "$ROOT/runtime/Resources" ]; then
  cp "$MASTER" "$ROOT/runtime/Resources/macapk_default_icon.png"
  echo "fallback do runtime (repositório) atualizado"
fi

apply_bundle() {
  local app="$1"
  [ -d "$app/Contents/Resources" ] || return 0
  chmod u+w "$app/Contents/Resources" 2>/dev/null || true
  cp "$ROOT/assets/Instamac.icns" "$app/Contents/Resources/AppIcon.icns"
  cp "$ROOT/assets/instamac-icon-1024.png" "$app/Contents/Resources/InstamacIcon.png"
  if [ -d "$app/Contents/Resources/runtime/Resources" ]; then
    cp "$ROOT/assets/instamac-icon-1024.png" \
       "$app/Contents/Resources/runtime/Resources/macapk_default_icon.png"
  fi
  echo "bundle atualizado: $app"
}

apply_bundle "$ROOT/build/Instamac.app"

if [ "$INSTALL" -eq 1 ] && [ -d "$BUNDLE" ]; then
  apply_bundle "$BUNDLE"
  codesign --force --sign - "$BUNDLE" >/dev/null 2>&1 && echo "assinatura refeita (só o bundle)"
  # O Finder e o Dock guardam o ícone por data do bundle: tocar e registrar de novo.
  touch "$BUNDLE"
  LSREG="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
  [ -x "$LSREG" ] && "$LSREG" -f "$BUNDLE" >/dev/null 2>&1 || true
  echo "pronto: reabra o Instamac; se o Dock/Finder ainda mostrar o antigo, 'killall Dock' atualiza o cache"
fi
