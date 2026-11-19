# CLAUDE.md — Instamac

Documento de trabalho: o que o produto é, o que já está provado, o que falta e como
continuar sem repetir medições. Tudo aqui foi medido nesta máquina (macOS 27.2, Apple
Silicon, dois displays: 2560×1440 @1x e 1080×1920).

---

## 1. O produto, em uma frase

**Instamac é o Instagram rodando nativamente no macOS, com o nome Instamac em toda
superfície.** O usuário abre o app e o Instagram já está instalado dentro dele — sem
seletor de APK, sem descompactar, sem "primeiro uso", sem emulador, sem VM, sem navegador.

### Regras que não se negociam

1. **Nome**: menu bar, título da janela, Dock, Cmd-Tab, diálogos e identidade Android
   (`Build.BRAND`, `EGL_VENDOR`, telefonia, sensor, IME, áudio) dizem **Instamac**. O nome
   do projeto upstream aparece só onde a AGPL exige atribuição (NOTICE/README/licença).
2. **Ícone**: o que o dono escolheu (2026-11-11), fixo, em `assets/Instamac.icns` +
   `assets/instamac-icon-1024.png`. Trocar **só** com `scripts/set-icon.sh <arquivo.icns>`:
   ele confere a grade da Apple (corpo 824/1024, `tools/icongrid.swift`), regenera todas as
   representações a partir do mestre e atualiza bundle e fallback do runtime. O launcher
   passa `MACAPK_APP_ICON` e `MACAPK_ICON_ROUND=0` (o PNG já está na grade; sem isso o
   runtime o encolhe de novo). Nunca usar o ícone extraído do APK. **O dono aprovou o ícone
   atual: não mexer.**
3. **Nada de desempacotar para o usuário**: a instalação/conversão/tradução acontece no
   **build** (`scripts/preseed.sh`). O bundle sai pronto.
4. **Instância única**: o launcher faz `execv` no runtime (sem processo pai). Rodar como
   filho deixava o boot travado — medido.
5. **Janela**: dois modos, trocados pelo menu Visualizar — **Celular** (abre 412×915,
   barra de abas embaixo, largura sempre < 600 dp) e **Tablet** (abre 1280×800, trilho
   lateral). Redimensionáveis dentro do próprio layout; sem tela cheia (ADR 0010).

---

## 2. Como o Instamac é montado

```
Instamac.app/Contents/
  MacOS/Instamac                     launcher Swift: resolve APK, aplica env, execv
  Resources/AppIcon.icns             ícone do bundle
  Resources/InstamacIcon.png         ícone do Dock (MACAPK_APP_ICON)
  Resources/runtime/                 runtime embutido (binários + jars + jre + translator)
  app/embedded/                      vazio depois do build (o .xapk só existe até o preseed)
  android/                           o Instagram JÁ INSTALADO
    data/app/…/base.apk              como num device
    .macapk/code/<pkg>_<ver>/        classes.jar convertido + lib_native traduzidas
    data/data/<pkg>_<ver>/           dados do app (sessão, prefs); `cache` é link para
                                     ~/Library/Caches/dev.instamac.app/<pkg>/cache
    data/system/                     AccountManager (login sobrevive a reset de dados do app)
```

Pipeline do build: `payload/*.xapk` → runtime instala/convert/traduz dentro do bundle
(`preseed.sh`, duas passadas: fria + morna) → links relativos → `compact-app.sh` (tira o .xapk duplicado, compressão APFS) →
assinatura ad-hoc. Tamanho medido do app instalado: 646 MB em disco (era 1,6 GB; ADR 0008).

### Código nosso (o que se edita)

