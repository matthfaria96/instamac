# ADR 0026 — Tradutor: valores estáticos que o ConstantValue não carrega

## Contexto
Log de toda abertura: `NullPointerException: Cannot invoke "Class.getSimpleName()"` em
`X.01Az.A0A` (o `BLog` do Instagram), vindo de
`RealtimeClientManager$mqttChannelStateListener$1.onChannelStateChanged` — o cliente de tempo
real (MQTT) do Direct. O `TAG` (`static final Class`) chegava nulo: no bytecode traduzido o
`<clinit>` nunca o atribuía.

No DEX, os `static_values` da classe são gravados pela VM **antes** do `<clinit>`, e o R8 não
deixa a atribuição no `<clinit>`. O `DexConverter` só transformava em `ConstantValue` os
primitivos e `String` em campo `String` — e supunha que o `<clinit>` cuidaria do resto. Todo
valor estático de outro tipo (literal de classe, string em campo não-`String`, constante de
enum, `MethodType`/`MethodHandle`) ficava nulo, em qualquer classe.

## Decisão
O conversor junta esses valores por classe; o `Translator.emitPrologue` os grava (`ldc` /
`getstatic` + `putstatic`) no início do `<clinit>` traduzido — dentro do `<clinit>`, onde a JVM
aceita escrita em `static final`. Classe sem `<clinit>` ganha um. Patch 0033.

## Medição (clone)
- `RealtimeClientManager.<clinit>` começa com `putstatic TAG`.
- Abertura: 0 exceções `getSimpleName`, 0 "exception dispatching message" (antes 3 por
  abertura); o canal registra `CONNECTING → CONNECTED → CONNECTED_AND_ACKED`.
- Reconversão do APK: 228.034 classes em 63 s.

## Consequências
- O ouvinte do canal agora termina o trabalho dele (antes morria no log, antes de reassinar
  tópicos): mensagens, digitação e presença ao vivo no Direct devem melhorar — a validar à mão.
- Qualquer outro caminho do app que dependia de um desses campos também passa a funcionar.
