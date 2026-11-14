# ADR 0029 — Assinatura local estável; câmera de volta; animador e getBitmap

## Contexto
Reassinar o runtime ad-hoc (embutir JRE/bibliotecas) muda o cdhash, e o macOS esquece a
permissão de câmera: a página de câmera ficava preta ("timed out after 30s waiting for the
macOS camera permission prompt"). O dono autorizou usar a câmera e mexer no que fosse preciso
(2026-11-12), exceto conta Apple Developer.

## Decisão
- **Identidade local estável:** certificado autoassinado "Instamac Local Signing" (só assinatura
  de código, 10 anos) no chaveiro de login, liberado para o `codesign`. `scripts/sign-identity.sh`
  devolve essa identidade quando existe (senão ad-hoc); `embed-jre.sh`, `bundle-host-libs.sh` e
  `build-instamac.sh` assinam com ela. Requisito do runtime:
  `identifier "dev.instamac.runtime" and certificate leaf = H"a1c1c4…"` — igual em toda
  reassinatura, então a permissão de câmera dada uma vez fica. Vale também para o clone de teste.
- **ValueAnimator:** `getAnimatedValue()` de animador float/int devolve 0 antes do primeiro
  quadro, como o AOSP (o `null` derrubava todo `ShimmerFrameLayout.dispatchDraw`).
- **TextureView.getBitmap(Bitmap):** copia o quadro atual (câmera ou vídeo) — era um stub em
  branco.
Patch 0036.

## Medição
Câmera: prévia ao vivo da câmera do Mac em Post e Story, no app instalado e no clone. Erros do
Shimmer: 0 (antes, dezenas por tela). Gates 5/5; app abre em 7 s.

## Pendente
- O obturador recebe o clique (`ig_camera_tap_capture_button`) mas a captura não é disparada:
  nenhum pedido à emulação de câmera nem `getBitmap`. Seguir o fluxo de captura do Optic.
- Células da grade da galeria às vezes cinza (não era o Shimmer nem o cache de desenho).

> Obturador resolvido no ADR 0030.
