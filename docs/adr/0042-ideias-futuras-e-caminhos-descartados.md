# ADR 0042 — Ideias futuras e caminhos descartados

**Status:** anotação (2026-11-19). Nada daqui foi implementado nem medido de novo; os números
vêm dos ADRs citados.

## Contexto
Revisão de projetos parecidos (ApkStart, Waydroid) e da própria arquitetura, perguntando se
dá para ficar mais rápido e mais nativo trocando peças grandes.

## Projetos olhados
- **ApkStart** (RoutineMiku, até 0.6.2): casca Electron só para Windows sobre o Android
  Emulator do Google (QEMU) ou o MuMu; instalador de 1,3 GB, boot do Android de 40–142 s.
  Nenhum código serve (Windows, emulador, licença da imagem do Play). Duas ideias servem:
  ambiente residente e recuperação automática (abaixo).
- **Waydroid**: Android num contêiner LXC que divide o kernel Linux (`binderfs`, namespaces).
  Não existe no macOS; só dentro de uma VM, o que cai no caso descartado abaixo.

## Ideias para implementar (em ordem de valor)
1. **Fechar a janela só esconde** (vindo do ApkStart). Botão vermelho/⌘W escondem; o Dock
   reabre na hora, já no feed; ⌘Q encerra de verdade. Com a janela fora de vista o Android
   já vai a `onStop` (ADR 0037), CPU baixa. Custo: ~850 MB residentes até o ⌘Q. Bônus: DM
   continua notificando com a janela fechada. É o único caminho para "abrir" em < 0,5 s:
   do zero, o Instagram precisa de 6–7 s (JVM + classes do cache, init do app, feed pela rede).
2. **Recuperação automática no launcher** (vindo do ApkStart): se o boot não chegar ao
   primeiro quadro, reabrir; se travar de novo, afastar `data/data/<pkg>` como faz
   `scripts/reset-app-data.sh` (login sobrevive em `data/system`). Baixo valor hoje: boot 10/10.
3. **Heap devolvendo memória ociosa** (`MACAPK_JVM_OPTS`, ex. `-XX:MaxHeapFreeRatio`):
   dezenas de MB de ~850 MB; barato; exige o gate de boot 10/10.
4. **Terminar o treino AOT** (ponto `LongformDraftRepository.A02`, ADR 0032): o treino já
   cobre janela e feed, então a abertura muda pouco; ganho na 1ª visita a perfil/Reels.
5. **JDKs futuras** com código compilado guardado entre aberturas (sucessores do AOT cache do
   ADR 0019): abertura mais rápida sem mudar a arquitetura; reavaliar a cada JDK nova.

## Caminhos descartados (e por quê)
- **Android numa VM** (Virtualization.framework ou o emulador com HVF + gfxstream→Metal):
  compatibilidade quase total, mas quebra a regra "sem emulador, sem VM", 2–4 GB de RAM
  parado, boot de um Android inteiro, sem 3D no Virtualization.framework para Linux, refazer
  toda a integração com o Mac, e mais atrito com integridade/atestado (§3 item 7).
- **Trocar o `Canvas` de Java2D por Skia/Metal**: Skiko já vem no app (só AGSL/RenderEffect),
  mas o custo que motivava isso (26–41% da thread principal, ADR 0016) já foi retirado pelos
  ADRs 0018, 0023 e 0038 (quadro completo 5,8 ms, só desenho 2,7 ms). Sobra pouco ganho para
  reescrever 7,2 mil linhas com alto risco visual. Formas pequenas via Skia também não: o
  adendo do ADR 0023 mostrou que até a chave de cache custa mais que desenhar.
- **Sair do Java**: o Instagram é bytecode e precisa de uma VM. ART só existe para
  Linux/Android (portar = meses, perder JDK 25 + AOT); GraalVM native-image não aceita o
  carregamento dinâmico e a reflexão do app. O JIT da JDK 25 no M4 é tão bom quanto o do ART.
- **Rust**: ganha segurança de memória, não velocidade; reescrever runtime/tradutor/shim em
  C++ que já funcionam arrisca regressões resolvidas (ADRs 0001, 0011). Só para peça nova e
  isolada.

## Teto atual
Rolagem > 60 qps, abertura 6–7 s, parado 6,5–10% de CPU, ~850 MB. Os ajustes que sobram são
de dezenas de MB ou frações de segundo; o tempo rende mais em funcionalidade (lista "Aberto").
