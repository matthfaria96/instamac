#!/usr/bin/env bash
# ui.sh -- dirige o Instamac instalado para verificação visual, sem permissão de
# acessibilidade: os toques entram pelo arquivo de injeção do runtime e a árvore
# de views sai no log.
#
#   scripts/ui.sh start [K=V ...]   fecha, reabre com injeção + dump ligados (e os
#                                   K=V extras no runtime_env) e espera o foco
#   scripts/ui.sh tap X Y           toque em pixels de superfície (origem no topo)
#   scripts/ui.sh swipe X0 Y0 X1 Y1 [ms]
#   scripts/ui.sh key KEYCODE       ex.: 4 = BACK
#   scripts/ui.sh flick FX FY PONTOS [passos]   gesto de trackpad de dois dedos (frações
#                                   da janela; PONTOS negativo avança o feed)
#   scripts/ui.sh raw "verbo ..."   linha(s) cruas para o injetor (hostscroll, hosttap, sleep)
#   scripts/ui.sh text "..."        digita no campo focado
#   scripts/ui.sh shot NOME         captura a janela em build/shots/NOME.png
#   scripts/ui.sh tree [filtro]     último dump de texto (NODE ...), opcionalmente
#                                   filtrado por regex
#   scripts/ui.sh views [opções]    último dump da árvore de views com posições
#                                   absolutas (tools/viewtree.py: --off, --grep, --all)
#   scripts/ui.sh log               caminho do log da sessão
#   scripts/ui.sh stop              fecha e remove o runtime_env de teste
#
# Coordenadas: as do dump (`b=l,t,r,b`) já são pixels de superfície; num monitor
# 1x, 1 px = 1 pt = 1 dp.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUNDLE="${INSTAMAC_APP:-/Applications/Instamac.app}"
# Caminho físico: o processo roda como /private/var/folders/.../T/..., e um
# INSTAMAC_APP vindo de $TMPDIR (/var/folders/.../T//...) não casaria no pgrep --
# o `stop` dizia "fechado" e o app velho seguia aberto.
BUNDLE="$(cd "$BUNDLE" 2>/dev/null && pwd -P || printf '%s' "$BUNDLE")"
APP="$BUNDLE/Contents"
RUNTIME="$APP/Resources/runtime/Resources/macapk-runtime"
ENV_FILE="$APP/android/.macapk/runtime_env"
# Estado FORA de ~/Documents, ~/Desktop e ~/Downloads: o app lê o arquivo de
# injeção, e ler uma pasta protegida faz o macOS abrir o diálogo "Instamac quer
# acessar a pasta Documentos" -- a cada reabertura depois de uma reassinatura
# ad-hoc (a identidade do app muda), com a thread do injetor bloqueada em
# opendir até alguém responder. O diretório temporário do usuário não pede nada.
STATE="${TMPDIR:-/tmp}/instamac-ui"
STATE="${STATE%/}"
INJECT="$STATE/inject.txt"
LOGDIR="$HOME/Library/Logs/macapk"
DUMP_EVERY="${UI_DUMP_EVERY:-240}"
mkdir -p "$STATE" "$ROOT/build/shots"

log_path() { cat "$STATE/log" 2>/dev/null; }
pids() { pgrep -f "$RUNTIME" 2>/dev/null; }

stop_app() {
  local p i
  for p in $(pids); do kill -TERM "$p" 2>/dev/null; done
  for i in $(seq 1 20); do [ -z "$(pids)" ] && return 0; sleep 0.5; done
  for p in $(pids); do kill -KILL "$p" 2>/dev/null; done
  sleep 1
}

inject() { printf '%s\n' "$*" >> "$INJECT"; }

# Pede o dump da árvore na hora (verbo `dump` do injetor) e espera ele sair: uma
# tela parada desenha poucos quadros, e o dump periódico (a cada N quadros) fica
# minutos atrasado.
fresh_dump() {
  local live before i
  live="$(log_path)"
  before="$(grep -c 'TextDump: END seq=' "$live" 2>/dev/null)"
  inject "dump"
  for i in $(seq 1 30); do
    [ "$(grep -c 'TextDump: END seq=' "$live" 2>/dev/null)" -gt "$before" ] && return 0
    sleep 0.2
  done
  echo "aviso: dump novo não saiu em 6 s; mostrando o último" >&2
}

