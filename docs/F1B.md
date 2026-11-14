# F1b — os métodos que ainda estubam (medidos)

Depois do `SwitchTableEmitter` o Instagram abre na tela de login, mas três métodos
gigantes ainda não convertem e saem como stub que lança. Este documento registra a forma
de cada um, medida com `DEX2JVM_SPLIT_DUMP_BIG=1`, e o que cada um exige.

## 1. `X/09IF.A0p(LX/013g;)LX/06Vi;` — 68.700 bytes

```
9867 insns, 492 try block(s), 805 locais
[dex-split] refused A0p: no valid cut within 62251 bytes of index 26
```

492 blocos `try`, com faixas curtas (por exemplo `[60,63)`, `[63,82)`, `[82,110)`…)
cobrindo praticamente todo o corpo, e um handler catch-all compartilhado. Nenhum corte é
legal porque toda faixa cruza quase todo ponto possível, e os handlers não são clonáveis
(o dump mostra 0 ou 1 clonável por tentativa).

**O que exige**: dividir *junto* com a tabela de exceções — cada parte precisa de uma cópia
das faixas que a cobrem e do handler correspondente, ou de um driver que capture e
redespache. É a parte mais delicada do F1b.

## 2. `X/0bRx.getValues()[I` — 73.744 bytes

```
11265 insns, 2 try block(s), 19 locais
try [13, 29037)  catches: <all>@0x7174
handler 0x7174: move-exception; monitor-exit; throw
[dex-split] refused getValues: no valid cut within 65395 bytes of index 2
```

O handler é `move-exception; monitor-exit; throw`: o corpo inteiro está dentro de um bloco
`synchronized`. O divisor recusa por causa da regra 5 (monitor-enter e monitor-exit têm de
ficar no mesmo método, JVMS 2.11.10) — e recusa certo: um `return` de uma parte com o
monitor na mão deixa o lock preso.

**O que exige**: manter o driver dono do monitor e chamar as partes de dentro dele, com o
`try/finally` do `monitorexit` no driver. É viável, mas é uma transformação própria, não
um corte.

## 3. `X/…invoke` — 168.419 bytes

```
12527 insns, 0 try block(s), 948 locais
fam=1 (move) 71173 B (42.3%) · fam=32 (invoke-direct) 37125 B (22.0%)
fam=2 (move-wide) 25640 B (15.2%) · fam=16 (filled-new-array) 8574 B
```

968 locais e um corpo dominado por `move`/`move-wide` e chamadas directas — o formato de
um inicializador gerado. Aqui o frame no heap **ajuda de verdade**: 948 slots viram
posições de um array e o custo de prólogo por parte deixa de ser 4 bytes por slot.

## Decisão de implementação (rodada de 11/nov)

Para `X/0bRx.getValues()` o caminho é **içar o monitor**, não cortar dentro dele:

- o corpo inteiro está num único `synchronized` (enter no topo, exit antes dos `return`,
  mais um exit no handler catch-all). A janela de monitor cobre o método todo, então
  nenhum corte é legal — e cortar assim mesmo produziria parte que tranca sem destrancar;
- o caminho correto é marcar o método original com `ACC_SYNCHRONIZED`, **remover** os
  `monitor-enter`/`monitor-exit` e o handler do fluxo, e deixar a cadeia normal dividir o
  corpo. Enquanto o driver (o método agora sincronizado por flag) chama as partes, a
  thread já é dona do monitor, então as partes não precisam de instrução de monitor
  nenhuma, e todo `return` do driver libera o lock — inclusive nos caminhos de exceção.

Para `X/09IF.A0p` (492 `try` com handler catch-all compartilhado) o caminho é o mesmo
princípio, um nível acima: replicar a tabela de exceções por parte e clonar o handler por
faixa (o mecanismo `cloneableHandlers` já existe, mas hoje recusa trechos longos).

### Medição da rodada de 11/nov — o teto real é a ARESTA DE RETORNO

Implementados o içar de monitor e a clonagem do handler do `synchronized`, o divisor parou
de recusar por monitor e por handler, e o dump passou a mostrar o que sobra:

```
[split-dump] recusas: backEdge=1158 uninitThis=0 unreachable=0 noBytecode=0
                      stack=1150 deferredNew=702 trySpan=6829
```

