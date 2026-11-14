# ADR 0039 — Quadros sem mudança visível são pulados; inflação sem reler arquivos; folha de áudio certa

**Status:** aceito em 2026-11-14 (patches `0052`, `0053`)

## Repintura parcial: medida e decisão
O S1 (cada view registra onde desenhou; uma invalidação soma a área antiga e a nova) foi
implementado e validado com `MACAPK_DAMAGE_VALIDATE=1` (o validador desenha tudo, declara a área
e acusa qualquer pixel mudado fora dela). Resultados (`MACAPK_FRAME_PHASE_TRACE=1`):
- desenhar só a área suja custa o mesmo que a janela inteira (1,9 contra 1,7 ms): o custo é
  percorrer a árvore, não pintar pixels;
- 11 de 581 quadros recortados deixaram região velha (um elemento que encolhia na troca de aba).

**Decisão:** o recorte fica desligado (`MACAPK_DAMAGE_CLIP=1` liga). O S1 fica para **pular
quadros em que toda invalidação é invisível** (view ou ancestral com escala 0 ou alfa 0 — o
coração do toque duplo, parado em escala 0, invalidava ~75×/s). Duas voltas completas
validadas: 0 pulos errados (a regra "fora da janela" foi tirada: o validador pegou uma legenda
visível). Com um `SurfaceView` na tela nada é pulado (a camada dele é dimensionada na
apresentação; o editor de foto ficava preto).

Também: `offsetTopAndBottom/LeftAndRight` e `setLeftTopRightBottom` invalidam (AOSP).
`MACAPK_TRACE_DAMAGE=1` diz por que quadros foram completos e quem declarou o quê.

## Inflação de telas (picos de 100–450 ms nas trocas de aba)
`MACAPK_LAYOUT_SAMPLER=1` (novo) mostrou o framework relendo arquivos a cada `TextView`:
- `getFont` relia e reinterpretava a fonte: 29% do layout → cache de `Typeface` por recurso;
- `ColorStateList` de arquivo relida do APK → cache por (id, pilha de estilos do tema);
- construtores e campos por reflexão (com exceção a cada falha) → cache;
- uma linha de log por elemento inflado → só com `MACAPK_TRACE_INFLATE=1`.
Depois disso o tempo amostrado é layout do próprio Instagram. Trocas de aba (8 trocas, AOT
treinado): picos somam 0,9–1,7 s, máximo ~400 ms, todos na primeira visita de cada tela.

## Folha de áudio que abria vazia
Causa: o cache de medida (ADR 0034/patch 0045). Com ele, o conteúdo ficava com a altura de um
instante da animação (6–170 px) em 10 de 12 aberturas; sem ele, 12 de 12 certas. A remedida
perdida não foi encontrada; o cache fica **desligado** (`MACAPK_MEASURE_CACHE=1` liga).
Mantidos: pedido de layout feito durante o layout é refeito depois subindo a cadeia toda (AOSP
`requestLayoutDuringLayout`); `setMinimumHeight/Width` pedem layout.

## Pendente
- Uma captura de tela do Mac escolhida no Novo post deixa a prévia do editor preta (a foto da
  comida funciona); sem erro no log.
- O toque em "Post" da folha Criar às vezes só fecha a folha (nos testes; intermitente).
- Picos de primeira visita de tela (~400 ms) são layout do app; restam JIT/AOT.

## Adendo (2026-11-14, noite): varredura de Stories e Direct; módulos
- **Erro meu, corrigido:** `scripts/build-notifier.sh` fazia `chmod -R u+w` em todo o
  `Contents`, o que tirou o 0444 dos módulos baixados (`modules/*/download.zip`); pytorch,
  executorch e spm deixaram de carregar ("Downloaded module file must be read only"). Módulos
  de volta a 0444; o script só mexe em `Contents/Helpers`.
- **Stories:** destaque da própria conta abre, o vídeo toca, a barra de progresso anda, tocar
  avança, Voltar fecha. A faixa escura no topo é o cartão 9:16 centralizado numa tela 20:9
  (comportamento do Instagram).
- **Direct:** caixa de entrada correta (vazia na conta de teste, sugestões, avatares padrão).
  Bolhas de conversa (9-patch) não testadas: exigiria enviar mensagem.
- **Avatar escuro:** só o da própria conta ("Seu story", "Sua nota", aba Perfil); o avatar
  padrão de outras contas aparece. Causa não encontrada (drawable de imagem do Instagram em
  estado de espera; nenhum download nem erro no log).
- **Editor preto:** acontece com `Captura de tela 2026-11-13 às 00.34.19.png` (PNG 1492×1195,
  nome em forma decomposta); a foto JPEG funciona. O carregador é nativo do Instagram (caminho do
  arquivo); só um `eglSwapBuffers` e nenhum quadro entregue; sem erro no log.

## Adendo (2026-11-14): imagens e ícones sem serrilhado (patch `0054`)
O dono notou fotos e ícones "serrilhados / detalhados demais". Duas causas:
- **Recorte duro:** o Java2D recorta formas não retangulares sem suavização; todo avatar redondo
  e card arredondado tinha borda em degraus. Agora `clipPath` logo após um `save` desenha numa
  camada do tamanho da forma e, no `restore`, aplica a forma suavizada como máscara.
  `MACAPK_SOFT_CLIP=0` desliga.
- **Redução de uma vez só:** num Mac 1x, fotos de 1080 px viram ~412 px e avatares ~85 px; um passo
  bilinear lê 4 de cada N×N pixels. As reduções guardadas em cache passam por metades sucessivas
  (mipmap) e o `BitmapShader` escolhe o nível pela escala. `MACAPK_MIP_DOWNSCALE=0` desliga.
Medido: bordas lisas na ampliação (antes em degraus); desenho 1,9 → 2,2–2,9 ms por quadro.