| caminho | papel |
|---|---|
| `launcher/InstamacMain.swift` | launcher: env, log, locks, `execv` |
| `src/dex/*.java` | overlay do tradutor dex→JVM (SwitchTableEmitter/Splitter, Translator, DexConverter) |
| `src/framework/**` | overlay do framework Android (hoje: `AndroidKeyStoreCipherSpi`) |
| `vendor/macapk/runtime/java/**` | framework Android + loader do runtime (patch local): recursos/densidade, inflador, `ImageView`, `TypedArray`, `MediaCodec`. `build-framework.sh` compila todo `.java` que difere do commit fixado |
| `vendor/macapk/runtime/src/*.mm,*.cpp` | runtime nativo (patch local): janela, título, menu, resolução |
| `vendor/macapk/runtime/translator/src/*.cpp` | shim bionic (x18, mmap de `/dev/zero`, `munmap` cru); loader em `arm64_native.cpp` (passe de canário, resolução de imports guest × host) |
| `vendor/macapk/runtime/macapk-runtime-info.plist` | **nome do app no menu bar** (plist embutido no binário) |
| `contrib/upstream/patches/` | todo patch publicado (AGPL) |

### Scripts

| comando | o que faz |
|---|---|
| `scripts/build-dexconv.sh` | compila `com.macapk.dex` (vendor + overlay) → `build/classes` |
| `scripts/build-framework.sh` | compila `src/framework` + os `.java` do vendor com patch local → `build/framework-classes` |
| `scripts/inject-classes.sh <classes> <runtime/lib>` | injeta classes nos **dois** jars do runtime (cada um recebe as que já contém) |
| `scripts/runtime-patch.sh apply\|export` | aplica ao submódulo limpo, ou regrava, o patch único com as mudanças do runtime (`contrib/upstream/runtime.patch`) |
| `scripts/set-icon.sh <icns>` | troca o ícone em todo lugar, na grade da Apple |
| `scripts/build-notifier.sh <app>` | compila o auxiliar de notificações (`tools/notifier`) em `Contents/Helpers`; reassinar o bundle depois |
| `scripts/ui.sh start\|tap\|swipe\|flick\|raw\|key\|shot\|tree\|views\|stop` | dirige o app instalado para verificação visual: toques injetados, captura da janela, árvore de views e de acessibilidade |
| `scripts/build-instamac.sh` | monta `build/Instamac.app` (embute payload, preseed, injeta jars, assina) |
| `scripts/release-clean.sh <app>` | tira do app montado o estado de uma instalação (ids, prefs, caminhos) e grava o modo Celular; o `make-dmg.sh` roda na cópia do DMG |
| `scripts/make-dmg.sh` | `build/Instamac-<versão>.dmg` a partir de `build/Instamac.app` (limpo) |
| `scripts/compact-app.sh <app>` | encolhe o bundle (app fechado): remove o container duplicado e comprime o que não muda em uso |
| `scripts/preseed.sh <app>` | roda o runtime 2× contra `Contents/android` (fria + morna; gate = chegar ao frame) |
| `scripts/patch-app.sh` | troca runtime/launcher/jars no app instalado **preservando dados** |
| `scripts/deploy.sh` | rebuild completo + instala (zera dados do app; login em `data/system` sobrevive) |
| `scripts/reset-app-data.sh` | recupera boot travado: afasta `data/data/<pkg>` para /tmp |
| `scripts/boot-test.sh <árvore> \| -` | ABRIU (em Ns, em qual atividade)/TRAVOU; `BOOT_ENV=launcher` (padrão, abre pelo bundle) `\|bare`; `BOOT_RUNTIME_ENV="K=V"` para A/B sem recompilar; ao travar grava `sample`+`jcmd` em `build/boot/hang-*` |
| `scripts/boot-loop.sh N [árvore\|-]` | N aberturas seguidas (a 1ª com a árvore, as outras com o estado que ficou); resumo `k/N` |
| `scripts/convert-apk.sh <apk>` | roda só o tradutor, com `DEX2JVM_SPLIT_DEBUG` |
| `tools/winid.swift` | lista janelas (id/título/bounds) para capturar a janela do app |
| `tools/viewtree.py <log>` | último dump de views com posições absolutas (`--off` = fora da janela, `--all`, `--grep`) |
| `tools/arsc.py <apk> name\|values\|find\|style\|styles-with` | consulta `resources.arsc` (não há aapt2 aqui): valor por configuração, estilos |
| `tools/axml.py <apk> dump\|with-id\|find-attr` | lê layouts, inclusive os do blob empacotado do Instagram |
| `tools/findconst.py <jar> 0x7f…\|s:texto` | classes do app que usam uma constante (id de recurso, string) |
| `tools/mkpatch.py OUT DESC arquivo[:trechos]` | monta um patch publicado a partir do diff do submódulo, escolhendo trechos por número ou `~regex` |
| `tools/icongrid.swift` | mede/normaliza um ícone contra a grade da Apple |

