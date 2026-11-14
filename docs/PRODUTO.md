# Produto: o que a build entrega

## Contrato

```bash
git clone <repo> && cd instamac
git submodule update --init
scripts/build-dexconv.sh      # tradutor com nossos patches
scripts/build-instamac.sh     # embute o payload/, pré-instala e assina
open build/Instamac.app       # abre já no Instagram instalado
```

`Instamac.app` é **um app só**, e ele já contém o Instagram instalado: APK, classes
convertidas para a JVM e libs nativas traduzidas. Duplo clique → a janela do Instagram
abre na tela de login. Sem runtime auxiliar à vista, sem select de APK, sem espera de conversão, sem nada
em `~/Library`.

## O que existe hoje (v0, verificado nesta máquina)

- `build/Instamac.app`, assinado ad-hoc, `codesign --verify --deep --strict` ok.
- Runtime upstream **embutido** em `Contents/Resources/runtime/` (com o loader jar já
  patchado a partir de `build/classes`).
- APK embutido em `Contents/app/embedded/`, sem symlink para fora do bundle.
- **Instagram instalado dentro do bundle**: `Contents/android/` já tem `data/app/*/base.apk`,
  `.macapk/code/<pkg>_<ver>/classes.jar` e `lib_native/` traduzidas. É o mesmo layout que o
  runtime produz numa primeira abertura — feito no build por `scripts/preseed.sh`.
- A conversão (DEX→JAR) e a tradução ARM32→arm64 **não acontecem na máquina de quem usa**:
  viajam prontas dentro do bundle. Uma abertura = um boot quente (~segundos de JVM), igual
  à segunda abertura em qualquer app nativo.
- Processo aparece como `.Instamac`; menu do app mostra o rótulo do payload.
- Sem notarização: ad-hoc abre nesta máquina; em outra, botão direito → Abrir.
- Depois da primeira abertura o **selo do bundle deixa de conferir** (`codesign --verify`
  acusa recurso alterado): o Instagram escreve dados e cache dentro de `Contents/android`,
  e isso muda o conteúdo selado. Ad-hoc não é verificado no lançamento, então o app abre
  normalmente; um build/notarização de distribuição terá de resolver isso movendo o estado
  mutável para fora da área selada.

## Anatomia do bundle

```
Instamac.app/
  Contents/
    Info.plist                 CFBundleName/DisplayName = Instamac
    MacOS/
      Instamac                 nosso launcher (~60 KB, Swift)
      .Instamac -> ../Resources/runtime/Resources/macapk-runtime
    Resources/runtime/         runtime embutido (bin, lib, Resources/jre, translator)
    app/embedded/              o container do Instagram (base + splits), fonte do install
    android/                   o Instagram JÁ INSTALADO
      data/app/~~…/…/          base.apk + splits, como num device
      .macapk/code/<pkg>_<ver> classes.jar convertido + lib_native/ traduzidas
      data/data/<pkg>_<ver>/   dados do app (sessão, prefs, mídia)
      sdcard/                  armazenamento externo simulado
```

O launcher só faz uma coisa: acha o APK embutido (ou o `base.apk` já instalado), acha o
runtime, e `execv` com `--apk … --android-root Contents/android` — o mesmo contrato do stub
do runtime upstream. Não há diálogo: se o bundle não tem payload, é build incompleto e o launcher
diz isso.

## Pré-instalação (o passo que faz "por natureza")

`scripts/preseed.sh <Instamac.app>` roda o runtime duas vezes contra `Contents/android`:

1. **fria** — instala (data/app), converte os DEX e traduz as `.so`; para no primeiro frame.
2. **morna** — relança e exige chegar ao frame **sem** `cold install (DEX->JAR)`.

A segunda passada é o gate: se ela reconverter, o cache não está sendo aceito e o build
falha. O sinal de parada é o log do runtime (`first frame presented`), não um `sleep`.

Custo: uma conversão por build. Para não pagar duas vezes, `scripts/deploy.sh` pula o
preseed quando vai copiar a árvore já preparada do app instalado.

## F1c — o bug que impedia reabrir o app (corrigido)

Sintoma: o Instagram abria só na primeira vez. Na abertura seguinte, com dados já gravados,
morria antes de existir atividade:

