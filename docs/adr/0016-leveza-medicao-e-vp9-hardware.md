# ADR 0016 — Leveza: medição de base e VP9 por hardware

**Status:** aceito em 2026-11-11 (patch `0022`); o corte grande (vídeo fora do Java2D) está aberto

## Medição de base (Apple M4, macOS 27.2, modo celular, sessão logada)
| estado | CPU (de 1 núcleo) | observação |
|---|---|---|
| 1º minuto depois de abrir | 45–55% | JIT e carga de classes |
| feed parado, sem vídeo | 9–12% | thread principal 8%, compilador 5% (ainda aquecendo) |
| Reels com vídeo | 33–68% | varia com o vídeo |

Memória (feed, 1 min): pegada ~1,0 GB. Java responde pela maior parte: heap 456 MB
reservados (288 MB em uso; coletor serial, sem `-Xmx`) e **230 MB de metadados de classes**
(o Instagram convertido carrega muita classe). Nativo: ~320 MB de `malloc`.

Com vídeo, por thread (`jcmd Thread.print`, duas leituras): thread principal do Android
**26–41%**, `ExoPlayer:Playback` 8,1%, `MediaCodec:VideoPresent` 2,8%. Doze amostras da
pilha da principal: 4 ociosa, 8 em desenho por software do Java2D (`View.draw` →
`MacApkBitmapShaderPaint.getRaster`, `AAShapePipe`, glifos). Ou seja: a cada quadro de
vídeo a árvore de views inteira é redesenhada em Java2D.

## Decisão desta rodada: VP9 pelo VideoToolbox
O runtime decodificava VP9 por software (libvpx) porque um teste antigo concluiu que o Mac
"não tem decodificador VP9" (-12906). O decodificador é **suplementar**: só aparece depois
de `VTRegisterSupplementalVideoDecoderIfAvailable`. Medido aqui num programa à parte: antes
da chamada, sem hardware e -12906; depois, sessão aberta **com hardware** (AV1 idem).
`video_vp9_decode.mm` agora lê os parâmetros de cada quadro-chave, abre a sessão do
VideoToolbox e cai para o libvpx se não houver hardware (`MACAPK_VP9_HW=0` força software).

Resultado nos Reels: `hw=YES (VideoToolbox)` em todos os vídeos, 0 erro de decodificação,
imagem correta (`build/shots/reels-hw.png`); `ExoPlayer:Playback` caiu de 8,1% para 1,1%.
**O total do processo não mudou além do ruído** (43–68% → 42–54%): o custo que sobra é a
thread principal.

## Próximo corte (em ordem de ganho esperado, pelos números acima)
1. **Vídeo numa camada nativa, sem redesenhar a árvore**: quadro do `MediaCodec` direto para
   uma `CALayer` no retângulo do `TextureView` (como o `SurfaceView` já faz), com a interface
   por cima só redesenhada quando ela muda. Alvo: tirar os 26–41% da thread principal.
2. **Metadados de classes (230 MB)** e tempo de abertura: arquivo de classes pré-carregado
   (AOT cache exige JDK 24+; hoje o runtime liga na JDK 21 do Homebrew). Anda junto com o
   item de distribuição (embutir a JVM).
3. **Heap**: `MACAPK_JVM_OPTS` com limites de folga (`-XX:MaxHeapFreeRatio`), sempre com o
   gate de boot 10/10. Ganho estimado menor (dezenas de MB).
4. AV1 pelo VideoToolbox (mesma chamada de registro), se o Instagram passar a servi-lo.