### Receitas

```bash
# build completo (runtime já vem de runtime/ ou de um app instalado)
scripts/build-dexconv.sh && scripts/build-framework.sh
scripts/build-instamac.sh

# aplicar só código novo no app instalado, sem perder login
scripts/build-framework.sh && INSTAMAC_SKIP_PRESEED=1 scripts/build-instamac.sh
scripts/patch-app.sh

# runtime nativo (C++/ObjC), ligado à JDK 25 (ADR 0019) — preserva entitlements de x18/JIT
cd vendor/macapk/runtime && JAVA_HOME=/opt/homebrew/opt/openjdk@25/libexec/openjdk.jdk/Contents/Home \
  cmake -DCMAKE_BUILD_TYPE=Release -B build-jdk25 . && \
  cmake --build build-jdk25 --target macapk-runtime -- -j8
# instalar: scripts/embed-jre.sh <app> build-jdk25/macapk-runtime build/jre25 build/lib-jdk25
# (NÃO copiar o binário cru: ele aponta para a JDK do Homebrew). Depois de trocar
# runtime ou jars: scripts/train-aot.sh (o cache antigo vira MISS; o app abre sem ele)

# shim do tradutor (x18/mmap/syscalls)
cd vendor/macapk/runtime/translator && JAVA_HOME=/opt/homebrew/opt/openjdk@25/libexec/openjdk.jdk/Contents/Home \
  cmake --build build --target macapk-bionic-shim -- -j8

# patch Java do runtime (vendor/macapk/runtime/java/**): compilar e aplicar no app instalado
scripts/build-framework.sh
scripts/inject-classes.sh build/framework-classes \
  /Applications/Instamac.app/Contents/Resources/runtime/lib
codesign --force --sign - /Applications/Instamac.app

# tradutor (src/dex): reconverter o APK (~40-90 s) e trocar o classes.jar do app instalado
scripts/build-dexconv.sh
INSTAMAC_RUNTIME=/Applications/Instamac.app/Contents/Resources/runtime \
  scripts/convert-apk.sh "$(ls /Applications/Instamac.app/Contents/android/data/app/*/*/base.apk)" build/conv.jar
cp build/conv.jar /Applications/Instamac.app/Contents/android/.macapk/code/com.instagram.android_*/classes.jar

# verificação visual (toques injetados, sem permissão de acessibilidade)
scripts/ui.sh start MACAPK_MEDIA_PROBE=1      # K=V extras vão para o runtime_env
scripts/ui.sh tap 450 776 && scripts/ui.sh shot perfil && scripts/ui.sh views --off
scripts/ui.sh stop                              # remove o runtime_env de teste
```


**Pegadinhas** — a lista completa e medida está em `docs/PEGADINHAS.md`; leia a parte da
área em que vai mexer. As que valem sempre:

- `codesign --force --sign - <binário aninhado>` **remove as entitlements** (x18/JIT; boot
  morre com `[x18] FATAL`). Assine só o bundle. Para assinar código, use a identidade de
  `scripts/sign-identity.sh` ("Instamac Local Signing" no chaveiro): ad-hoc faz o macOS esquecer
  a permissão de câmera a cada reassinatura (ADR 0029).
