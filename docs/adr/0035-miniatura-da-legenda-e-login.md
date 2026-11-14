# ADR 0035 — Miniatura da tela de legenda; login revisto

**Status:** aceito em 2026-11-13 (patch `0046`)

## Miniatura da tela de legenda
Medido: a célula de prévia (`share_photo_media_preview_layout`) tem um shimmer e um
`IgSimpleImageView` `wrap_content` (`photo_media_preview_image_view`). O bitmap chegava
(`BitmapDrawable(232x232)`), mas a view seguia medida 0×0 e só o shimmer aparecia. Não era o
cache de medida (ADR 0034, patch 0045): com `MACAPK_MEASURE_CACHE=0` continuava 0×0.

Causa: o nosso `ImageView.setImageBitmap` só chamava `invalidate()`. No AOSP ele passa por
`setImageDrawable` → `updateDrawable`, que chama `requestLayout()` quando a largura ou a altura
do drawable mudam. Agora faz o mesmo (só quando o tamanho intrínseco muda, para não forçar
layout a cada avatar).

Resultado: miniatura 232×232 com a foto; continua lá depois de escolher música e voltar. O
painel de música mostra a prévia da foto (o pendente "prévia some no painel de música" não
apareceu). Gate depois de injetar e retreinar o AOT (342 MB): 5/5, abre em 8–9 s.

## Login (pendente do ADR 0034), não reproduzido
Caminho sem deslogar ninguém: perfil → seletor de contas → "Adicionar conta" → "Entrar na conta
existente" → "Usar outro perfil". Com toque injetado e com clique real do AppKit (`hosttap`):
- o campo de usuário recebe foco e o texto (também vazio, depois de focar a senha);
- a senha aparece mascarada; o olho mostra e volta a mascarar.

O verbo `text` do injetor entra pelo mesmo `doDispatchKey` do keyDown real. Fica para o dono
confirmar com o teclado de verdade.

## Ferramenta
`hosttappx X Y` alcança botões dentro de folhas/diálogos (o `tap` cai na atividade de trás).
Corrige a nota do ADR 0034 de que só o mouse real funcionava.

## Notado, sem mudança
O arquivo de envio `pending_media_*.webp` é PNG (o `Bitmap.compress(WEBP)` grava PNG): 2,3 MB
para 1080×1080. Os posts publicam; só pesa mais no envio.
