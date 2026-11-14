#!/usr/bin/env bash
# train-aot.sh [app] -- treina o cache AOT da JVM 25 embutida (ADR 0019).
#
# Abre o app ATRÁS das outras janelas e sem foco, passa pelas abas (feed, Reels,
# Direct, busca, perfil -- só navegação, nada é enviado), encerra com Cmd+Q (o
# runtime sai por Runtime.halt nesse modo, e a JVM monta o cache) e põe o arquivo
# onde o runtime procura (o caminho sai do próprio log: depende da JRE, dos jars e
# das opções). Fecha o app se estiver aberto. Refaça depois de trocar runtime/jars.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export INSTAMAC_APP="${1:-/Applications/Instamac.app}"
STATE="${TMPDIR:-/tmp}/instamac-aot"; mkdir -p "$STATE"
HK="$STATE/hostkey.txt"; OUT="$STATE/treino.aot"
: > "$HK"; rm -f "$OUT" "$OUT.config"
UI_TIMEOUT=200 "$ROOT/scripts/ui.sh" start "MACAPK_DEBUG_HOSTKEY_FILE=$HK" "MACAPK_AOT_RECORD=$OUT" || true
LOG="$("$ROOT/scripts/ui.sh" log)"
TARGET="$(grep -m1 -oE 'the runtime looks for [^)]+' "$LOG" | sed 's/the runtime looks for //')"
[ -n "$TARGET" ] || { echo "erro: o runtime não entrou em modo de treino (JVM 21? veja $LOG)" >&2; "$ROOT/scripts/ui.sh" stop; exit 1; }
sleep 20
for x in 123 205 287 369 41; do "$ROOT/scripts/ui.sh" tap "$x" 890; sleep 12; done
"$ROOT/scripts/ui.sh" flick 0.5 0.6 -300; sleep 8
printf 'cmd+q\n' >> "$HK"
RT_BIN="$INSTAMAC_APP/Contents/Resources/runtime/Resources/macapk-runtime"
for _ in $(seq 1 120); do pgrep -f "$RT_BIN" >/dev/null || break; sleep 5; done
rm -f "$INSTAMAC_APP/Contents/android/.macapk/runtime_env"
[ -s "$OUT" ] || { echo "erro: cache não gerado (veja $LOG)" >&2; exit 1; }
mkdir -p "$(dirname "$TARGET")"
mv "$OUT" "$TARGET"
# Os caches de binários anteriores nunca mais casam com a chave: só ocupam disco
# (~200 MB cada). Só no treino do app instalado: o clone de teste divide a pasta, e
# treiná-lo não pode apagar o cache do app do dono.
if [ "$INSTAMAC_APP" = /Applications/Instamac.app ]; then
    for old in "$(dirname "$TARGET")"/macapk-*.aot; do
        [ "$old" = "$TARGET" ] || rm -f "$old"
    done
fi
echo "ok: cache AOT $(du -h "$TARGET" | cut -f1) em $TARGET"
