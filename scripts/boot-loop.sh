#!/usr/bin/env bash
# boot-loop.sh [N] [árvore|-]  -- taxa real de boot: N aberturas seguidas.
#
# A primeira abertura usa a árvore dada (ou "-" = o que está em data/data); as
# seguintes reabrem com o estado que a anterior deixou, que é o uso real. O
# critério de pronto do P0 é N=10 sem nenhum TRAVOU.
#
# Repassa BOOT_ENV/BOOT_TIMEOUT/BOOT_HOLD/BOOT_QUIT para boot-test.sh.
# Saída: uma linha por abertura e um resumo "k/N abriram"; logs em BOOT_OUT.
set -uo pipefail

N="${1:-10}"
FIRST="${2:--}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export BOOT_OUT="${BOOT_OUT:-$ROOT/build/boot/loop-$(date +%Y%m%d-%H%M%S)}"
mkdir -p "$BOOT_OUT"

ok=0
for i in $(seq 1 "$N"); do
  src="-"
  [ "$i" -eq 1 ] && src="$FIRST"
  line="$("$ROOT/scripts/boot-test.sh" "$src" | tail -1)"
  case "$line" in *MORREU*) ;; *ABRIU*) ok=$((ok + 1)) ;; esac
  printf '%2d/%d  %s\n' "$i" "$N" "$line" | tee -a "$BOOT_OUT/summary.txt"
done
printf 'resumo: %d/%d abriram (modo %s)\n' "$ok" "$N" "${BOOT_ENV:-launcher}" | tee -a "$BOOT_OUT/summary.txt"
[ "$ok" -eq "$N" ]