```
[E] Mac.apk.Boot: FATAL EXCEPTION: SWPool1_t2of3
java.lang.IllegalArgumentException: Bad arguments
    at javax.crypto.Cipher.doFinal
    at android.security.keystore.AndroidKeyStoreCipherSpi.engineDoFinal
...
[I] Mac.apk.Process: System.exit(10) from the app (no activity ...)
```

Causa: o contrato do `Cipher` do Android aceita entrada **nula** em
`engineDoFinal`/`engineUpdate` (o caminho de `CipherInputStream` sem argumento passa
`(null, 0, 0)`). O nosso SPI repassava o `null` ao `Cipher` do JDK, que responde
`IllegalArgumentException("Bad arguments")` — o Instagram trata isso como erro fatal de dex
e chama `System.exit(10)`. Toda leitura de dado cifrado (prefs, cache) derrubava o app.

Correção (`src/framework/android/security/keystore/AndroidKeyStoreCipherSpi.java`):
normalizar `null` para array vazio nas quatro entradas (`update`, `update` com buffer,
`doFinal`, `doFinal` com buffer) e ignorar AAD nulo. É o que os providers da plataforma
fazem. O build injeta a classe em `android-framework.jar` (`scripts/build-framework.sh`).

## F1d — `/dev/zero` não mapeia no macOS (corrigido)

Sintoma no log: `[arm64-mmap] mmap(... lin_flags=0x0 fd=109) -> FAILED` em série,
`MainThreadWatchdog: RED` de ~1 s recorrente, e — no pior caso — o `libstartup.so`
andando por cima de um ponteiro nulo até estourar o teto de 100M recuperações do shim
(aí o processo morre).

Causa: o Instagram usa o truque de Linux de mapear `/dev/zero` com
`mmap(..., MAP_SHARED/MAP_PRIVATE, fd, 0)` para obter memória zerada
(`com.facebook.analytics.memory.AddressSpace` faz isso para medir o limite de espaço de
endereçamento). **O macOS recusa qualquer mapeamento de `/dev/zero`** —
`ENODEV`, "Operation not supported by device" (medido com um binário C de 20 linhas:
`flags=0` → `EINVAL`, `MAP_SHARED`/`MAP_PRIVATE` → `ENODEV`). No Android a chamada
funciona; aqui ela falha, e quem não checa o retorno segue com ponteiro nulo.

Correção (`contrib/upstream/patches/0002-linux-memory-syscalls.patch`, aplicado em
`runtime/translator/src/bionic_shim.cpp`): quando o `mmap` do host falha e o fd é
`/dev/zero` (ou `/dev/null`), servir a semântica do Linux — um mapeamento anônimo
privado, que é exatamente a mesma memória (todo página desses devices é zero). O offset
é descartado junto com o arquivo.

Efeito medido: `mmap FAILED` = 0 (era uma série por passada do probe), `anonymous zero
pages` = 8 no primeiro launcher, app sem estourar o teto do null-recovery.

## F1e — janela preta ao trazer o app para frente (corrigido)

Sintoma: o Instamac abria e a janela ficava **totalmente preta** — sem logo, sem campo de
login, sem nada. Dava para achar que o app tinha morrido.

Medido, não suposto: a mesma janela capturada com o app coberto (`screencapture -l`) sai
preta; capturada com o app ativo, sai com a tela de login inteira. O runtime detecta
oclusão (`NSWindowOcclusionStateVisible`) e **pausa/reduz a apresentação a 2 Hz** para
economizar energia; a janela então volta sem frame desenhado, e o usuário vê preto.

Correção: o launcher agora exporta `MACAPK_PAUSE_WHEN_HIDDEN=0` por padrão — a camada de
compatibilidade de desktop precisa estar pronta quando o usuário olha para ela. O custo é
continuar desenhando enquanto a janela está coberta; num app único, foreground, é o
trade-off certo. Override em `Contents/android/.macapk/runtime_env`.

## F1f — `munmap` por syscall cru não existia (corrigido)

