# Pegadinhas medidas

Tudo aqui custou uma medição. Leia a parte da área em que vai mexer antes de mexer.

- Editar só `macapk-runtime-info.plist` **não** re-linka: `rm -f build/macapk-runtime` antes.
- `codesign --force --sign - <binário aninhado>` **remove as entitlements** (x18/JIT falha no
  boot com `[x18] FATAL`). Assine só o bundle; o binário mantém a assinatura do build.
- `data/data/.../lib-compressed` fica em modo 0555: `chmod -R u+w` antes de mexer/copiar.
- Janela em tela secundária travava o boot (`Configuration` de uma tela, superfície de
  outra). A tela é escolhida uma vez: menu-bar screen (`macapk_launch_screen`).
- `MACAPK_DISPLAY_DENSITY=320` faz o boot travar com frequência nesta máquina; ficar no
  padrão (160 em monitor 1x) e ajustar o **tamanho da janela** em vez da densidade.
  (Medido antes da correção F1q; a atribuição pode ter sido correlação — remedir com
  `boot-loop.sh` antes de reusar.)
- O `.text` que roda **não é o do arquivo**: o loader reescreve código do guest (canário,
  x18). Para ver o que executou, use `MACAPK_FAULT_DUMP=1` (despeja o código vivo antes do
  `pc`) e `MACAPK_CANARY_TRACE=1` (lista cada site reescrito; ignora o cache de plano).
- Sem debugger: SIP ligado e o runtime não tem `get-task-allow` → `lldb` não anexa. O que
  funciona: `sample`, `jcmd` (openjdk@21), `MACAPK_FAULT_DUMP`, e
  `MACAPK_NULL_RECOVERY_NEARNULL=0` (a primeira falta nula vira crash com `hs_err`).
- Import do guest resolvido para uma dylib do macOS (`dlsym(RTLD_DEFAULT)`) é suspeito
  quando o app traz a própria biblioteca: ABI variádico diferente e estado duplicado. O
  loader prefere o guest para cripto e SQLite; o log diz `-> guest … (preferred over …)`.
  Crash pós-boot: `BOOT_HOLD=150 scripts/boot-test.sh -` (exit 3 = morreu aberto).
- `build-instamac.sh` sobrepõe ao runtime extraído os nativos compilados em `vendor/`
  (shim e `macapk-runtime`). Depois de recompilar o shim, copie também para
  `runtime/bin/` e para o app instalado (ou rode o build + `patch-app.sh`).
- Dependências fora do bundle (P5): o runtime carrega `libjvm` de
  `/opt/homebrew/Cellar/openjdk@21/…` (não a `jre/` embutida) e o shim linka
  `libcapstone`/`libpng` do Homebrew.
- **Pedidos de permissão do macOS**: qualquer coisa que faça o **app** ler `~/Documents`,
  `~/Desktop` ou `~/Downloads` abre o diálogo "Instamac quer acessar a pasta…" e bloqueia a
  thread em `opendir` até alguém responder — e volta a cada reassinatura ad-hoc (a
  identidade do app muda para o TCC). Medido: o arquivo de toques do `ui.sh` ficava em
  `build/ui` (dentro de Documents). Estado de ferramentas que o app lê vai em `$TMPDIR`.
  Capturar só a **janela** (`screencapture -l<id>`), não a tela inteira.
- Recursos: o payload só traz o split `xxhdpi` e a janela roda a 160 dpi. Valores
  (`dimen` etc.) com qualificador de densidade são classificados, e rasters são escalados
  do bucket do arquivo para a tela (patch `0008`). Se algo aparecer 3× maior, é um caminho
  que decodifica o arquivo cru: `scripts/ui.sh views` mostra `BitmapDrawable(72x72)`.
- Antes de recompilar uma classe do vendor pela primeira vez, confira que a fonte bate com
  o jar do runtime: `javap -p` da classe do jar × da recém-compilada (só os membros novos
  podem diferir). Todas as tocadas até aqui bateram.
