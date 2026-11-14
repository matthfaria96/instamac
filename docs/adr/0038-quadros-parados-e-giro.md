# ADR 0038 — Tela parada sem quadros; girar sem a janela sumir

**Status:** aceito em 2026-11-13 (patch `0051`; launcher)

## Tela parada
Medido (perfil parado, tempo de CPU do processo): 20%, com ~20 repinturas da janela inteira
por segundo. `MACAPK_TRACE_INVALIDATE=1` + `MACAPK_TRACE_INVALIDATE_STACK` (novo) apontaram o
"tique" do `ProgressBar` indeterminado do runtime: invalidava a 20 Hz mesmo oculto (ele ou um
ancestral `GONE`/`INVISIBLE`, alfa 0, fora da janela). Agora só invalida visível.

| perfil parado | quadros pulados (de 300) | CPU do processo |
|---|---|---|
| antes | ~225 | 20% |
| `ProgressBar` só visível | 290 | 13% |
| + batimento espaçado (`MACAPK_FRAMESPEED_HEARTBEAT=1`, padrão no launcher) | 298 | 6,5–10% |

O batimento é o quadro completo de segurança do driver (a cada 30 vsyncs); espaçado, dobra até
120 quando nenhum batimento muda pixel (Instagram: `heartbeat-diff changed=0` em todas as
medições) e volta a 30 com qualquer mudança, toque ou layout.

Ainda: ~6.300 despertares/s do processo parado (não atribuídos por thread: exige `sudo`).

## Feed: o próximo custo
Feed com o vídeo terminado: 24%. O que anima é o letreiro da música (Litho `setTranslationY`/
`setAlpha`, ~37/s) e cada quadro repinta a janela inteira: falta a repintura parcial (o
consumidor S2 existe no driver; a metade S1 — registrar onde cada view invalidada desenhou —
não). É o próximo item, com `MACAPK_DAMAGE_VALIDATE=1` para provar que não falta área.

## Girar
O dono girou numa instância de teste (`MACAPK_NO_ACTIVATE=1`): o relançamento da atividade
chama `CocoaShowWindow`, que nesse modo fazia `orderBack` → a janela ia para trás de tudo
("minimiza e não volta"). No modo normal, o mesmo caminho ativava o app por cima do que
estivesse na frente. Agora uma janela já na tela mantém o lugar e só ganha foco se o app já
estiver ativo. Medido com o verbo novo `rotate`: posição 0 (frente) antes e depois, nos dois
sentidos (412×947 ↔ 1280×832).

Também: o `runtime_env` de teste ficava no app depois de sessões que eu não fechei — quem abria
pelo Dock herdava o modo de teste. Fechar sempre com `scripts/ui.sh stop`.
