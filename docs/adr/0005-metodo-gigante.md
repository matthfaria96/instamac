# ADR 0005 — Métodos gigantes: um ainda estubado (P4)

**Status:** um resgatado, um estubado e nunca chamado

`X/09IF.A0p` (68.700 B) foi **resgatado** sem dividir: slots locais numerados por
frequência de uso (`Translator.COMPACT_LOCALS`, patch `0011`) → 61.730 B. É um resgate de
último recurso: só roda para método que nenhuma outra transformação salvou, então o resto
do jar fica byte a byte igual (medido: 1 classe diferente em 228.034).

`X/0bRx.getValues()[I` caiu de 73.744 para 68.914 B e **segue estubado** (faltam 3.379 B).
Nunca foi chamado (`grep -c macapk-stub <log>` = 0 nas telas testadas). Se aparecer: mais
compactação de codegen (o prólogo que zera cada slot custa ~4 B por slot) antes da
máquina de estados (F1b). Içar monitor + clonagem de handler seguem arquivados em
`0004-monitor-hoist-wip.patch`.
