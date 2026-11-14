# ADR 0023 — Desenho mais leve: pixels guardados, furo rápido, texto já formatado

## Contexto
A interface é desenhada no processador (Java2D). Rolando o feed (clone, janela 412×915), um
quadro completo custava ~8 ms, dos quais ~7 ms de desenho da árvore
(`MACAPK_FRAME_PHASE_TRACE=1`). Amostragem própria do desenho (`MACAPK_DRAW_SAMPLER=1`: uma
thread olha a pilha da thread que desenha a cada 1 ms e soma por método):
- ~40%: avatares pintados com `BitmapShader` (amostra pixel a pixel em Java) e fotos
  redimensionadas a cada quadro (`TransformHelper`), sempre iguais de um quadro ao outro;
- 12%: o furo das camadas de vídeo (`DST_OUT` pelo laço genérico do Java2D);
- 10%: refazer o shaping (HarfBuzz) de todo texto a cada quadro.

## Decisão
1. **Pixels guardados** (`Canvas`, `MACAPK_DRAW_CACHE`): foto escalada (inclusive sob o
   `concat` do `ImageView`) e oval/retângulo arredondado com shader de bitmap viram pixels de
   tela, guardados pela imagem e sua geração (muda a cada alteração de pixels), geometria,
   filtro e fração de pixel; os quadros seguintes só copiam. Entra no cache só na **segunda**
   vez que o mesmo desenho aparece (na primeira, guardar tudo gerava ~700 MB/min de lixo e
   paradas de segundos). LRU de 24 MB (`MACAPK_DRAW_CACHE_MB`), no máx. 1,2 MP por imagem.
2. **Furo rápido** (`MACAPK_PUNCH_FAST`): furo opaco, retangular, em pixel inteiro, sob recorte
   retangular = zerar as linhas (mesmo resultado do `DST_OUT`).
3. **Texto já formatado** (`MacApkFont`, `MACAPK_QUANTIZE_CACHE`): o resultado do shaping fica
   guardado por thread (fonte, texto, ligaduras); quem move glifos usa a versão sem cache.

Todos desligáveis (`=0`). Patch 0032.

## Medição (clone, mesmo roteiro de 20 rolagens do feed)
| | desligado | ligado |
|---|---|---|
| quadro só de desenho | 5,16 ms | 2,69 ms |
| quadro completo (desenho) | 7,67 ms | 5,82 ms |
| quadros produzidos | 354 | 1646 |

Perfil do dono nos dois modos: 0,26% dos pixels diferem, nenhum por mais de 24/255.
Gate 10/10 no clone.

## Consequências
- Restam no topo: ovais e arcos sem shader (anéis de story), retângulos, texto rasterizado.
  O próximo salto é não redesenhar a árvore inteira quando só a rolagem mudou.
- +até 24 MB de heap no pior caso (o cache medido ficou em 3–6 MB).

## Adendo — formas simples (medido e descartado)
Cache de ovais/arcos/retângulos arredondados com cor sólida ou gradiente (os anéis de story):
duas rodadas A/B com e sem (`MACAPK_DRAW_CACHE_SHAPES`), o quadro completo ficou **pior**
(2,56→3,23 ms; 3,47→3,83 ms) — montar a chave custa mais que desenhar formas pequenas.
Removido. A admissão passou a lembrar as vistas por objeto de origem com referência fraca (as
4 mais recentes), para não segurar bitmaps na memória; medido: 1952 acertos, 5 imagens
guardadas, 1,9 MB.
