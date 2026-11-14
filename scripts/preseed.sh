#!/usr/bin/env bash
# Prepara o Instagram DENTRO do bundle, antes da assinatura.
#
#   scripts/preseed.sh build/Instamac.app
#
# O que "instalado por natureza" exige: o bundle sai do build com o app já
# descompactado, as classes já convertidas para a JVM e as libs nativas já
# traduzidas. Assim a primeira abertura do Instamac é indistinguível da
# segunda -- nenhuma tela de espera, nenhuma conversão na máquina de quem usa.
#
# Como: o próprio runtime faz o trabalho no seu modo normal de instalação
# (o mesmo caminho de uma primeira abertura), com o --android-root apontando
# para Contents/android. O gatilho de parada é o primeiro frame apresentado,
# medido no log do runtime -- não um "sleep" chutado.
#
# Duas passadas:
#   1. fria   -- instala, converte (DEX->JAR) e traduz as libs; mata no frame.
#   2. morna  -- relança e exige chegar ao frame SEM "cold install (DEX->JAR)".
#                É a prova de que o bundle embutido acorda quente.
#
# Variáveis:
#   INSTAMAC_PRESEED_TIMEOUT   segundos por passada (padrão 1800)
#   INSTAMAC_PRESEED_VERIFY=0  pula a passada morna (build mais rápido)
set -euo pipefail

APP="${1:?uso: scripts/preseed.sh <Instamac.app>}"
[ -d "$APP" ] || { printf 'erro: %s não é um bundle\n' "$APP" >&2; exit 1; }
# Absoluto: o runtime é executado com o cwd em build/, então um caminho
# relativo herdado da linha de comando deixaria de resolver.
APP="$(cd "$APP" && pwd -P)"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ANDROID="$APP/Contents/android"
RUNTIME="$APP/Contents/Resources/runtime/Resources/macapk-runtime"
EMBEDDED="$APP/Contents/app/embedded"
LOG="$ROOT/build/preseed.log"
PIDFILE="$ROOT/build/preseed.pid"
TIMEOUT="${INSTAMAC_PRESEED_TIMEOUT:-1800}"
VERIFY="${INSTAMAC_PRESEED_VERIFY:-1}"

# O frame apresentado é o único sinal que não mente: ele vem depois do
# install (data/app), da conversão (classes.jar) e da tradução das libs.
MARKER='first frame presented\|delivering window focus'

die() { printf 'erro: %s\n' "$*" >&2; exit 1; }

stop_app() {
  local pid="$1"
  kill -TERM "$pid" 2>/dev/null || true
  for _ in $(seq 1 30); do
    kill -0 "$pid" 2>/dev/null || { wait "$pid" 2>/dev/null || true; return 0; }
    sleep 1
  done
  kill -KILL "$pid" 2>/dev/null || true
  wait "$pid" 2>/dev/null || true
}

# Roda o runtime uma vez e devolve 0 quando o primeiro frame aparece.
# O duplo fork tira o processo da tabela de jobs do shell: sem isso o bash
# imprime "Terminated: 15" no meio do build a cada parada, ruído que esconde
# erro de verdade.
run_until_frame() {
  local pass="$1" deadline start
  : > "$LOG"
  # Janela atrás, sem foco e muda: o build roda enquanto o dono usa o Mac.
  ( ( cd "$ROOT/build" && MACAPK_NO_ACTIVATE=1 MACAPK_AUDIO_TEST_MUTE=1 exec "$RUNTIME" \
        --apk "$APK" --android-root "$ANDROID" ) >>"$LOG" 2>&1 & echo $! > "$PIDFILE" )
  APP_PID="$(cat "$PIDFILE")"
  start=$SECONDS
  deadline=$((SECONDS + TIMEOUT))
  while (( SECONDS < deadline )); do
    if grep -q "$MARKER" "$LOG" 2>/dev/null; then
      printf '   %s: frame em %ds\n' "$pass" "$((SECONDS - start))"
      stop_app "$APP_PID"
      return 0
    fi
    if ! kill -0 "$APP_PID" 2>/dev/null; then
      printf 'erro: o runtime morreu na passada %s. Últimas linhas do log:\n' "$pass" >&2
      tail -40 "$LOG" >&2
      return 1
    fi
    sleep 1
  done
  printf 'erro: %s não chegou ao primeiro frame em %ds. Últimas linhas:\n' \
    "$pass" "$TIMEOUT" >&2
  tail -40 "$LOG" >&2
  stop_app "$APP_PID"
  return 1
}

[ -x "$RUNTIME" ] || die "runtime ausente em $RUNTIME (monte o bundle antes)"

# APK fonte: o nome que o build gravou em EMBEDDED, ou o maior do bundle.
APK=""
if [ -f "$EMBEDDED/EMBEDDED" ]; then
  APK="$EMBEDDED/$(cat "$EMBEDDED/EMBEDDED")"
fi
if [ ! -f "$APK" ]; then
  APK="$(find "$EMBEDDED" -maxdepth 1 -type f \
          \( -name '*.apk' -o -name '*.xapk' -o -name '*.apkm' -o -name '*.apks' \) \
          -exec stat -f '%m %N' {} + 2>/dev/null | sort -n | tail -1 | cut -d' ' -f2-)"
fi
[ -n "$APK" ] && [ -f "$APK" ] || die "nenhum APK em $EMBEDDED (o build não embutiu payload)"

mkdir -p "$ROOT/build" "$ANDROID"

jar_of() { ls -1 "$ANDROID"/.macapk/code/*/classes.jar 2>/dev/null | head -1; }
marker_of() { find "$ANDROID/data/app" -name .installed 2>/dev/null | head -1; }

warm=0
if [ -n "$(jar_of)" ] && [ -n "$(marker_of)" ] && [ "$VERIFY" = "0" ]; then
  warm=1
  echo "   já preparado (classes.jar + data/app): só validando"
fi

if [ "$warm" = "0" ]; then
  echo "   passada fria: instalar, converter e traduzir dentro do bundle"
  run_until_frame "fria" || die "preseed falhou"
fi

JAR="$(jar_of)"
MARK="$(marker_of)"
[ -n "$JAR" ]  || die "classes.jar não apareceu em $ANDROID/.macapk/code (conversão incompleta)"
[ -n "$MARK" ] || die "marcador .installed não apareceu em $ANDROID/data/app (instalação incompleta)"

if [ "$VERIFY" = "1" ]; then
  # A passada morna é o gate de verdade: se ela re-converter, o bundle não
  # está "instalado por natureza" -- está só com um cache que expira.
  echo "   passada morna: o bundle tem que acordar sem converter"
  run_until_frame "morna" || die "o bundle não acorda quente"
  grep -q 'cold install (DEX->JAR)' "$LOG" \
    && die "a passada morna re-converteu o código: o cache não está sendo aceito"
fi

# Restos de uma execução morta não viajam no bundle.
rm -f "$ROOT/build"/hs_err_pid*.log 2>/dev/null || true
rm -f "$APP"/hs_err_pid*.log 2>/dev/null || true

printf '   preparado: %s (classes.jar %s, libs %s arquivos)\n' \
  "$(basename "$(dirname "$JAR")")" \
  "$(du -h "$JAR" | cut -f1)" \
  "$(find "$(dirname "$JAR")/lib_native" -type f 2>/dev/null | wc -l | tr -d ' ')"
