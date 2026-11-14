# ADR 0019 — JDK 25 embutida no app e cache AOT de classes

**Status:** aceito em 2026-11-12 (gate na cópia de teste; troca no app instalado depois)

## Contexto
O runtime ligava a `libjvm` da JDK 21 do Homebrew (o app não roda num Mac sem Homebrew) e
abria sem nenhum compartilhamento de classes: a cada abertura, ~17 mil classes do Instagram
lidas, verificadas e ligadas de novo (232 MB de metadados, ADR 0018). O projeto de origem
previu a troca (`MACAPK_JDK`, `stage_jre.sh`, `MACAPK_AOT_CACHE`), mas o vendor veio sem as
correções do `java.base` para a 25 e sem o `jdk25_bake.sh`.

## Decisão
1. **Runtime ligado à JDK 25** (`vendor/macapk/runtime/build-jdk25`, `JAVA_HOME` da 25).
2. **Correções do java.base rebaseadas** para a 25 em `runtime/java_base_patch_jdk25`:
   mesclagem de 3 vias (original 21 → nossa 21 → original 25); um conflito, no
   `Reflection.java` (filtro de campos do `ClassLoader`), resolvido à mão mantendo a correção.
3. **JRE mínima própria** (`stage_jre.sh`, 60 MB) com as correções **gravadas** nos módulos
   (`debug/jdk25_bake.sh`; o `module-info` do `java.base` perde o atributo `ModuleHashes`
   via `debug/StripModuleHashes.java`, senão o `jlink` recusa o `jdk.unsupported` alterado).
   Sem `--patch-module`, o HotSpot aceita CDS/AOT.
4. **Embutida no bundle** (`scripts/embed-jre.sh`): `Resources/runtime/Resources/jre`, binário
   reapontado para `@executable_path/jre/...` e reassinado com as entitlements de JIT/x18.
   O build oficial faz isso na etapa 4c (`INSTAMAC_JDK=21` desliga).
5. **Cache AOT** (JEP 483/514): o launcher liga `MACAPK_AOT_CACHE=1`; o cache é treinado por
   `scripts/train-aot.sh` (abre atrás das janelas, navega pelas abas, encerra com ⌘Q — nesse
   modo o runtime sai por `Runtime.halt` para a JVM montar o arquivo). O cache depende do
   caminho da JRE, dos jars e das opções: refazer depois de trocar runtime/jars.

## Medição (cópia de teste, mesmo Mac)
- Abre na JDK 25 com a JRE embutida (`home=…/jre`), nenhuma JVM do Homebrew.
- Cache: 207 MB em `~/Library/Caches/Mac.apk/aot`; abertura **9–11 s → 7–8 s** (2 × 2). App instalado: gate 10/10 (6–15 s, maioria 6–9 s; antes 12–16 s).
- Memória/CPU nos Reels: medição em segundo plano inconclusiva (143–769 MB entre rodadas
  iguais; o vídeo nem sempre começou com a janela coberta). Cabeçalhos compactos
  (`-XX:+UseCompactObjectHeaders`) ficaram de fora até haver medição limpa (e exigiriam
  outro cache, porque as opções entram na chave).

## Consequências
- O bundle deixa de depender da JVM do Homebrew (passo do item 6, distribuição). Bibliotecas
  nativas do runtime (libvpx, capstone, libpng…) ainda vêm do Homebrew.
- +60 MB no bundle (JRE), +207 MB em `~/Library/Caches` (cache, regenerável).

> Treino parcial resolvido no ADR 0032.