Ou seja: com monitor içado e handler clonado, `getValues` ainda não corta porque o corpo
tem **laços** — 1.158 pontos candidatos recusados por aresta de retorno (e 1.150 por pilha
não vazia no corte, 702 por `new` pendente). O divisor é só-para-frente por construção:
cortar um laço exige devolver controle ao chamador, o que é a máquina de estados com frame
(o F1b de verdade), não uma exceção pontual.

Consequência para o plano: o içar de monitor e a clonagem ficam no lugar (são pré-requisitos
e estão dormentes — nenhum método atual se beneficia), mas o trabalho que destrava
`getValues` é **frame no heap + transição entre partes**, o mesmo que destrava o `invoke`
de 948 locais.

**Correção da medição anterior sobre o `A0p`**: ele também tem laço. O mesmo dump, agora
lido no método certo, dá para `A0p`:

```
[try-probe] A0p tries=492 B0[60,63) h=21410 blk: 0x0d 0x08 0x6e 0x27 …
[dex-split] 94 uninitialized-ref window(s) are cut-forbidden, widest 90 of 9867 instructions
[split-dump] recusas: backEdge=1158 stack=1150 deferredNew=702 trySpan=6829
```

1.158 recusas por aresta de retorno, 1.150 por pilha não vazia, 702 por `new` pendente —
os mesmos números que eu tinha atribuído ao `getValues`. Ou seja: **os dois stubs restantes
exigem a máquina de estados**, e o `A0p` ainda tem 492 faixas de exceção por cima. A tabela
replicada sozinha não destrava nada; ela é condição necessária junto com o frame.

### Medição da rodada de 11/nov (hoist implementado)

O içar de monitor está implementado no overlay: `MethodSplitter` reconhece a forma
(um único `monitor-enter` cujo registro é `this`, inclusive via cadeia de
`move-object`, com prolepse só de leitura), marca o plano, e `Translator.runSplit`
troca cada `monitor-enter`/`monitor-exit` por um `POP` (o empurrão do operando
permanece, então o frame não muda) e liga `ACC_SYNCHRONIZED` no método original.

Medido na conversão do Instagram 455: o içar **dispara** —

```
[dex-split] monitor hoisted to ACC_SYNCHRONIZED (lock is this; 11265 instructions)
```

— e `getValues` **continua estubado**, por outra parede:

```
[dex-split] refused getValues: no valid cut within 65395 bytes of index 3
```

O corpo inteiro está dentro de um `try` com handler catch-all, e a regra 2 recusa
qualquer corte que cruze a faixa; a clonagem (`cloneableHandlers`) recusa esse handler
porque ele contém um `monitor-exit`. Ou seja: `getValues` precisa das **duas** coisas —
monitor içado e handler clonável — e é o mesmo machado que destrava o `A0p`
(492 `try`, handler compartilhado). O próximo passo é `cloneSafe` aceitar o handler
`move-exception; monitor-exit; throw` quando o plano é hoisted (o `monitor-exit` vira
`POP`, então o clone é um rethrow puro).

## O que isso muda no plano

O `SwitchTableEmitter` resolveu o caso "dispatcher com milhares de destinos" sem frame.
Os três restantes não têm esse formato, e cada um pede uma capacidade diferente:

| Método | Capacidade necessária | Complexidade |
|---|---|---|
| `A0p` | corte com tabela de exceções replicada | alta |
| `getValues` | driver dono do monitor + partes chamadas de dentro | média |
| `invoke` | frame no heap para 948 locais | média-alta |

Nenhum deles bloqueou o boot até a tela de login. A ordem de ataque, se algum recurso
falhar em uso, é `getValues` (mais simples e provavelmente array de configuração) →
`invoke` → `A0p`.

## Estado do objetivo

O que está provado: Instagram abre, renderiza e chega ao login, com `Instamac.app` único,
runtime embutido e o app **já instalado dentro do bundle** (`scripts/preseed.sh`): a
primeira abertura é um boot quente, sem seletor de APK e sem conversão na máquina de quem
usa. O que falta para fechar: **login real** (depende do usuário) e os três métodos acima,
que só se manifestam se algum recurso os chamar.