- Nada que faça o app ler `~/Documents`, `~/Desktop` ou `~/Downloads` (diálogo do macOS que
  bloqueia a thread, e volta a cada reassinatura). Estado de teste em `$TMPDIR`; capturar só
  a **janela**. Reassinar o mínimo possível.
- `data/data/.../lib-compressed` é 0555: `chmod -R u+w` antes de mexer.
- Copiar o app só com `ditto` (Finder/`cp` desfazem a compressão do APFS).
- O injetor do `ui.sh` reivindica o arquivo em lotes e entrega cada evento de trackpad com
  ~0,5 s de atraso: escreva um gesto numa escrita só (`flick`, ou `raw` com várias linhas) e
  espere o `[wheel] harness trackpad phase=2` no log antes de capturar. `hosttap` exige
  `MACAPK_EXTERNAL_URLS=0`. Para medir tempo, `UI_DUMP_EVERY=100000`.
- Editar só `macapk-runtime-info.plist` não re-linka: `rm -f build/macapk-runtime` antes.
- Disco do Mac com pouco espaço livre (1–4 GB) e `classes.jar` de ~450 MB: conferir `df` antes
  de copiar jar/bundle, `cmp` depois (uma cópia que falha por falta de espaço pode truncar), e
  apagar `build/*.jar` e `build/boot` velhos.

---

## 3. Estado

**Provado (não refazer; tabela com evidências em `docs/PROVADO.md`):** instala, abre e chega
ao feed logado; boot 10/10 com sessão logada; retrato (telefone) e paisagem (tablet, trilho);
vídeo e som nos Reels; keystore; sessão estável; nome/ícone/menu.

**Decisões e medições: um ADR por assunto em `docs/adr/`** (histórico F1a–F1t em
`docs/PRODUTO.md`).

