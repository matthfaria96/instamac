# ADR 0018 — Vídeo de TextureView numa camada nativa (sem cópia, sem repintar)

**Status:** aceito em 2026-11-12 (patch `0024`); item 5(a) do plano de leveza

## Contexto
ADR 0016 mediu: com um Reel tocando, a thread principal do Android gastava 26–41% de um
núcleo repintando a árvore de views inteira em Java2D a cada quadro, porque cada quadro
decodificado era copiado para um `int[]` (≈6,5 MB por quadro), virava Bitmap e invalidava a
`TextureView`.

## Decisão
O `CVPixelBuffer` decodificado vira o conteúdo de uma `CALayer` própria da `TextureView`
(mesmo mecanismo das camadas por superfície do `SurfaceView`), abaixo da árvore de views:
- zero cópia: `layer.contents = IOSurface do buffer` (retido enquanto está na tela);
- posição e recorte puxados da `TextureView` a cada tick (retângulo visível, `setTransform`,
  `contentsRect` para o pedaço visível);
- a árvore só abre o buraco uma vez; quadro novo não invalida nada; `onSurfaceTextureUpdated`
  continua chegando (agregado) na thread principal.
`MACAPK_TEXTUREVIEW_LAYER=0` volta ao caminho antigo.

## Medição (Reels, vídeo comprovadamente avançando nos dois casos)
| | antigo | camada nativa |
|---|---|---|
| CPU do processo (1 núcleo = 100%) | 38–135% | **15–18%** |
| threads Java | 40% | 14% (resto: JIT aquecendo) |
| memória residente | 1064 MB | 849 MB |

Imagem correta (botões, perfil e "Seguir" por cima do vídeo); vídeo do feed meio fora da tela
mostra a parte certa. Boot 10/10.

## Pegadinha descoberta
Com a janela totalmente coberta (testes em segundo plano) o vídeo do **feed** para sozinho nos
dois caminhos; nos **Reels** ele continua. Medir vídeo sempre nos Reels.

## Aberto
- `TextureView.getBitmap()` no caminho novo não tem o último quadro (nenhum uso visto).
- Rotação em `setTransform` (não só escala/translação) cai para "escondido"; o Instagram não usa.

## Medição seguinte: heap enxuto (não adotado)
`MACAPK_JVM_OPTS=-Xmn40m -XX:MaxHeapFreeRatio=30 -XX:MinHeapFreeRatio=10`, Reels, 2 rodadas
de cada: memória residente 436/511 MB (padrão) × 468/438 MB (enxuto); CPU no ruído (27–49%
nos dois). O heap reservado cai ~100 MB, mas a memória residente não acompanha. Sem ganho
medido → fica o padrão. Retrato da JVM (NMT, Reels): heap 457 MB reservados / ~290 MB em
uso, metadados de classes 232 MB, código compilado 75 MB.