`syscall(215, ...)` — `SYS_munmap` do arm64 — caía em `UNIMPLEMENTED -> -ENOSYS`. O
export `munmap` da libc sempre funcionou, mas quem emite o **syscall cru** (o caminho de
memory-analytics/lacrima da Meta faz isso) não liberava nada: medido como
`open("/dev/zero")` + `mmap(4 MB)` + `syscall(215) ENOSYS` repetindo a cada ~500 ms, um
vazamento de 4 MB por passada, e a tempestade de `libstartup.so` no shim
(`[null-recovery] … SWPool3_t1of1`).

Correção: rota `case 215` no `__macapk_arm64_syscall_impl`, chamando
`__macapk_arm64_munmap` (mesma semântica do export libc).

## F1q — a causa do boot travado: o passe de canário zerava um campo (corrigido)

**Medido em 2026-11-11.** O travamento não era corrida nem dado corrompido: era
**determinístico com sessão logada**. Seis árvores de `data/data` logadas guardadas em
`/tmp` travaram 6/6; a árvore deslogada abriu 10/10. Só com `UserSession` o
`X.03yo.run` chama `CacheKeyGenerator.initializeKeyGenerator(json)`, com o JSON de
cache-key do MobileConfig (`backendConfigs`/`queryParamLists`, 5,2 KB) — e esse JSON só
existe na árvore depois que o MobileConfig da sessão foi baixado. Por isso "apagar os
dados" parecia resolver: a primeira abertura depois do reset ainda não tem o JSON.

Cadeia medida (sem debugger: SIP ligado e o runtime sem `get-task-allow`):

1. `MACAPK_NULL_RECOVERY_NEARNULL=0` transformou a primeira falta mascarada em crash: a
   falta é em `libstartup+0x4452e8`, `ldr x9,[x20+0x50]` com `x20 = 0`, e o próprio
   crash handler do Instagram a recebe — ou seja, o estado já divergiu antes.
2. `MACAPK_FAULT_DUMP=1` (diagnóstico novo no shim) mostrou o nó do `std::map` com o
   `begin` **correto** na memória (`0x78968aa840`, `size=1`), mas `x20 = 0` lido dele
   13 instruções antes, sem nenhuma chamada no meio.
3. O código **vivo** em `+0x445258` é `d2800014` (`mov x20,#0`); no arquivo é
   `f9401554` (`ldr x20,[x10,#0x28]`).
4. `MACAPK_CANARY_TRACE=1`: `libstartup.so backstop 0x445258 (x20<-[x10,#0x28])`. O braço
   *backstop* do passe de neutralização de canário confundiu `begin == end?` (com `end()`
   guardado na pilha: `ldr x8,[sp,#0x70] ; cmp ; b.eq`) com a checagem de canário, porque
   o campo está em `+0x28`, o mesmo offset do slot do canário no TLS do Bionic.

Correção (`arm64_native.cpp`, patch `0006`): o passe lembra, por função, o slot onde o
prólogo salvou o canário (`[sp,#0x228]` aqui) e o backstop só reescreve quando a
comparação recarrega esse slot. Resultado medido:

| | antes | depois |
|---|---|---|
| árvores logadas guardadas que abrem | 0/6 | 6/6, no feed (`InstagramMainActivity`), 8–10 s |
| sites recusados pelo backstop (42 imagens) | — | 1, exatamente `libstartup+0x445258` |
| sites restantes do backstop que levam a `__stack_chk_fail`/epílogo (auditoria offline) | — | 5.764 / 5.764 |
| aceitação P0: 10 aberturas seguidas, mesma árvore logada | — | **10/10**, no feed, 5–9 s (`build/boot/p0-final/summary.txt`) |
| mesmo critério com `MACAPK_RESOLUTION_UI=1` (lock de resolução) | — | **10/10** (`build/boot/p1-lock/summary.txt`) |

