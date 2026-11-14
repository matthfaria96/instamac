# ADR 0033 — Tela de carregamento nativa

**Status:** aceito em 2026-11-12 (patch `0041`)

## Contexto
A janela abria preta e ficava preta durante toda a abertura (5–17 s), o que parece travado.

## Decisão
Uma tela de AppKit dentro do contêiner da janela, acima da view de renderização: o material
da janela (`NSVisualEffectView`, segue claro/escuro), o ícone do app com sombra e um pulsar lento,
o nome e um indicador giratório pequeno. Sai com fade de 0,3 s no primeiro quadro apresentado que
não é de uma cor só (amostra 8×8 da cópia do quadro, a cada 150 ms), ou aos 45 s.
`MACAPK_LAUNCH_SCREEN=0` desliga.

## Medição (app instalado)
Disco quente: sai aos 8,7 s, já com o feed desenhado; primeira abertura depois de trocar o
binário (disco frio): 16,7 s. O cache AOT segue valendo com o binário novo.
