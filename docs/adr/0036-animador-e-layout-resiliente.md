# ADR 0036 — Painel de áudio: animador como no AOSP; layout resiliente

**Status:** aceito em 2026-11-13 (patches `0047`, `0048`)

## Painel de áudio do editor (abrir/fechar)
Medido (`MACAPK_TRACE_SETVIS=0x7f0b25fd`): ao abrir o painel de áudio, a barra do editor
(`MediaEditActionBar`, com a seta de voltar) some com um fade. Ao fechar, o Instagram chama
`setAlpha(0)`, `VISIBLE` e `animate().setDuration(..).withEndAction(..).alpha(1f)` — **sem
`start()`**. No AOSP o `ViewPropertyAnimator` começa sozinho no próximo quadro; o nosso só
começava com `start()`, e a barra ficava invisível (sem seta de voltar) depois de fechar.

O `ViewPropertyAnimator` agora segue o AOSP:
- uma instância por view (`View.animate()` em cache): `view.animate().cancel()` cancela o que
  foi iniciado antes (antes, cada `animate()` era um objeto novo e o `cancel()` não fazia nada);
- valor inicial lido na chamada da propriedade; início agendado no próximo quadro;
- propriedade animada por uma animação nova é tirada da anterior (cancelada se ficar vazia);
- `withStartAction`/`withEndAction` valem para uma animação; cancelada, a ação final não roda e
  os valores ficam onde estão.

`MACAPK_TRACE_VPA=1` registra início e cancelamento de cada animação.

Medido: abrir → fechar (Voltar) → a barra volta com fade; a prévia de música para ao fechar
(pause/flush/release no rastreio de áudio); escolher música → ✓ → editor com a música;
abrir → fechar → abrir → escolher → confirmar funciona. Feed e Reels sem mudança visível.

## Layout resiliente
O perfil abria sem barra de título, botões e grade: um `RecyclerView` de sugestões lançou
`ClassCastException` no `onMeasure` (item `X.07EH`, "sugestão com story", com anel visível; o
código do app faz cast para `User`). O runtime engolia a exceção da medida, mas o
`RecyclerView` ficava no meio de um passo e o `onLayout` seguinte lançava
`Layout state should be one of 100 but it is 10`, abortando o layout da tela inteira.
`View.layout` agora segura a exceção do `onLayout` (como a medida já fazia) e registra a pilha
uma vez por classe. Resultado: perfil inteiro; só aquela lista fica vazia. O item vem do
servidor e não aparece em toda abertura.

## Pendente
- Painel de áudio às vezes abre com o conteúdo colapsado (2–15 px; 2 em ~30 aberturas): a
  última medida real do `IgPrioritizedVerticalLayout` foi com altura pequena e não é refeita.
  Fechar e abrir de novo resolve. Causa não encontrada.
- O toque em "Post" da folha "Criar" às vezes fecha a folha sem abrir a galeria (o toque cai
  enquanto a folha ainda anima); nos roteiros, esperar a folha assentar.
