# ADR 0012 — Varredura visual (celular e tablet) e o que ela corrigiu

**Status:** aceito em 2026-11-11 (patch `0018`)

## O que foi olhado
Com `scripts/ui.sh` (toques injetados + captura da janela), nos dois modos: feed, Reels,
Direct (lista), notificações, explorar, perfil, configurações. Mais a contagem de erros de
fidelidade no log (`NoSuchMethodError`, `macapk-stub`, `threw`…).

**De propósito não abri**: conversas do Direct e stories de outras pessoas (marcariam
"visto" na conta do dono) e câmera/criação (pediria permissão de câmera ao macOS). Essas
telas seguem não verificadas, assim como o desenho das bolhas de mensagem (9-patch).

## Defeitos encontrados e corrigidos
1. **`IgLinearLayout.generateLayoutParams` → `NoSuchMethodError`, 377×/boot.** O
   `LinearLayout` do framework não tinha a assinatura covariante do AOSP; o inflador caía
   num caminho genérico. Agora 0 ocorrências.
2. **Direct no tablet: painel "Suas mensagens" com 300 px, colado à esquerda de um painel de
   816 px.** O inflador gravava os `LayoutParams` no filho e chamava `addView(view)`; o
   `SlidingPaneLayout` reembrulha o painel de detalhe e herdava a largura 300. Agora o
   inflador faz `addView(view, params)` como o AOSP; painel centralizado.
3. **Tablet: linha horizontal atravessando o conteúdo, 48 px acima da base.** É a divisória
   (`tab_bar_shadow`) da barra de abas do celular, que fica na árvore no modo tablet, vazia.
   O atualizador do próprio app sai cedo quando o trilho está ativo e nada mais mexe nas
   duas views (rastreado com `MACAPK_TRACE_SETVIS`). **Não achei o que a remove num tablet
   de verdade**; a correção é um *quirk* declarado: quando o trilho (`ls_vertical_nav_bar_stub`)
   é inflado, barra e divisória ficam `GONE` — o estado que o app dá a elas ao esconder a
   barra. `MACAPK_QUIRK_RAIL_TABBAR=0` desliga.
4. `VMRuntime.setTargetHeapUtilization` não existia (1×/boot).

## Não era defeito
- A pilha redonda cortada no canto inferior direito do Direct (celular): o app reserva uma
  faixa de 66 px e deixa as fotos passarem da borda de propósito.
- O "tofu" antes de um @ da bio já estava resolvido (patch `0012`).

## Resultado
Log de boot sem nenhum `NoSuchMethodError`; nenhuma das telas olhadas com defeito visível
nos dois modos. Capturas em `build/shots/v*-*.png` (celular) e `t*-*.png` (tablet).
