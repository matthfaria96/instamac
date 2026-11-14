# ADR 0014 — Editor de foto: janela EGL sobre `ImageReader` e `Transaction.setBuffer`

**Status:** aceito em 2026-11-11 (patch `0020`)

## Contexto
O editor de foto abria com a foto importada e a **prévia preta** (ADR 0013). Medido: em
API 34+ o Instagram (`X.0Fpu`) não desenha na `Surface` do `SurfaceView`. Ele cria um
`ImageReader` (RGBA_8888, do tamanho que `surfaceChanged` informou), renderiza nele com EGL
próprio e mostra cada `Image` com `SurfaceControl.Transaction.setBuffer(filho,
image.getHardwareBuffer(), fence, callback)` num filho de `SurfaceView.getSurfaceControl()`.
O runtime recusava a `Surface` do leitor (`EGL_NO_SURFACE`), `setBuffer` com
`HardwareBuffer` nem existia e `Image.getFence()` também não.

## Decisão
Implementar o caminho do aparelho, sem atalho específico do Instagram:
1. `MacApkGlWindow` aceita `ImageReader` como consumidor (mesmo pbuffer + leitura no
   `eglSwapBuffers` que já servia `SurfaceTexture`).
2. `ImageReader` ganha o lado produtor: fila limitada a `maxImages`, `acquireNextImage` /
   `acquireLatestImage`, `Image` com um plano RGBA, `getHardwareBuffer()` com os pixels e
   `getFence()`. `Bitmap.wrapHardwareBuffer` copia esses pixels; `PixelCopy.request(Surface)`
   responde com o último quadro do leitor.
3. `SurfaceControl` guarda pai e o `SurfaceView` dono; `Transaction.reparent`/`setBuffer`
   têm efeito no `apply()`: o buffer é mostrado pelo caminho de um quadro `lockCanvas`
   (camada própria da view, no retângulo dela). O callback de liberação sai por outra thread.
4. Um `SurfaceView` que recebe um filho de `SurfaceControl` passa a informar o **tamanho da
   própria view** (regra "Canvas"), não o da janela.

## Medição
Envio de 1 JPEG ao Feed: a superfície é reanunciada em 412×412 (antes 412×915), a janela
sobre o leitor nasce nesse tamanho, o primeiro quadro aparece em `0,237 412x412` e **o
editor mostra a foto** (`build/shots/editor-1.png`). A imagem 1080×1080 que o app renderiza
para o envio (`files/pending_media_images/*.webp`) foi aberta e está correta. Reels/feed
seguem com quadro `RICH`; `boot-loop.sh 10 -` → 10/10.

## Aberto
- A miniatura em "Novo post" fica no marcador de carregamento (cosmético; sem erro no log;
  não vem de `PixelCopy`).
- Filtros, ajustes e recorte dentro do editor não foram exercitados; publicar de fato
  também não (agiria na conta do dono).
- Story e Reel caem na página de câmera do Instagram, que aparece **vazia** (nenhuma view
  dentro do contêiner). É outro assunto: câmera — e abrir a câmera pede permissão ao macOS.
- Custo: um `glReadPixels` síncrono + conversão por quadro. Para foto é irrelevante; para
  prévia de vídeo no editor o caminho certo é IOSurface sem cópia (ver item Leveza).