| ADR | assunto | estado |
|---|---|---|
| 0001 | boot determinístico (passe de canário) | resolvido |
| 0002 | resolução fixa | substituído pelo 0010 |
| 0003 | fluidez | apresentação estável (89 qps, p99 11,8 ms, 0 watchdog RED); CPU ~34% parado com vídeo; falta medir sob gesto real denso |
| 0004 | vídeo e som | funcionando nos Reels; stories, DM e H.264/HEVC não exercitados |
| 0005 | métodos gigantes | `X/0bRx.getValues` segue estubado, nunca chamado |
| 0006 | girar relança a atividade | ligado por padrão; os dois sentidos corretos |
| 0007 | scroll do trackpad desde o primeiro delta | ligado; sensação a validar pelo dono |
| 0008 | bundle compacto | 1,6 GB → 646 MB em disco; compressão do APFS no teto |
| 0009 | processo: ADRs sim, AgEnFK não | — |
| 0010 | dois modos de janela (celular 412×915 / tablet 1280×800) e barra de menus refeita (Visualizar, Rolagem, Navegar, Janela) | ligado; arrasto da borda e "Inércia do macOS" não verificados |
| 0011 | "SIGILL em código JIT": a guarda do tratador contava PC, não quadro | corrigido; 20/20 aberturas sem morte (antes 2 em 10 morriam aos 7–8 s) |
| 0012 | varredura visual nos dois modos + correções de fidelidade (LinearLayout covariante, `addView` do inflador, linha da barra de abas no tablet) | 7 telas × 2 modos sem defeito visível; conversas, stories e câmera não abertos |
| 0013 | arquivos do Mac para o Instagram (menu Arquivo, arrastar para a janela) e menu Editar | entrega medida (Feed, Mensagem, vários, HEIC); Story/Reel caem na página de câmera vazia; painel e arrasto reais a validar pelo dono |
| 0014 | editor de foto: janela EGL sobre `ImageReader` + `Transaction.setBuffer` no `SurfaceView` | prévia do editor funciona, imagem de envio conferida; miniatura de "Novo post" no carregando; filtros/publicar não exercitados |
| 0015 | criar pelo Mac: "+" do feed abre o painel em Imagens; colar na legenda; Imagens/Filmes mapeados; módulos baixados somente-leitura (shim) | "+" e colar medidos; **página de câmera do Instagram em branco** (Story/Reel) sem causa; galeria mapeada não vista numa grade |
| 0016 | leveza: medição de base (CPU/memória por componente) e VP9 por hardware (VideoToolbox) | VP9 em hardware medido (thread do player 8,1% → 1,1%); total não muda: a thread principal redesenha a árvore em Java2D a cada quadro (26–41%) |
| 0017 | página de câmera do Instagram com a câmera do Mac (margens, serviço "window", JPEG, fps UVC, textura externa) | prévia ao vivo em Story/Post; Story/Reel voltaram ao menu Arquivo; disparador e grade da galeria abertos |
| 0018 | vídeo de TextureView numa camada nativa (IOSurface do decodificador, sem cópia nem repintura) | Reels: CPU 38–135% → 15–18%, RSS 1064 → 849 MB; boot 10/10 |
| 0019 | JDK 25 embutida (JRE jlink de 60 MB com correções gravadas) + cache AOT de classes | abre em 7 s (antes 12–16 s); sem JVM do Homebrew; cache 199 MB em ~/Library/Caches |
| 0020 | rodinha do mouse nos Reels vira deslize de arrasto (pagina); prévia da primeira imagem enviada; carrossel com 2 anexos | 4 cliques = 4 Reels, nada para no meio; 1ª prévia correta; as duas páginas com prévia |
| 0021 | som dos vídeos ao abrir (Visualizar): Ativado/Desativado/Padrão, enviado como tecla de volume | desligado medido no Reels (0.0); ligado no feed; menu não testado à mão |
| 0022 | links do WhatsApp pelo Mac: `com.whatsapp` "companheiro" (VIEW/SEND abrem wa.me no Mac) | link do perfil → `wa.me/<número>` puro (antes: Play Store) |
| 0023 | desenho mais leve: pixels guardados (fotos escaladas, avatares), furo de vídeo rápido, texto já formatado | quadro só de desenho 5,2→2,7 ms; completo 7,7→5,8 ms; 354→1646 quadros na mesma rolagem |
| 0024 | app sem Homebrew (`bundle-host-libs.sh`); distribuição pendente | capstone/libpng de dentro do app; notarizar exige Developer ID do dono + dados fora do bundle |
| 0025 | chips do perfil em retângulo arredondado (`MACAPK_RES_OVERRIDES`) | 8dp, como no celular |
| 0026 | tradutor: valores estáticos sem `ConstantValue` (ex.: `static final Class TAG`) gravados no `<clinit>` | cliente de tempo real do Direct sem exceção; canal CONNECTED_AND_ACKED |
| 0027 | notificações do macOS: desenho | substituído pelo 0037 |
| 0028 | galeria vazia: varredura de mídia travava em `~/Movies/TV` (pasta protegida) | galeria lista 1187 itens; células às vezes cinza (pendente) |
| 0029 | assinatura local estável ("Instamac Local Signing") mantém permissões; câmera de volta; ValueAnimator e TextureView.getBitmap fiéis | prévia da câmera ao vivo |
| 0030 | obturador: zoom máximo 1,0 + faixa de razão (o Optic morria num `get(0)`) e estado 3A nos resultados | foto 1920×1080 abre o editor de Story |
| 0031 | grade da galeria: ouvintes de layout disparam no `LAYOUT_REQUIRED` (spec mudou), como no AOSP | 4/4 aberturas com a grade completa (antes ~3 de 4 cinza) |
| 0032 | treino AOT: construtores do R8 reapontados (padding no reaproveitamento, pares fora de ordem, contagem de alocações) | cache 199 → 325 MB, abre em 6 s; sobra 1 ponto (`LongformDraftRepository.A02`) |
| 0033 | tela de carregamento nativa (ícone, nome, indicador) até o primeiro quadro com conteúdo | sai aos 8,7 s com o feed (disco quente) |
| 0034 | postar: BEGIN cru como transação aninhada; fundo de diálogo do tema; folhas inferiores deslizam | posts com legenda e música publicados (conta de teste) |
| 0035 | miniatura da legenda: `setImageBitmap` pede layout quando o tamanho muda (AOSP); login revisto | miniatura com a foto; login (foco, senha mascarada) não reproduzido; `hosttappx` alcança folhas |
| 0037 | janela fora de vista → `onStop` (CPU 21% → 9–14%); notificações do macOS por app auxiliar (`NSUserNotificationCenter`: sem Developer ID o sistema nega o novo); barra de título com 3 botões centralizados | autoteste ponta a ponta; DM real com o app minimizado não testada |
| 0039 | S1 de dano (+ adendo: recorte suavizado e mipmaps contra serrilhado, patch 0054): pula quadros cuja mudança é invisível (recorte parcial desligado: não ganha e erra 2%); inflação sem reler fontes/cores/reflexão; cache de medida desligado (folha de áudio vazia) | folha 12/12; 0 pulos errados validados; picos de 1ª visita ~400 ms (layout do app) |
| 0038 | tela parada: `ProgressBar` oculto parava de repintar; batimento espaçado (launcher); girar não manda a janela para trás | perfil parado 20% → 6,5–10% CPU; feed 24% (falta repintura parcial) |
| 0036 | `ViewPropertyAnimator` como no AOSP (um por view, começa sozinho, `cancel()` real); layout resiliente a `onLayout` que lança | seta do editor volta ao fechar o painel de áudio; perfil inteiro com lista de sugestões quebrada; painel de áudio colapsado ~1 em 15 (aberto) |
| 0040 | Tamanho da Interface (Visualizar: Automático/100/125/150%): densidade e janelas escaladas; automático = maior que cabe | 125% nesta tela (515×1144, 200 dpi), toque e layout de celular conferidos |
| 0041 | distribuição 1.0.0: `release-clean.sh` (sem identidade/caminhos, abre em Celular) no `make-dmg.sh`; repo público com histórico novo | DMG 608 MB, cópia limpa abre no "Participe do Instagram" |
| 0042 | ideias futuras (fechar só esconde, recuperação automática, heap, treino AOT) e caminhos descartados (VM, Skia no `Canvas`, sair do Java, Rust) | anotação; nada implementado |