- Diagnósticos novos (todos desligados por padrão): `MACAPK_TRACE_RRECT=1` (cada
  `drawRoundRect` distinto), `MACAPK_TRACE_SETLP=<classe>` (quem define os LayoutParams),
  `MACAPK_TRACE_ATTR=<attr>` (valor bruto por camada), `MACAPK_MEDIA_PROBE=1` /
  `MACAPK_AUDIO_PROBE=1` (entradas/saídas de codec, escritas na trilha, áudio não silencioso).
- `boot-test.sh`/`ui.sh` relançam com `open`; logo após encerrar o app o LaunchServices
  pode responder -600 — os dois tentam de novo.
- `codesign --verify --strict` só passa no app recém-construído: o runtime espelha
  `data/data/<pkg>/*` como links em `android/.macapk/code/<pkg>/`, e quando o Instagram
  apaga um arquivo (ex.: `ig_crash_log_session`) o link fica pendurado. A verificação
  normal (`codesign --verify`) continua válida; não apague esses links à mão.

## Criação, área de transferência e módulos (ADR 0015)
- **Colar no harness**: o Android só lê a área de transferência com a janela em foco.
  Escreva `activate` no arquivo de `MACAPK_DEBUG_HOSTKEY_FILE` antes de `cmd+v` (e
  `deactivate` depois). Use `MACAPK_CLIPBOARD_TEST_PASTEBOARD=<nome>` para não tocar na área
  de transferência do dono.
- **Módulos baixados do Instagram** (`data/data/<pkg>/modules/*/download.zip`) têm de ficar
  `0444`. Quem der `chmod u+w` neles quebra o carregamento ("must be read only").
- **Painel de arquivos aberto num teste** fica na tela do dono: feche com `scripts/ui.sh stop`.
- O verbo `share <n>` do harness segue a tabela `kShareTargets`: hoje 0 = Feed, 1 = Mensagem.


## Câmera e coordenadas (ADR 0017)
- `scripts/ui.sh tap X Y` usa coordenadas de **superfície** (as do `views`), não as da
  captura: a captura inclui a barra de título (32 px). Errar isso parece "o botão não reage".
  Com o Tamanho da Interface automático (ADR 0040) a superfície nesta tela é 515×1144: as
  coordenadas antigas (feitas a 412×915) precisam de ×1,25, ou grave `100` em `.macapk/ui_scale`.
- A página de câmera lembra o último destino (POST abre a galeria, não a câmera).
- A câmera do Mac aparece como `LENS_FACING_EXTERNAL` para webcam USB; não há câmera traseira.
- `MACAPK_DUMP_FRAGMENTS=1` (com `MACAPK_DUMP_TREE_EVERY`) imprime a árvore de fragmentos com
  estado: o jeito rápido de achar "tela montada mas vazia".
- Não editar `boot-test.sh`/`ui.sh` com um `boot-loop.sh` rodando: o bash lê o script durante
  a execução e a abertura daquele momento sai sem resultado (parece travamento e não é).
- Os scripts abrem o app com `open -g` + `MACAPK_NO_ACTIVATE=1` (janela atrás, sem foco);
  `UI_FOREGROUND=1` / `BOOT_FOREGROUND=1` para o modo antigo.

## JDK 25 e cache AOT (ADR 0019)
- O binário de `build-jdk25/` aponta para a JDK do Homebrew; no bundle ele precisa passar por
  `scripts/embed-jre.sh` (reaponta para `@executable_path/jre` e reassina COM entitlements).
- O cache AOT depende dos jars (tamanho+data), das opções da JVM e do caminho da JRE.
  `inject-classes.sh`, `patch-app.sh` ou um runtime novo → `aot-cache: MISS` (abre igual, só
  mais devagar) até rodar `scripts/train-aot.sh`.
- `MACAPK_JVM_OPTS` também entra na chave: testar uma opção nova da JVM = MISS naquela rodada.
- Rodada de treino deixa a abertura lenta (o `ui.sh start` pode reclamar de foco); o script
  espera o Cmd+Q terminar e só então move o cache.

