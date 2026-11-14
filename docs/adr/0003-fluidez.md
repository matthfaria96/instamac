# ADR 0003 — Fluidez de uso (P2)

**Status:** em andamento

Medido: `fps 89.9` estável, mas `MainThreadWatchdog: RED` aparece ~19× numa sessão
(stalls de ~1 s) e o app consome ~100% de CPU. Log já foi cortado (P0 do custo). Suspeitos:
- recuperação de faltas do shim ainda disparando (amostra pega `macapk_segv_handler`);
- `folly`/Tigon fazendo trabalho de init em thread de UI;
- caminho de desenho Java2D + readback no canvas.

Próximos passos: medir input-to-frame (não só fps), contar `[null-recovery]` por segundo,
testar `MACAPK_JVM_OPTS` (heap maior / G1) com critério de boot 10/10.