**Aberto, em ordem:**
1. Dono testar à mão o scroll (feed, Reels, stories) e o giro (ADR 0007), e os modos de janela
   e o menu Rolagem (ADR 0010).
2. Criação: indicador de carregamento no editor de Story; filtros;
   retângulo cinza atrás do diálogo "Deseja descartar as edições?".
3. Varredura visual: Direct, stories, notificações, configurações. Conhecidos: "tofu" antes de
   um @ na bio; `IgLinearLayout.generateLayoutParams` → `NoSuchMethodError` (~260/boot, cai no
   caminho genérico); 9-patches nas bolhas de mensagem.
4. Treino AOT: o ponto que sobra (ADR 0032) encerra o treino depois do feed.
5. Leveza: metadados de classes (232 MB) e código traduzido (238 MB em disco), ADR 0018.
6. Notificações: validar com mensagem real (ADR 0037); notarização e o caminho novo de
   notificações exigem Developer ID do dono.
7. Limite declarado: **não forjar atestado de hardware**; se aparecer bloqueio de
   integrity/attestation, documentar e propor caminho.

---

## 4. Como verificar qualquer mudança

```bash
# 1. boot (o gate mais importante)
scripts/boot-test.sh - | tail -1            # ABRIU/TRAVOU, ~80 s
scripts/boot-loop.sh 10 /tmp/instamac-data-20261111-021127/com.instagram.android_455_0_0_51_72
BOOT_RUNTIME_ENV="MACAPK_X=1" scripts/boot-test.sh -   # A/B de um knob sem recompilar

# 2. app real
open -a /Applications/Instamac.app
tail -f ~/Library/Logs/macapk/app_com.instagram.android_*.log | grep -E "first frame|window focus|FATAL|macapk-stub"

# 3. captura da janela (sem permissão de acessibilidade)
swiftc -O -o build/winid tools/winid.swift
W=$(build/winid | awk -F'\t' '$3=="Instamac" {print $1; exit}')
screencapture -x -o -l"$W" /tmp/janela.png

# 4. mídia (sem app)
MACAPK_MEDIA_SELFTEST=1 MACAPK_MEDIA_SELFTEST_FILE=/tmp/mdtest.m4a \
  /Applications/Instamac.app/Contents/Resources/runtime/Resources/macapk-runtime \
  --apk "$(ls /Applications/Instamac.app/Contents/app/embedded/*.xapk|head -1)" \
  --android-root /Applications/Instamac.app/Contents/android
```

