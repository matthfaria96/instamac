# ADR 0020 — Rodinha do mouse nos Reels e prévia da primeira imagem enviada

**Status:** aceito em 2026-11-12 (patch `0026`)

## Rodinha do mouse nos Reels
**Relato do dono:** passar de vídeo nos Reels pela rodinha "não passa direito, fica meio
travado"; quer a mesma experiência de clicar e arrastar.

**Causa medida:** cada clique da rodinha ia como `ACTION_SCROLL` (rolagem genérica). O
`ViewPager2` dos Reels rola isso em pixels e não encaixa → o Reel parava no meio (4 cliques
deixaram dois Reels meio a meio na tela). O caminho anterior (arrasto sintético) mandava
DOWN/MOVE/UP no mesmo instante → velocidade zero → voltava ao mesmo Reel.

**Decisão:** sobre um paginador vertical a rodinha vira um deslize de arrasto: a sequência de
cliques (até a rodinha parar por 200 ms) = um deslize de 1/4 da altura em 6 passos de 8 ms,
solto em movimento. Listas (feed) continuam com `ACTION_SCROLL`.
`MACAPK_WHEEL_PAGER_DRAG=0` / `MACAPK_WHEEL_GESTURE=0` voltam ao antigo.

**Medição:** 4 cliques para baixo = 4 Reels; 2 para cima = volta 2 (Reel final idêntico ao
de antes do 3º clique). Nada para no meio.

## Primeira imagem enviada sem prévia
**Relato do dono:** ao enviar post pelo menu, a primeira imagem não carrega a prévia, só a
segunda.

**Causa medida:** na primeira abertura do editor o `SurfaceView` informou o tamanho da janela
(412×915) antes de saber que é alimentado por buffers; o Instagram criou o `ImageReader` com
esse tamanho e não o recria quando o tamanho passa a 412×412. O quadro de 412×915 era espremido
no quadrado (foto achatada sobre a galeria). Na segunda abertura a ordem já estava certa.

**Decisão:** buffer do tamanho da janela numa view menor → mostra-se a parte do buffer sob a
view (onde uma superfície do tamanho da janela a põe), sem espremer.

**Medição:** primeira abertura depois de abrir o app mostra a foto inteira.

## Dois anexos: a primeira página do carrossel em branco (adendo)
**Relato do dono:** com dois anexos, o primeiro continua sem prévia.

**Causa medida:** o lado nativo tem UM alvo de desenho por janela (`NativeCocoa.setRenderer`,
o último `SurfaceView` construído). O carrossel do editor tem um `SurfaceView` por página; só a
última recebia `surfaceCreated`, então o renderizador da primeira nunca começava.

**Decisão:** um `SurfaceView` anexado, com tamanho, que não é o alvo nativo, recebe o próprio
`surfaceCreated/Changed` no layout (holder com canvas travado, camada própria), como no AOSP
cada `SurfaceView` tem seu ciclo. `MACAPK_SV_SECONDARY=0` volta ao comportamento antigo.
Patch 0027.

**Medição:** no clone, carrossel com duas fotos: as duas páginas com prévia.
