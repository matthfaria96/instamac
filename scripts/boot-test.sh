#!/usr/bin/env bash
# boot-test.sh <árvore-data-com-<pkg>> | -   -- o app abre ou trava?
#
#   <árvore>  copia essa árvore para data/data/<pkg> antes de abrir
#   -         abre com o que já está em data/data (o caso real: abrir de novo)
#
# Modos (BOOT_ENV):
#   launcher  (padrão) `open` no bundle: launcher -> execv -> runtime, com o
#             ambiente do Instamac. É exatamente o que o Dock faz.
#   bare      runtime direto, sem o ambiente do launcher (para A/B).
#
# Outros knobs:
#   BOOT_TIMEOUT  segundos até declarar TRAVOU (padrão 80)
#   BOOT_HOLD     segundos que o app fica aberto depois do foco (morrer nesse
#                 intervalo = crash pós-boot, exit 3), para escrever o
#                 estado de uma sessão normal antes de fechar (padrão 15)
#   BOOT_OUT      diretório onde guardar log e diagnóstico (padrão build/boot)
#   BOOT_QUIT     term (padrão) | kill -- como fechar o app no fim
#   BOOT_RUNTIME_ENV  "K=V K2=V2": grava <android-root>/.macapk/runtime_env só
#                 durante este teste (o launcher lê o arquivo) e restaura o
#                 anterior no fim. Só vale no modo launcher.
#
# Marcador de sucesso: "delivering window focus" (a atividade recebeu foco). O
# primeiro frame não serve: é o placeholder e aparece mesmo quando trava.
# Ao travar, grava `sample` e `jcmd Thread.print` do processo antes de matá-lo.
#   exit 0 = abriu   1 = travou   2 = erro de uso   3 = abriu e morreu aberto
set -uo pipefail

SRC="${1:?uso: boot-test.sh <árvore data/data/com.instagram...> | -}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUNDLE="${INSTAMAC_APP:-/Applications/Instamac.app}"
BUNDLE="$(cd "$BUNDLE" 2>/dev/null && pwd -P || printf '%s' "$BUNDLE")"   # caminho físico, como o pgrep vê o processo
APP="$BUNDLE/Contents"
DATA="$APP/android/data/data"
MODE="${BOOT_ENV:-launcher}"
TIMEOUT="${BOOT_TIMEOUT:-80}"
HOLD="${BOOT_HOLD:-15}"
QUIT="${BOOT_QUIT:-term}"
OUT="${BOOT_OUT:-$ROOT/build/boot}"
LOGDIR="$HOME/Library/Logs/macapk"
RUNTIME="$APP/Resources/runtime/Resources/macapk-runtime"
JCMD="${JCMD:-/opt/homebrew/opt/openjdk@21/bin/jcmd}"
mkdir -p "$OUT"
STAMP="$(date +%Y%m%d-%H%M%S)"
LOG="$OUT/boot-$STAMP.log"

runtime_pids() { pgrep -f "$RUNTIME" 2>/dev/null; }

stop_all() {
  local sig="$1" p
  for p in $(runtime_pids); do kill "-$sig" "$p" 2>/dev/null; done
}

wait_gone() {
  local i
  for i in $(seq 1 20); do
    [ -z "$(runtime_pids)" ] && return 0
    sleep 0.5
  done
  stop_all KILL
  sleep 1
}

stop_all TERM
wait_gone

if [ "$SRC" != "-" ]; then
  PKG_DIR="$(ls -d "$DATA"/com.instagram.android_* 2>/dev/null | head -1)"
  PKG="$(basename "${PKG_DIR:-$SRC}")"
  chmod -R u+w "$DATA/$PKG" 2>/dev/null
  rm -rf "${DATA:?}/$PKG"
  cp -Rc "$SRC" "$DATA/$PKG" 2>/dev/null || cp -R "$SRC" "$DATA/$PKG" 2>/dev/null \
    || { echo "erro: cópia falhou"; exit 2; }
fi

ENV_FILE="$APP/android/.macapk/runtime_env"
# Sem atrapalhar a tela do dono: a janela abre ATRÁS das outras e o app nunca
# toma o foco (MACAPK_NO_ACTIVATE=1 no runtime + `open -g`). BOOT_FOREGROUND=1
# volta ao comportamento antigo (janela na frente, app ativo).
if [ "${BOOT_FOREGROUND:-0}" != 1 ]; then
  BOOT_RUNTIME_ENV="MACAPK_NO_ACTIVATE=1 MACAPK_BACKGROUND_ON_OCCLUSION=0 MACAPK_AUDIO_TEST_MUTE=1 ${BOOT_RUNTIME_ENV:-}"
  OPEN_FLAGS="-g"
