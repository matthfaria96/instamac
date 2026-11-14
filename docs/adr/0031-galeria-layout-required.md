# ADR 0031 — Grade da galeria: ouvintes de layout disparam no LAYOUT_REQUIRED

**Status:** aceito em 2026-11-12 (patch `0038`); resolve o pendente do ADR 0028

## Contexto
Em "Novo post", as fotos mais recentes ficavam em células cinza em cerca de 3 de cada 4 aberturas.

## O que estava errado (medido)
As miniaturas eram geradas (`MACAPK_THUMB_TRACE`), mas o `X.0DTe` do Instagram só entrega o
bitmap à célula se o pai dela não tiver layout pendente. Se tiver, ele adia a entrega para o
próximo `onLayoutChange` da célula. Esse disparo vem de o `ConstraintLayout` pai medir a célula de
novo com spec diferente (altura UNSPECIFIED, depois EXACTLY 97). No AOSP isso liga
`PFLAG_LAYOUT_REQUIRED` e o `layout()` chama os ouvintes mesmo com o quadro igual. O nosso só
considerava o pedido explícito de layout. Resultado: 19 entregas adiadas, nenhuma disparada.

## Decisão
`View.measure()` aplica a regra do AOSP (forceLayout, ou spec mudou e não é exata ou não bate com
o tamanho medido) e o `layout()` dispara os ouvintes quando ela vale.

## Medição
Antes: 13 de 16 células cinza, 19 adiamentos sem disparo. Depois: 4 de 4 aberturas com a grade
completa e todo adiamento disparado (7/7, 19/19, 14/14). A única célula "cinza" contada é uma
imagem branca.

## Consequências
Para medir a grade, confira que a tela é "Novo post": o Instagram reabre no último modo de
criação, e a câmera do Story conta como "0 cinza" sem ser galeria.