## Harness, clone e preferências (ADRs 0021, 0022)
- Tela parada desenha ~5 quadros/s, e o dump da árvore sai a cada `MACAPK_DUMP_TREE_EVERY`
  quadros: lido depois de um toque, ele podia ter minutos. `ui.sh tree/views` agora pedem o
  verbo `dump` (quadro e dump na hora) e esperam por ele.
- Captura de janela coberta mostra o último quadro apresentado; confirme pela árvore.
- O clone e o app do dono dividem as preferências do runtime (`dev.instamac.runtime`): gravar
  `VideoSoundAtStart` (ou velocidade de rolagem) num teste muda o app do dono. Apagar depois.
- O botão "Enviar post" do feed (Litho) não reage ao `tap` injetado; `hosttap fx fy` (clique pelo
  caminho do Mac) abre a folha. `hosttap` exige `MACAPK_EXTERNAL_URLS=0`.
- **Dentro de folhas e diálogos** (janelas do `WindowManager`: seletor de contas, "Criar",
  "Adicionar Instagram") o `tap` cai na atividade de trás. Use `ui.sh raw "hosttappx X Y"`
  (pixels de superfície, passa pela pilha de janelas flutuantes): medido no seletor de contas →
  "Adicionar conta" → "Entrar na conta existente" → formulário de login (ADR 0035).
- Telas com lista cheia (seguindo, seguidores) não têm barra de abas: (41, 891) cai na última
  linha. Ler a árvore antes de tocar; nunca tocar em "Mensagem"/"Seguindo" das linhas.
- Testar abertura de link com `MACAPK_EXTERNAL_URLS=0`: o log mostra `REFUSED … host open(<url>)`
  com a URL exata, sem abrir o navegador na tela do dono.
- `build-framework.sh` agora inclui `.java` novos (não rastreados) do submódulo, e
  `inject-classes.sh` põe classe nova de `com.macapk.loader` nos dois jars.

## Desempenho (ADR 0023)
- Medir desenho com `MACAPK_FRAME_PHASE_TRACE=1` (fases por quadro) e achar o culpado com
  `MACAPK_DRAW_SAMPLER=1` (métodos mais amostrados durante o desenho; também mostra acertos e
  falhas do cache de pixels). A/B: o mesmo roteiro com `MACAPK_DRAW_CACHE=0 MACAPK_PUNCH_FAST=0
  MACAPK_QUANTIZE_CACHE=0`; o feed muda a cada abertura, então somar várias janelas.
- Janela coberta: o vídeo do feed não toca, e a captura mostra o furo preto da camada de vídeo.
  Não é defeito do desenho.
- A JRE embutida não tem JFR (`jdk.jfr`); `sample` do macOS só mostra Java2D nativo.
- Cache de pixels guardando na primeira vista = GC de segundos. Manter a regra de admitir só
  na segunda vez igual.

## Rastreio de métodos do app (DEX2JVM_TRACE_ENTRY)
- `DEX2JVM_TRACE_ENTRY='^(X/0Foo|X/0Bar)$'` na conversão (`convert-apk.sh`) faz cada método
  dessas classes registrar a entrada (`[W] trace: Classe.metodo… #n`) e os argumentos
  inteiros/booleanos (`argN=…`), nas 30 primeiras chamadas. Só em jar de diagnóstico, só no
  clone (converter leva ~1–2 min; voltar o `classes.jar` normal depois).
- Busca de grupos no compartilhar (2026-11-12): a busca chama `X.0LYV.A01`
  (`direct_v2/ranked_recipients/`, `show_threads=true`, uma vez por letra); o servidor responde
  só contas (`X.0Fta` nunca chama o parser de conversa `X.0Rv3`). No celular os grupos vêm da
  montagem local (`X.0LXU.A03` junta `X.0M4c.A01` e `X.0JKe.A00`); próximo passo: rastrear
  essas duas e a origem das conversas que elas consultam.