else
  OPEN_FLAGS=""
fi
ENV_SAVED=""
if [ -n "${BOOT_RUNTIME_ENV:-}" ]; then
  mkdir -p "$(dirname "$ENV_FILE")"
  if [ -e "$ENV_FILE" ]; then ENV_SAVED="$OUT/.runtime_env-$STAMP"; cp "$ENV_FILE" "$ENV_SAVED"; fi
  { [ -n "$ENV_SAVED" ] && cat "$ENV_SAVED"; for kv in $BOOT_RUNTIME_ENV; do echo "$kv"; done; } > "$ENV_FILE"
fi
restore_env() {
  [ -n "${BOOT_RUNTIME_ENV:-}" ] || return 0
  if [ -n "$ENV_SAVED" ]; then mv "$ENV_SAVED" "$ENV_FILE"; else rm -f "$ENV_FILE"; fi
}
trap restore_env EXIT

t0=$(date +%s)
case "$MODE" in
  launcher)
    marker="$OUT/.launch-$STAMP"; : > "$marker"
    LIVE=""
    # `open` logo depois de encerrar o app pode responder -600 (o LaunchServices
    # ainda está fechando a instância anterior). Isso é do teste, não do boot:
    # tentar de novo, e recomeçar o relógio a cada tentativa.
    for _try in 1 2 3 4; do
      t0=$(date +%s)
      open $OPEN_FLAGS -a "$BUNDLE" 2>/dev/null
      for _ in $(seq 1 24); do
        LIVE="$(find "$LOGDIR" -name 'app_com.instagram.android_*.log' -newer "$marker" 2>/dev/null | sort | tail -1)"
        [ -n "$LIVE" ] && break
        sleep 0.25
      done
      [ -n "$LIVE" ] && break
      sleep 2
    done
    rm -f "$marker"
    [ -n "$LIVE" ] || { echo "erro: launcher não criou log"; exit 2; }
    PID=""
    for _ in $(seq 1 40); do PID="$(runtime_pids | head -1)"; [ -n "$PID" ] && break; sleep 0.25; done
    ;;
  bare)
    LIVE="$LOG"
    : > "$LIVE"
    "$RUNTIME" --apk "$(ls "$APP"/app/embedded/*.xapk | head -1)" \
      --android-root "$APP/android" >> "$LIVE" 2>&1 &
    PID=$!
    ;;
  *) echo "erro: BOOT_ENV=$MODE (use launcher|bare)"; exit 2 ;;
esac

ok=1
took=""
while [ $(( $(date +%s) - t0 )) -lt "$TIMEOUT" ]; do
  sleep 1
  if grep -q "delivering window focus" "$LIVE" 2>/dev/null; then
    ok=0; took=$(( $(date +%s) - t0 )); break
  fi
  [ -n "$PID" ] && ! kill -0 "$PID" 2>/dev/null && break
done

died=""
if [ $ok -eq 0 ]; then
  # Aberto, como numa sessão: se o processo morrer aqui, é crash pós-boot.
  for s in $(seq 1 "$HOLD"); do
    sleep 1
    if [ -n "$PID" ] && ! kill -0 "$PID" 2>/dev/null; then died="$s"; break; fi
  done
elif [ -n "$PID" ] && kill -0 "$PID" 2>/dev/null; then
  DIAG="$OUT/hang-$STAMP"
  mkdir -p "$DIAG"
  "$JCMD" "$PID" Thread.print > "$DIAG/threads.txt" 2>&1
  sample "$PID" 3 -file "$DIAG/sample.txt" >/dev/null 2>&1
  ps -M -p "$PID" > "$DIAG/ps-threads.txt" 2>&1
fi

if [ "$QUIT" = kill ]; then stop_all KILL; else stop_all TERM; fi
wait_gone

[ "$LIVE" != "$LOG" ] && cp "$LIVE" "$LOG" 2>/dev/null
[ -n "${DIAG:-}" ] && cp "$LOG" "$DIAG/app.log" 2>/dev/null

ACT="$(grep -oE "delivering window focus to [^ ]+" "$LOG" 2>/dev/null | head -1 | awk '{print $NF}')"
if [ $ok -eq 0 ] && [ -n "$died" ]; then
  echo "resultado: ABRIU em ${took}s em ${ACT:-?} e MORREU ${died}s depois do foco (modo $MODE, log $LOG)"
  exit 3
elif [ $ok -eq 0 ]; then
  echo "resultado: ABRIU em ${took}s em ${ACT:-?} (modo $MODE, log $LOG)"
else
  echo "resultado: TRAVOU (modo $MODE, log $LOG${DIAG:+, diagnóstico $DIAG})"
fi
exit $ok