As explicações anteriores (F1g "dados de crash", F1h "processo-filho", F1k/F1l "dois
displays", F1m "x18 sem TLS") eram correlações de tempo: cada uma mudava se o MobileConfig
já estava carregado quando o init rodava. As correções delas continuam válidas por si, mas
nenhuma era a causa deste travamento.

Ferramentas novas: `scripts/boot-test.sh` (modo `launcher` = abre pelo bundle como o Dock;
`BOOT_RUNTIME_ENV` para A/B sem recompilar; `sample` + `jcmd` automáticos ao travar) e
`scripts/boot-loop.sh N <árvore>` (taxa real em N aberturas seguidas).

## F1s — retrato: menus, ícones e botões que não apareciam (corrigido)

Medido em 2026-11-11 com `scripts/ui.sh` (toques injetados, captura da janela, árvore de
views). Em retrato (500×800 dp) o Instagram usa o layout de telefone; cinco defeitos, cinco
causas no runtime, nenhuma no app:

| o que se via | causa medida | correção |
|---|---|---|
| sem barra de abas inferior | `dimen/tab_bar_height_panorama` só existe em `-xxhdpi` (no split); o runtime descartava valores com qualificador de densidade → altura 0 | densidade em valores é classificada, não descartada (`0008`) |
| ícones 3× maiores: botão "mais" 92×96, ícone de Reels 72 dp, logotipo 349 dp | 3.227 rasters do split `xxhdpi` usados em pixels crus numa tela de 160 dpi | escala do bucket do arquivo para a tela, inclusive 9-patch (`0008`) |
| "Editar perfil"/"Compartilhar perfil" sem fundo | cor que é alias para um arquivo de lista de estados não era seguida | alias de cor chega ao arquivo (`0008`) |
| chips do perfil com um canto do ícone | `ImageView` encolhia os bounds; o vetor do app posiciona por gravidade | bounds intrínsecos + matriz para drawables do app (`0009`) |
| abas do perfil (grade/reels/marcados) sem ícone | o inflador reescrevia a largura por cima do `generateLayoutParams` do `TabLayout`, que ignora o XML de propósito | a resposta da sobrescrita do app é final (`0009`) |

Também caíam dois construtores de view (`CornerPunchedImageView`, `FittingTextView`) por
`getNonResourceString` estubado e por referência numérica `@0x7f…` não entendida — hoje
**0 construtores falhando** no log.

O predicado do app: `X.01rq.A06(larguraDp)` → trilho lateral só com largura ≥ 600 dp.

## F1t — vídeo e som (corrigido)

Três bloqueios em cadeia, medidos com `MACAPK_MEDIA_PROBE=1 MACAPK_AUDIO_PROBE=1`:

1. **Buffer de entrada não era limpo.** `MediaCodec.dequeueInputBuffer` devolvia o buffer
   com o limite do uso anterior; o player do Instagram confia na garantia do AOSP e
   descarta a amostra (`Input buffer guard dropped sample (sample of 186 exceeds
   destination 184)`). VP9: `in=11, codec_out=0` → depois `150 in / 150 out` por 5 s.
2. **O item de Reel era um método estubado.** `X/09IF.A0p` (68.700 bytes) lançava e a aba
   mostrava "Esse reel está indisponível". Resgatado com slots locais por frequência
   (61.730 bytes; patch `0011`), sem dividir o método.
3. **O áudio dos Reels é xHE-AAC** (`mp4a.40.42`). O decoder abria como AAC comum, aceitava
   232 unidades e não devolvia nada; sem áudio pronto a reprodução inteira parava. O
   AudioToolbox tem o decoder (`usac`), mas exige o `ES_Descriptor` completo como cookie
   — conferido contra o cookie que o AudioFile entrega para uma trilha real.

| medição | antes | depois |
|---|---|---|
| autoteste com trilha xHE-AAC real | `no decoder` | `frames=237568 rms=5901 -> PASS` |
| autoteste HE-AAC / AAC-LC | PASS | PASS |
| aba Reels: quadros apresentados em 5 s | 0 ("indisponível") | ~120 |
| aba Reels: bytes escritos na trilha em 5 s | 0 | 962.560 (48 kHz estéreo) |
| saída de áudio não silenciosa | — | 469/469 renders, 0–1 underrun |

Amostras reais para teste saem do cache do player
(`data/data/<pkg>/cache/ExoPlayerCacheDir/videocache/*a.-1.*.0.*.exo`, fMP4; remuxar com
`ffmpeg -c:a copy` para o autoteste).

## F1r — crash ~1 min depois de abrir logado: SQLite do macOS no lugar do do app (corrigido)

Com o boot resolvido (F1q), apareceu o próximo bloqueio: o app logado morria entre 10 s e
~1 min depois de abrir. Cadeia medida no log do próprio runtime:

- `SIGILL` na thread `SWPool3` executando `0x70422f8c28` — endereço de **pilha**, não código;
- chamada vinda de `libscrollmerged.so+0x67689c` (`blr` para o GOT de `sqlite3_exec`) →
  `libsqlite3.dylib` **do macOS** → `walIndexReadHdr` → `sqlite3_log` → o callback de log;
- a `libstartup.so` do Instagram **traz o SQLite inteiro**, mas o loader ligou os imports
  `sqlite3_*` da `libscrollmerged.so` ao `libsqlite3` do sistema.

`sqlite3_config(SQLITE_CONFIG_LOG, fn, arg)` é variádica: o Bionic passa os variádicos em
registradores e o ABI arm64 da Apple os lê da pilha, então o SQLite do host guardou uma
palavra da pilha como callback; a primeira recuperação de WAL o chamou. Além disso, dois
motores SQLite diferentes operavam os mesmos `-wal`/`-shm`.

Correção (`arm64_native.cpp`, patch `0007`): a mesma regra que o loader já aplicava à
cripto da Apple — se o símbolo do host vem do `libsqlite3` e uma imagem do app o define,
liga ao do app (`MACAPK_GUEST_SQLITE=0` volta ao comportamento antigo).

| sessões logadas de 150 s | SQLite do macOS | SQLite do app |
|---|---|---|
| resultado | morreu 2/2 (11 s, 29 s) | sobreviveu 3/3, sem `SIGILL` |

`scripts/boot-test.sh` agora acusa esse tipo de falha: com `BOOT_HOLD=N` ele vigia o
processo depois do foco e responde `ABRIU … e MORREU Ns depois do foco` (exit 3).

## F1g — dados do app podem travar o boot (recuperável)

> Superado por F1q: a causa medida do travamento é o passe de canário, não o estado dos dados.

Medido: com `data/data/<pkg>` recém-criada a build abre no feed; com a árvore que sobrou
de um crash/resize anterior, o boot trava **antes da atividade** — main looper em
`dispatched #1`, tempestade de null-recovery em `libstartup.so` (+0x445084, dentro de
`folly::dynamic`), janela preta para sempre.

É estado da aplicação, não da build: o mesmo binário e o mesmo runtime funcionam com a
árvore limpa. Recuperação sem perder a conta (o login mora em `data/system`, que não é
tocado):

```bash
scripts/reset-app-data.sh
```

Ela move `data/data/com.instagram.android_*` para `/tmp/instamac-data-<data>` (o estado
antigo fica lá para diagnóstico) e reabre o app.

## F1o — performance: o log era o custo escondido

O log por sessão tinha **180.653 linhas**, das quais **55.532** eram de carregamento de
classe (`AppCl`), escritas em arquivo durante o boot. Ligando as portas que o runtime já
tem — `MACAPK_QUIET_CLASSLOAD=1` e `MACAPK_LOG_LEVEL=4` (piso INFO do AOSP) — a mesma
sessão caiu para **4.060 linhas**. É I/O de boot a menos, e o log fica legível.

## F1p — resolução fixa (retrato / widescreen) — implementada, ligada por flag

Pedido: duas medidas fixas, sem redimensionar, sem tela cheia, com item de menu
("travar resolução", sempre ativo, destravar desaconselhado). Está implementado no runtime:

- presets **widescreen 1280×800** e **retrato 832×1280** (mesma proporção, ambos na classe
  tablet do Android);
- menu **View → Resolução fixa** com Widescreen / Retrato / Destravar (não recomendado);
- com o lock ativo: janela sem alça de redimensionar, botão verde escondido e
  `FullScreenPrimary` removido — tela cheia não existe;
- a escolha persiste em `<root>/.macapk/resolution`.

**Medido**: aplicar o estilo/resize com o app já desenhando (4 s e 20 s depois) ainda
derrubava o boot de vez em quando — o mesmo descompasso entre Configuration e superfície
que o caminho `--width/--height` tinha. Por isso o recurso está **ligado por flag**
(`MACAPK_RESOLUTION_UI=1`) e desligado por padrão até o boot ficar estável; o que está
sempre ativo é o **tamanho de tablet** (a janela nasce 1280×800 via `MACAPK_WINDOW_BUDGET`).

## F1m — o boot travado: x18 sem TLS nas threads da JVM (corrigido)

Medido com `jcmd Thread.print` em três travamentos seguidos: `SWPool3_t1of1` a **98% de
CPU** dentro de `CacheKeyGenerator.initializeKeyGenerator` (nativo) e a main do app parada
em `CacheKeyGenerator.isInitialized`. O shim "recuperava" cada falta de memória zerando o
destino, então um ponteiro nulo virava uma estrutura de zeros e o `folly::dynamic` girava
para sempre.

Causa: o bloco de **TLS do Bionic** (x18) só era instalado na thread do loader
(`Image::run_init_array`). Guest code rodando em thread criada pela JVM lia `[x18+k]` com
x18 nulo — toda leitura falhava, o shim mascarava para zero, e aí a estrutura inteira
nascia zerada.

Correção (shim, `bionic_shim.cpp` + `arm64_native.cpp`): quando a falta é um load por x18
e x18 não tem o bloco instalado, o handler **instala o TLS daquela thread e re-executa a
instrução** (PC não avança) em vez de mascarar. Medido depois: **4/4 aberturas seguidas
sem travar**, com a mesma árvore que travava 3/3 antes.

## F1n — o rail com ícones gigantes e cortados

Captura do Kai: rail de tablet com ícones esticados e o último item cortado. Causa: num
monitor 1x o runtime mapeia 1dp = 1px, então a janela de 2560px faz o Instagram ver uma
tela de **2560dp** de largura (o dobro de um tablet real). Correção: o launcher nasce com
`MACAPK_WINDOW_BUDGET=1280x800` — o app vê 1280x800dp, tamanho de tablet — e a janela
continua redimensionável. Verificado: rail com ícones quadrados, espaçamento certo,
avatar no lugar.

## F1h — o boot travado era o processo-filho (supervisor removido)

Havia um supervisor no launcher: o runtime rodava como FILHO, o log era observado e, sem
foco de janela em 60 s, ele matava o filho, afastava caches (e depois a árvore inteira) e
subia de novo. Funcionava, mas custava o login e tratava sintoma.

Medição que derrubou o desenho: **rodando o runtime direto, 3 aberturas seguidas passaram;
rodando como filho, travava em boa parte delas.** A causa é a identidade: um processo-filho
do launcher não pertence ao bundle (`lsappinfo` reporta `bundleID = NULL`), então o AppKit
o trata como processo avulso e o init do Instagram perdia a corrida no
`CacheKeyGenerator.initializeKeyGenerator` (thread SWPool3 girando; main parada em
`isInitialized`).

Correção: o launcher volta a ser `execv` — o runtime **é** o processo do app, com a
identidade do bundle (menu, Dock, foco, encerramento). Medido depois da troca: **4/4
aberturas sem travar**. O supervisor saiu do código; recuperação de estado ruim agora é
explícita e manual: `scripts/reset-app-data.sh`.

## F1h-b — supervisor (histórico)

O launcher deixou de ser um `execv`: ele agora roda o runtime como filho, observa o log
e, se `delivering window focus` não aparecer em 110 s, faz o que o usuário teria de fazer
à mão — mata o processo, afasta `data/data/com.instagram.*` para o temporário e sobe de
novo, uma vez por abertura. O login sobrevive porque a conta mora em `data/system`.

Medido com uma árvore de dados que reproduzia o travamento (thread `SWPool3_t1of1` em
`CacheKeyGenerator.initializeKeyGenerator` a 98% de CPU; a main do app parada em
`CacheKeyGenerator.isInitialized`; janela preta para sempre):

```
---- boot sem primeiro frame em 110s; recuperando dados do app ----
---- estado antigo em /var/folders/…/instamac-recovery-2026-11-11T02-45-48Z
```

e o app abriu no feed. O marcador de sucesso é o **foco de janela na atividade**, não o
primeiro frame: o primeiro frame é o placeholder e aparece mesmo quando a atividade trava.

Duas correções no caminho: o relógio da recuperação só começa depois da linha
`app=com.instagram.android jar=…` (a reconversão de código acontece antes dela e leva 1-2
min — um boot frio nunca é confundido com travamento), e a recuperação tem **dois
estágios**: primeiro remove só caches (`cache/`, `code_cache/`, `.windowtraits`), o que
preserva `shared_prefs` e portanto o login; só se ainda travar move a árvore inteira para
o temporário. O estágio usado fica escrito no log (`---- caches removidos; reiniciando
(login preservado) ----` ou `---- segunda tentativa também travou; movendo os dados ----`).

## F1i — mídia verificada por self-test (áudio e vídeo)

O runtime tem dois self-tests embutidos que rodam sem abrir o app:

```bash
MACAPK_MEDIA_SELFTEST=1 MACAPK_MEDIA_SELFTEST_FILE=/tmp/mdtest.m4a macapk-runtime --apk …
MACAPK_VIDEO_IMAGE_SELFTEST=1 MACAPK_VIDEO_IMAGE_SELFTEST_FILE=/tmp/goi_test.h264 macapk-runtime --apk …
```

Medido nesta máquina (arquivos gerados com ffmpeg):

| caminho | resultado |
|---|---|
| AAC (audio/mp4a-latm, 44.1 kHz) | `RESULT frames=90112 rms=2866 -> PASS` |
| H.264 (raw annex-b, 320x240) | 18 frames decodificados, PNG 320x240 escrito |
| decoders registrados | avc e hevc por hardware (VideoToolbox); vp8/vp9 e mp4v/mpeg2/3gpp por software, libvpx **estático** no binário |

Ou seja: o decode existe e funciona. Se um reel específico falhar, o problema é do caminho com
Surface (render por cima da view) ou do container, não do decoder.

## F1i-b — por que o reel fica preto (medido, não suposto)

Com o app aberto e um vídeo na tela, o log mostra o caminho inteiro e onde ele para:

```
[W] IgMetaConfig: Could not obtain MC: not_user_session
    ... at com.facebook.video.cache.igdatasource.IgHttpDataSource.open()
[W] UnifiedPrefetchManager: Manifest for videoId ... is missing prefetch segment range
```

O `MediaCodec` de vídeo **nunca é criado** (`video/avc` aparece só como sonda de
capacidade do VideoToolbox: `max=4096x2304 ... decode-probed`). Ou seja: o decoder está
provado (self-tests), mas o stream nunca chega nele. A requisição passa pelo Tigon e cai
em `Could not obtain MC: not_user_session` — o MobileConfig que a camada de vídeo usa não
existe numa sessão anônima; o app segue com defaults e o prefetch não monta o segmento.

Conclusão medida: **vídeo depende de sessão iniciada**. Para validar de verdade é preciso
estar logado e abrir um reel; com a tela de login, o caminho de rede do vídeo não fecha.

## F1j — o stub agora se anuncia no log

`emitUnsupportedBody` passou a emitir `Log.w("macapk-stub", <motivo>)` antes do
`UnsupportedOperationException`. Antes, um método estubado era invisível: o Instagram
captura exceções e as manda para o próprio error reporter, então "a tela não faz nada" não
deixava rastro. Agora:

```bash
grep -c "macapk-stub" ~/Library/Logs/macapk/app_com.instagram.android_*.log
```

Na reconversão do Instagram 455 apareceram **2** métodos estubados
(`X/09IF.A0p`, `X/0bRx.getValues`) — o terceiro (o `invoke` de 168 KB) não é mais emitido
como stub, então a lista do F1B encolheu.

## F1k — retrato de primeira classe, e o descompasso entre dois monitores

`scripts/set-orientation.sh portrait` grava a preferência de janela que o runtime já
entende (a mesma do Cmd+R, em `<root>/.macapk/window_pref/<pkg>`). Medido: janela retrato
644x1284pt, `frame-score RICH`, feed logado. `--width/--height` cru continua proibido:
ele cai na regra legada (sem modelo de exibição AOSP) e trava o boot.

Medição desta máquina que explica a instabilidade: há **dois displays** (2560x1440 e
1080x1920). O orçamento da política vem de `[NSScreen mainScreen]` (2560x1284pt), mas a
janela às vezes nasce no display secundário (1080x1890, x negativo). Ou seja: o app pode
receber um Configuration de 2560x1284 enquanto a superfície real é 1080x1890 — o tipo de
incoerência que alimenta o loop do `CacheKeyGenerator` e a corrupção de estado
recuperada pelo supervisor. Próximo alvo: escolher o display uma vez (orçamento E janela)
e prender o frame a ele.

## F1l — uma tela por lançamento (dois monitores)

Medido: `[NSScreen mainScreen]` responde pela **janela-chave**, então muda enquanto as
janelas se movem. Nesta máquina com dois displays (2560x1440 + 1080x1920) o orçamento da
política veio de uma tela (2560x1284pt) e a janela nasceu na outra (1080x1890, `x=-1080`):
Configuration de um display, superfície de outro. É a incoerência que alimenta o loop do
`CacheKeyGenerator` e o estado corrompido que o supervisor recupera.

Correção em `cocoa_bridge.mm`: a tela é escolhida **uma vez** por lançamento — a que está
sob o mouse, senão `mainScreen`, senão a primeira — e a mesma tela serve o orçamento da
política e a centralização da janela (`macapk_launch_screen()`).

## Identidade: o app é Instamac, em toda superfície

Medido e corrigido nesta rodada: o nome no **menu bar** vinha do `__TEXT,__info_plist`
embutido no binário do runtime (não do bundle, não do label de janela), e o ícone do
**Dock** vinha do ícone extraído do APK. Agora:

| superfície | fonte | estado |
|---|---|---|
| nome no menu bar | `macapk-runtime-info.plist` embutido no binário | **Instamac** |
| título da janela | `MACAPK_APP_LABEL=Instamac` (launcher) | **Instamac** |
| Dock / Cmd-Tab | `MACAPK_APP_ICON=…/InstamacIcon.png` + `MACAPK_ICON_ROUND=0` (fixo no launcher) | o ícone do bundle, na grade da Apple (trocar com `scripts/set-icon.sh`) |
| app menu / About | título do método `install_menu_bar` re-afirmado no launch | **Instamac** |
| identidade Android (Build.BRAND, EGL_VENDOR, Telephony, Sensor, InputMethod, AudioEffect/AudioDeviceInfo) | classes do framework | **Instamac** |

O ícone é **fixo por construção**: o launcher passa sempre o PNG do Instamac, e o runtime
tem um único ponto que aplica ícone de app (`setApplicationIconImage`), no launch.

O nome do projeto upstream continua citado **apenas** onde a AGPL exige atribuição
(NOTICE/README/licença). Nenhuma superfície do app o mostra.

## Atualizar o Instagram

```bash
open -a Instamac --args --apk ~/Downloads/instagram-novo.xapk
```

O launcher copia o container para `Contents/app/embedded/`, derruba o código da versão
anterior e o runtime reinstala no lançamento seguinte. Dados de `/data/data` da mesma
versão sobrevivem; versão nova do Instagram começa com dados novos (decisão do runtime:
versões são independentes).

## Restrição legal que molda o produto

O Instamac **não redistribui o Instagram**. O `payload/` não é versionado: um bundle
construído na sua máquina carrega o APK que você forneceu, e distribuí-lo é distribuir obra
da Meta. Para o uso próprio e para o desenvolvimento, o app sai completo; para fora, o
produto é o instalador fino que embute o payload de quem usa.

## Pendências (v1)

1. **Assinatura de distribuição**: Developer ID + notarização. Para uso próprio, ad-hoc basta.
2. **Reparo**: um botão "reinstalar" que repete o preseed para o payload corrente.
3. **Primeiro boot pós-update**: hoje a atualização de versão reinstala e reconverte na
   abertura seguinte (não dá para pré-converter sem conhecer o APK novo antes).
4. **Migração de sessão entre raízes**: `scripts/deploy.sh` preserva só o `sdcard`. Copiar
   `data/data` de uma árvore antiga para uma recém-preseedada carrega `.androidkeystore` e
   prefs cifradas da raiz antiga, e o Instagram morre no boot
   (`IllegalArgumentException` em `AndroidKeyStoreCipherSpi` → `FatalDexError` →
   `System.exit(10)`) antes de existir atividade. Medido neste deploy; a saída é mover a
   chave mestra junto ou migrar as prefs de forma ciente do keystore.