Marcadores de sucesso nos logs: `delivering window focus` (UI subiu), `first frame
presented` (placeholder), `[present] window visible again`, `frame-score … verdict=RICH`.

---

## 5. Convenções

- Código: `snake_case` em funções/variáveis, `PascalCase` em tipos, comentário só no
  não-óbvio, nada de stub/TODO no que é entregue.
- Todo patch no runtime/tradutor vira arquivo em `contrib/upstream/patches/` (AGPL), e
  `scripts/runtime-patch.sh export` regrava o patch único que o build aplica.
- Decisão ou medição nova = um ADR curto em `docs/adr/` (contexto, decisão, medição,
  consequências) + uma linha na tabela do §3. Não engordar este arquivo: ele é carregado
  inteiro a cada sessão. `ARQUITETURA.md` é o mapa, `USO.md` o uso, `F1B.md` os métodos gigantes.
- Não escrever o nome do projeto upstream em superfície do app; só na atribuição legal.
- Antes de "consertar" algo grande, medir com `boot-test.sh`, `convert-apk.sh` ou os
  self-tests — três dos erros desta sessão vieram de hipótese sem medição (try/catch,
  densidade, e "o jar quebrou o render").

---

## 6. Estado do repositório

- Branch única, commits do dono; `vendor/macapk` é submódulo fixado em `57c9912`.
- `runtime/` e `payload/` não são versionados (runtime extraído, APK do usuário).
- `build/` guarda o app montado, logs de build e capturas de verificação.

---

## 7. Comece a próxima sessão por aqui

```bash
git status --short                      # overlay e runtime limpos?
scripts/boot-test.sh - | tail -1        # o app abre HOJE? (ABRIU em Ns em <atividade>)
scripts/boot-loop.sh 10 -               # gate depois de mexer em runtime/shim/launcher
```

**Onde parei** (atualize esta seção ao encerrar; é o que poupa redescobrir o estado):
2026-11-19: projeto encerrado por ora. Ideias e caminhos descartados anotados no ADR 0042
(retomar por ele). Artefatos de build apagados (refazer com as receitas do §2); `payload/`,
`runtime/` e o app em /Applications ficaram.

2026-11-14 (noite): patches 0046–0053 (ADRs 0035–0039). Varredura feita: Stories (destaque) e
Direct (caixa de entrada) corretos; módulos baixados de volta a 0444 (meu build-notifier tinha
tirado). Imagens: recorte suavizado + mipmaps (0054); Tamanho da Interface automático (0055, ADR 0040: 125% nesta tela, coordenadas do `ui.sh tap` ×1,25). Pendentes: captura de tela PNG do Mac preta no editor
(JPEG ok); bolhas do Direct não testadas (exige enviar mensagem); toque em "Post" da folha Criar
intermitente nos testes; picos de 1ª visita de tela (~400 ms, layout do app). SEMPRE
`scripts/ui.sh stop` ao fim de um teste (ou apagar o runtime_env se o dono estiver usando o app).
Versão 1.0.0 publicada (DMG no release do GitHub, página no witchmymac). Testes sempre mudos (`MACAPK_AUDIO_TEST_MUTE=1` no ui.sh/boot-test.sh).