- (2026-11-12) No modo de gravação (`MACAPK_AOT_RECORD`, `train-aot.sh`) a abertura para em
  "AppInitScheduler: Waiting on QPLInitializer / PLogCrashRecoveryInitializer" e nunca chega à
  janela; o processo sai em ~40 s e grava um cache só da inicialização (abre em ~11 s, contra
  5–7 s de um treino completo). Aberturas normais não têm essa espera. O `jcmd` não conecta
  nesta JVM ("not ready to participate in attach handshake"); investigar com `sample`.
- (2026-11-12) `~/Movies/TV` (biblioteca do app TV) trava `opendir` indefinidamente, até no
  terminal: qualquer varredura de `~/Movies` precisa de prazo. O `MediaStoreProvider` agora
  pula essa pasta e lista as outras com prazo (ADR 0028). Para testar o "+" pelo fluxo do
  próprio Instagram (sem abrir o painel do Mac), `MACAPK_HOST_CLICK=none`.
- Um resultado de A/B numa única rodada pode enganar: a grade cinza da galeria "sumiu" com uma
  chave desligada uma vez e voltou numa segunda rodada igual. Repetir antes de concluir.
- (2026-11-12) Reassinar o binário do runtime (`embed-jre.sh`, `bundle-host-libs.sh`) muda a
  assinatura ad-hoc, e o macOS esquece a permissão de câmera (e microfone): na próxima
  abertura da câmera aparece o pedido de novo e o runtime desiste em 30 s
  ("timed out after 30s waiting for the macOS camera permission prompt"). O dono precisa
  permitir uma vez. Solução duradoura: assinar com uma identidade local estável (certificado
  autoassinado no chaveiro) — a importação no chaveiro precisa de autorização do dono.
- O clone de teste também precisa da permissão de câmera (pede na primeira vez).
- Rastreio de argumentos objeto (`traceArgObj`) em classes do compartilhar quebrou a lista
  padrão da folha; usar só em classes onde chamar `size()`/`getClass()` não tem efeito.
- (2026-11-12) `INSTAMAC_APP` vindo de `$TMPDIR` tem `T//` e o processo roda como
  `/private/var/...`: o `pgrep` do `ui.sh stop` não casava e o app velho seguia aberto (testes
  rodavam com o código antigo). `ui.sh` e `boot-test.sh` agora resolvem o caminho físico.
- Toque injetado (`ui.sh tap`) vai para a janela da atividade e atravessa diálogos; num diálogo
  use `ui.sh raw "hosttap fx fy"` (com `MACAPK_EXTERNAL_URLS=0`).
- O modo de gravação AOT verifica as classes do app (fora dele a verificação fica desligada):
  um `VerifyError` só aparece no treino. Procure "VerifyError" e "System.exit(10)" no log.
- Antes de medir a galeria, confira "Novo post" na árvore: o Instagram reabre no último modo de
  criação (a câmera do Story mede "0 cinza").
- `kill -3` (SIGQUIT) MATA o app: o runtime não a repassa à JVM e não sai dump de threads.
- `ui.sh raw "hosttap fx fy"`: `fy` conta de BAIXO para cima (Cocoa); o toque em y px do topo é `fy = 1 - y/915`.

## Segundo plano e notificações (ADR 0037)
- Janela **coberta** conta como fora de vista: o app vai a `onStop` em 1 s. Os testes abrem o app
  atrás das janelas do dono, por isso `ui.sh` e `boot-test.sh` gravam
  `MACAPK_BACKGROUND_ON_OCCLUSION=0`. Para testar o segundo plano: `ui.sh raw miniaturize` /
  `deminiaturize` (o `hide` de um app inativo gera um "visível" logo depois e o atraso anula).
- Captura de janela coberta mostra o último quadro: "vídeo preto" depois de um `unhide` era isso.
- `UNUserNotificationCenter` nega sem pedido qualquer app sem assinatura da Apple neste macOS
  (ad-hoc e "Instamac Local Signing" incluídos); o auxiliar cai no `NSUserNotificationCenter`.
  Log do auxiliar: `~/Library/Logs/macapk/notifier.log`.
- Simular clique numa notificação: postar `dev.instamac.notifier.clicked` {key} por
  `NSDistributedNotificationCenter` (osascript -l JavaScript).