case "${1:-}" in
  start)
    shift
    stop_app
    : > "$INJECT"
    mkdir -p "$(dirname "$ENV_FILE")"
    {
      echo "MACAPK_INJECT_FILE=$INJECT"
      echo "MACAPK_DUMP_TREE_EVERY=$DUMP_EVERY"
      # Janela atrás das outras e sem foco (UI_FOREGROUND=1 desliga): o dono
      # continua usando o Mac; capturas e toques injetados não precisam de foco.
      [ "${UI_FOREGROUND:-0}" = 1 ] || echo "MACAPK_NO_ACTIVATE=1"
      # Atrás das janelas do dono, a janela fica coberta; coberta conta como fora de
      # vista e leva o app a onStop (ADR 0037). Nos testes, só minimizar/ocultar conta
      # (UI_OCCLUSION=1 mantém a regra do produto).
      [ "${UI_OCCLUSION:-0}" = 1 ] || echo "MACAPK_BACKGROUND_ON_OCCLUSION=0"
      # Teste não toca som no Mac do dono (UI_SOUND=1 para medir áudio).
      [ "${UI_SOUND:-0}" = 1 ] || echo "MACAPK_AUDIO_TEST_MUTE=1"
      for kv in "$@"; do echo "$kv"; done
    } > "$ENV_FILE"
    marker="$STATE/.launch"; : > "$marker"
    live=""
    # `open` logo depois de fechar pode falhar com -600 (o LaunchServices ainda
    # está encerrando a instância anterior): tentar de novo.
    for _try in 1 2 3 4; do
      if [ "${UI_FOREGROUND:-0}" = 1 ]; then open -a "$BUNDLE" 2>/dev/null; else open -g -a "$BUNDLE" 2>/dev/null; fi
      for _ in $(seq 1 24); do
        live="$(find "$LOGDIR" -name 'app_com.instagram.android_*.log' -newer "$marker" 2>/dev/null | sort | tail -1)"
        [ -n "$live" ] && break
        sleep 0.25
      done
      [ -n "$live" ] && break
      sleep 2
    done
    [ -n "$live" ] || { echo "erro: launcher não criou log"; exit 2; }
    echo "$live" > "$STATE/log"
    for _ in $(seq 1 "${UI_TIMEOUT:-80}"); do
      grep -q "delivering window focus" "$live" 2>/dev/null && break
      sleep 1
    done
    if grep -q "delivering window focus" "$live"; then
      echo "aberto em $(grep -oE 'delivering window focus to [^ ]+' "$live" | head -1 | awk '{print $NF}')"
    else
      echo "erro: sem foco de janela (log $live)"; exit 1
    fi
    ;;
  tap)   inject "tap $2 $3" ;;
  swipe) inject "swipe $2 $3 $4 $5 ${6:-300}" ;;
  key)   inject "key $2" ;;
  text)  inject "text $2" ;;
  raw)   shift; inject "$*" ;;
  flick)
    # flick FX FY PONTOS [passos]: um gesto de trackpad de dois dedos pelo mesmo
    # caminho do scrollWheel real (began .. changed* .. ended), 8 ms entre
    # eventos, solto ainda com velocidade. FX/FY são frações da janela; PONTOS
    # negativo = dedos para cima (avança o feed).
    awk -v fx="$2" -v fy="$3" -v t="$4" -v n="${5:-12}" 'BEGIN {
      pi = 3.14159265; s = 0
      for (k = 1; k <= n; k++) s += sin(0.75 * pi * k / (n + 1))
      printf "hostscroll %s %s 0 0\n", fx, fy
      for (k = 1; k <= n; k++)
        printf "sleep 8\nhostscroll %s %s 1 %.2f\n", fx, fy, t * sin(0.75 * pi * k / (n + 1)) / s
      printf "sleep 8\nhostscroll %s %s 2 0\n", fx, fy
    }' >> "$INJECT" ;;
  shot)
    [ -x "$ROOT/build/winid" ] || swiftc -O -o "$ROOT/build/winid" "$ROOT/tools/winid.swift"
    w="$("$ROOT/build/winid" | awk -F'\t' '$3=="Instamac" {print $1; exit}')"
    [ -n "$w" ] || { echo "erro: janela do Instamac não encontrada"; exit 1; }
    out="$ROOT/build/shots/${2:?nome}.png"
    screencapture -x -o -l"$w" "$out" && echo "$out"
    ;;
  tree)
    fresh_dump
    live="$(log_path)"
    seq="$(grep -oE 'TextDump: END seq=[0-9]+' "$live" | tail -1 | grep -oE '[0-9]+$')"
    [ -n "$seq" ] || { echo "erro: nenhum dump completo ainda"; exit 1; }
    grep -E "TextDump: (BEGIN|WIN|NODE|END) seq=$seq " "$live" | sed -E 's/^.*TextDump: //' \
      | { if [ -n "${2:-}" ]; then grep -E "$2"; else cat; fi; }
    ;;
  views)
    shift
    fresh_dump
    python3 -I "$ROOT/tools/viewtree.py" "$(log_path)" "$@"
    ;;
  log)  log_path ;;
  stop) stop_app; rm -f "$ENV_FILE"; echo "fechado" ;;
  *) sed -n 2,22p "$0"; exit 2 ;;
esac
