#!/usr/bin/env bash
# Recupera o Instamac de um estado de dados que trava o boot.
#
#   scripts/reset-app-data.sh            move os dados do app para /tmp e sobe limpo
#   scripts/reset-app-data.sh --keep     move, mas não abre
#
# Sintoma que isto resolve: o app abre, a janela fica preta e o log mostra o
# main looper preso em "#1" com a tempestade do shim:
#
#   [null-recovery] ... (x18-trap: zeroing X dest, advancing PC)
#   [I] Looper: MACAPK_REAL_LOOPER: main loop dispatched #1 on thread=main
#
# Medido: é o ESTADO DA APLICAÇÃO, não o app nem o runtime. A mesma build, com
# `data/data/<pkg>` recém-criada, chega ao feed; com a árvore que ficou de um
# crash/resize anterior, trava em libstartup.so (+0x445084, folly::dynamic
# hash/walk com ponteiro inválido). O login NÃO se perde: a conta mora em
# `data/system` (AccountManager), que este script não toca.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="${INSTAMAC_APP:-/Applications/Instamac.app}"
DATA="$APP/Contents/android/data/data"
PKG_GLOB="com.instagram.android_*"
OPEN="${1:-}"

say() { printf '\n== %s\n' "$*"; }
[ -d "$DATA" ] || { echo "erro: $DATA não existe" >&2; exit 1; }

say "limpando caches de janela"
# O runtime guarda decisões de janela aqui; uma delas pode fixar um tamanho
# ruim (medido: janela 1080x574 fora da tela). Não é dado do usuário.
for c in "$DATA/.windowtraits" "$DATA/.macapk-settings"; do
  [ -e "$c" ] && mv "$c" "/tmp/instamac-cache-$(basename "$c")-$(date +%s)" 2>/dev/null \
    && echo "   movido: $(basename "$c")"
done

say "fechando o app"
pkill -f "$APP/Contents" 2>/dev/null || true
sleep 3

STAMP="$(date +%Y%m%d-%H%M%S)"
DEST="/tmp/instamac-data-$STAMP"
mkdir -p "$DEST"
moved=0
shopt -s nullglob
for d in "$DATA"/$PKG_GLOB; do
  [ -d "$d" ] || continue
  chmod -R u+w "$d" 2>/dev/null || true
  mv "$d" "$DEST"/
  moved=$((moved + 1))
  echo "   movido: $(basename "$d") -> $DEST"
done
[ "$moved" -gt 0 ] || echo "   (nada em $DATA) -- já está limpo"

say "pronto"
echo "   dados antigos: $DEST (login em data/system preservado)"
if [ "$OPEN" != "--keep" ]; then
  open "$APP"
  echo "   abrindo $APP"
fi
