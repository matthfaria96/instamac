# ADR 0007 — Scroll do trackpad: o conteúdo anda desde o primeiro delta

**Status:** aceito em 2026-11-11 (patch `0016`); sensação final a validar pelo dono

## Contexto
O scroll de dois dedos vira um dedo sintético (DOWN/MOVE/UP), o alvo mais compatível
(listas, pager dos Reels, puxar-para-atualizar). O DOWN era segurado por 6 pt e o Android
ainda descarta o *touch slop* (8 dp): os primeiros ~14 pt de cada gesto não moviam nada, e
um scroll curto e lento não movia nunca. O horário dos eventos era o do processamento no
loop, não o da entrega — rajadas depois de um quadro lento distorciam a velocidade do
arremesso.

## Decisão
1. O dedo desce no primeiro delta e já começa 9 pt adiante no eixo do gesto: o app entra em
   arrasto na hora e consome o slop desse salto; daí em diante é 1:1.
   `MACAPK_SCROLL_SLOP_JUMP=0` volta ao comportamento antigo.
2. O evento carrega o horário em que o host o entregou (thread do AppKit).
3. MOVEs que se acumulam atrás de um quadro lento viram um só (o mais novo).
4. O arremesso continua sendo o do Android (a cauda de inércia do macOS segue descartada):
   usar a inércia do macOS como arrasto dispararia puxar-para-atualizar no topo.

## Medição
Scroll lento de 5 / 12 / 30 / 60 pt move o feed 6 / 13 / 31 / 54 px (antes: 5 pt = 0 px).
Pager dos Reels troca de vídeo a cada gesto; clique pelo caminho real abre as abas.
Apresentação: 89 qps, p99 11,8 ms, 0 `MainThreadWatchdog RED`; CPU ~43% rolando o feed e
~34% parado (vídeo em reprodução). `sample` na aba Reels: thread principal 97% ociosa.

## Limites conhecidos
- O injetor de teste (`hostscroll`) entrega cada evento com ~0,5 s de atraso (o salto para a
  thread principal espera o run loop): serve para medir deslocamento, não fluidez sob um
  gesto denso. `MACAPK_DUMP_TREE_EVERY` do `ui.sh` também pesa: para medir tempo use
  `UI_DUMP_EVERY=100000`.
- O horário ainda é o da entrega, não `NSEvent.timestamp`; se a thread do AppKit atrasar,
  a distorção volta. Próximo passo se o arremesso parecer irregular.

## Atualização (mesmo dia): ajustes no menu Rolagem
Velocidade, inércia e rolagem automática viraram itens de menu (ADR 0010). O item 4 da
decisão segue sendo o padrão ("Do Instagram"); "Do macOS" mantém o dedo sintético por 50 ms
ao soltar e deixa a cauda de inércia continuar o mesmo arrasto — opção, não padrão, pelos
riscos descritos lá.

