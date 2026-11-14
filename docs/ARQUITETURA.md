# Arquitetura: onde o Instagram quebra e o que o Instamac muda

Mapa técnico do caminho entre um `.apk` do Instagram e uma janela no macOS, com os
pontos exatos do código do Mac.apk (commit `57c9912`) que decidem o destino do app.

## 1. O caminho de um APK até a tela

```
base.apk
  │
  ├─ ① extração           runtime/src/apk_unpacker.cpp
  │     lê o APK, resolve splits, unpacka libs nativas
  │
  ├─ ② tradução dex→JVM   runtime/java/com/macapk/dex/*.java
  │     Main → DexConverter → Translator → CodeWriter   (gera .class)
  │     resultado: <app>/Contents/android/.macapk/code/<pkg>_<ver>/*.jar
  │
  ├─ ③ tradução ARM32→arm64   runtime/translator/ + bin/macapk-translator
  │     .so do app → dylib nativo (libstartup.so, libheramerged.so, …)
  │
  └─ ④ execução           runtime/src/main.cpp + android-framework.jar
        JVM HotSpot 21 embutido, framework Android reimplementado,
        desenho via Skia/Metal, EGL via ANGLE/MoltenVK
```

Cada etapa é independente e tem seu próprio jeito de falhar. O Instagram 455 passa em
①, ③ e ④ — e quebra em ②.

## 2. O limite do formato de classe Java

Um `Code` de método no classfile guarda `code_length` num `u4`, mas o JVMS 4.9.1
restringe o atributo Code a **65535 bytes**. Dalvik não tem esse limite: um
`code_item` pode ser tão grande quanto o APK quiser.

O tradutor do Mac.apk mede e reage em três degraus
(`runtime/java/com/macapk/dex/DexConverter.java:540-601`):

| Degrau | Transformação | Onde |
|---|---|---|
| 1º | `MethodOutliner` — hoista uma região reta longa para um helper `void` | `MethodOutliner.java` |
| 2º | `MethodSplitter` — corta em cadeia de métodos sintéticos | `MethodSplitter.java` |
| 3º | **stub que lança** — o método vira `throw new UnsupportedOperationException(...)` | `DexConverter.java:590` |

O comentário do próprio autor no 3º degrau diz o que acontece: *"the CLASS is kept, this
one method throws if called"*. É exatamente o que o Instagram encontrou.

## 3. O que o MethodSplitter sabe fazer (e por que negou o Instagram)

O splitter corta o método em partes encadeadas **só para frente**, cada parte entrando
por um `switch(entry)`. As seis condições de legalidade estão documentadas no cabeçalho
(`MethodSplitter.java:54-78`) e implementadas em `validCut`
(`MethodSplitter.java:1335-1348`):

1. nenhuma aresta de retorno cruza o corte (`sufMin[p] < p` recusa);
2. nenhum `try`/handler cruza o corte;
3. a pilha de operandos está vazia no corte;
4. todo registrador definido na entrada tem descritor de parâmetro;
5. monitores (`monitor-enter`/`exit`) ficam juntos;
6. `this` já está inicializado.

Quando a condição 2 é o problema, existe um replano que **clona o handler em cada parte**
(`cloneableHandlers`, `MethodSplitter.java:1224-1294`), ligado por
`DEX2JVM_SPLIT_CLONE_HANDLERS`. Um handler só é clonável se: começa com
`move-exception`, é reta de até `MAX_CLONE_INSNS` instruções terminando em `throw`/`return`,
ninguém cai/salta nele, não está dentro de outro `try` nem de janela `uninitialized`, e só
usa famílias "seguras" (`cloneSafe`, `:1298`).

### Medição no Instagram 455.0.0.51.72

Rodando o tradutor direto sobre o `base.apk`, com `DEX2JVM_SPLIT_DEBUG=1`:

```
[dex-split] A00: 2 parts of 77269 bytes; [0 0e/0p] [15c3 6211e/0p]
[dex-split] target 40000 -> 83346 bytes, retrying
[dex-split] refused A00: no valid cut within 25161 bytes of index 0
[dex-split] A00: replanning with terminal handlers cloned per part
[dex-split] refused A00: no handler can be cloned
[dex-split] refused _clinit_: part 1 needs 1016 argument slots
[dex-split] refused _clinit_: part 1 needs 816 argument slots
```

Com a instrumentação do Instamac (`DEX2JVM_SPLIT_DUMP=A00`) a geometria do método ficou
visível:

```
[split-dump] A00: 15477 insns, 0 try block(s), 0 cloneable handler(s)
```

Leitura corrigida — a primeira hipótese (try cobrindo o corpo) estava **errada**:

- `A00` tem 15.477 instruções e **nenhum `try` block**. Logo o replano com clonagem de
  handler não tinha o que clonar (`no handler can be cloned` é consequência, não causa).
- Com zero `try`, a única condição de `validCut` capaz de vetar 25.161 bytes inteiros é a
  **(1) aresta de retorno**: `sufMin[p] < p`. Isso significa um laço que volta para um
  índice anterior a `p` ao longo de todo esse trecho — ou seja, o corpo do método é
  essencialmente **um laço gigante** (padrão de interpretador/decodificador ofuscado da
  Meta).
- A cadeia do divisor é, por construção, **só para frente** (`MethodSplitter.java:54-58`):
  uma aresta de retorno atravessando o corte exigiria chamar de volta o chamador, o que
  recursa sem limite dentro do laço. Por isso o divisor recusa — corretamente.
- `<clinit>` da mesma classe **se salvou sozinho** na escada de retry, com spill para
  campos estáticos:

```
[dex-split] _clinit_: part 1 needs 1016 argument slots; spilled 1015 values to static fields
[dex-split] _clinit_: 2 parts of 84091 bytes; [0 0e/0p] [3915 1e/1015p spilled]
```

  As recusas de 1.016/816/… slots no log são tentativas intermediárias da escada, não o
  veredito. **O único bloqueio real da classe é o `A00`.**

### O que isso implica para a correção

Medição posterior (relatório em [contrib/upstream/README.md](../contrib/upstream/README.md)) refinou o quadro: o `A00` **não tem
laço nenhum** — é uma tabela de 7.738 strings (`switch` gigante, cada caso
`const-string; return-object`). O que estoura é o custo por parte: a parte que herda os
destinos do `switch` recebe 6.211 entry stubs e sai com 83.346 bytes.

A correção é **distribuir o dispatcher**: particionar os casos em faixas, cada parte com
o seu próprio `switch` restrito à faixa. A transformação de frame no heap continua
necessária para métodos com laço de verdade (o `X/9Pu.A09` do upstream), mas não é o que
bloqueia o Instagram hoje.

## 4. Depois de destravar o splitter

Ordem provável de paredes, todas já visíveis no log do teste:

| # | Sintoma no log | Camada | Comentário |
|---|---|---|---|
| 1 | `X/0000.A00 needs code_length 77269` | ② tradutor | objeto deste repositório; bloqueia tudo |
| 2 | `_clinit_ ... 1016 argument slots` | ② tradutor | spill de `<clinit>` não cobre; bloqueia estado estático |
| 3 | `findClass(com.pairip.VMRunner) -> ClassNotFound` | ②+④ pairip | proteção da Meta; pode ser fatal mais adiante |
| 4 | layouts em `layouts.bin.spo` (issue #103 upstream) | ④ resources | corrigido a partir do 1.0.2377; validar na 455 |
| 5 | `video choppy and sound inop` (COMPATIBILITY.md, 445) | ④ mídia | decodificação de vídeo/áudio |
| 6 | câmera | ④ | acesso à câmera do Mac pelo framework |

Nenhum desses é "bypass de detecção". São lacunas de implementação do runtime. O único
item que a Meta trata como integridade é o pairip (3), e mesmo ele é uma proteção de
empacotamento, não um atestado de dispositivo.

## 5. Onde o Instamac entra sem forkar o runtime inteiro

O tradutor Java mora num jar de recursos do runtime instalado:

```
~/Library/Application Support/Mac.apk/runtime/lib/macapk-loader.jar   ← com.macapk.dex.*
~/Library/Application Support/Mac.apk/runtime/lib/android-framework.jar
```

O ciclo de desenvolvimento do tradutor: `scripts/build-dexconv.sh` compila `com.macapk.dex.*`
do vendor com nossos patches, `scripts/convert-apk.sh` reconverte o APK e o `classes.jar` novo
substitui o do app instalado (receita no `CLAUDE.md`).

Para distribuir, o Instamac empacota o runtime oficial + o jar corrigido (AGPL: fonte
publicada neste repositório) e assina o conjunto. Se um dia o patch for aceito upstream,
o Instamac vira só um instalador do Mac.apk com o Instagram pré-configurado.
