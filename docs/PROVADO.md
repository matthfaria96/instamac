# O que já está provado (não refazer)

Cada linha foi medida nesta máquina; a evidência está em `docs/PRODUTO.md` (seção indicada) ou em `build/boot/`.

| área | evidência |
|---|---|
| Instagram instala, abre e chega ao feed logado, layout tablet | capturas e `frame-score RICH` |
| Portrait e landscape | janela redimensionável, re-layout ao vivo; rail correto em 1280×800 |
| Ícone/nome/menu | menu bar e título "Instamac", Dock com o "I" |
| Keystore | `Cipher.doFinal(null)` normalizado; sem `System.exit(10)` com dados existentes |
| Mídia (decode) | AAC `frames=90112 rms=2866 -> PASS`; H.264 18 frames → PNG 320×240; vp8/vp9 por libvpx estático |
| `/dev/zero` + `munmap` cru | sem `mmap FAILED`; `syscall(215)` implementado |
| x18 TLS em thread da JVM | self-heal no handler (instala TLS e re-executa) — patch `0005` |
| **Retrato com layout de telefone** | barra de abas inferior, ícones no tamanho certo, botões e abas do perfil (patches `0008`, `0009`; PRODUTO.md F1s); 0 construtores de view falhando |
| **Vídeo e som** | feed e aba Reels tocam; xHE-AAC decodifica (`frames=237568 rms=5901 -> PASS`); no app `track_bytes=962560/5s`, `nonsilent_renders=469/469` (patches `0010`, `0011`; F1t) |
| **Reel renderiza** | `X/09IF.A0p` coube: 68.700 → 61.730 bytes com slots por frequência; `macapk-stub` = 0 nas telas testadas |
| **Sessão logada estável** | SQLite do app em vez do do macOS (PRODUTO.md F1r, patch `0007`): sessões de 150 s 3/3 vivas (antes 2/2 morriam em 11–29 s) |
| **Boot com sessão logada (P0)** | causa: passe de canário reescrevia `libstartup+0x445258` para `mov x20,#0` (PRODUTO.md F1q, patch `0006`); 6/6 árvores que travavam abrem no feed; **10/10 aberturas seguidas** logado (5–9 s): `build/boot/p0-final/` e, com o binário final (+ patch `0007`), `build/boot/final-10/` |
| Log | de 180.653 para 4.060 linhas/sessão com `MACAPK_QUIET_CLASSLOAD=1` + `MACAPK_LOG_LEVEL=4` |
| Bundling | app 1,4 GB, `codesign --verify --strict` ok no build; preseed por build |
