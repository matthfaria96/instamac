# ADR 0032 — Treino AOT: código traduzido verificável nos construtores do R8

**Status:** aceito em 2026-11-12 (patch `0040`); resolve o treino parcial do ADR 0019

## Contexto
No modo de gravação (`train-aot.sh`) a abertura parava em "Waiting on QPLInitializer" e o
processo saía em ~40 s com um cache só da inicialização (abertura ~11 s).

## O que estava errado (medido)
No treino, o HotSpot verifica as classes do app (fora dele, a verificação fica desligada).
O `X/03of.A01` fazia `new X/01aq` + `Object.<init>`: o R8 embute construtores triviais, o ART
aceita e a JVM não ("Call to wrong <init> method"). Isso derrubava o `QPLInitializer` e depois o
`AppInit4`, e o Instagram chamava `System.exit(10)`. O `InitRepointPlan` do upstream recusava esse
caso (o `01ap()` faz trabalho de verdade) e não via pares em que o `new` vem depois do `<init>`.

## Decisão
- Reaproveitar o repasse do R8 vira tentativa: se a cadeia acima estiver bloqueada, desfaz e
  sintetiza construtores com padding (`01aq(Void)` → `01ap(Void)` → `Object()`).
- Varredura do plano insensível à ordem dos blocos (proposta a mais é inofensiva; a inferência de
  tipos decide cada ponto).
- `hasHiddenRepoint` conta alocações por classe em vez de "aloca em algum lugar".

## Medição
O treino passa da janela e do feed; o cache vai de 199 para 325 MB; abertura de 6 s com ele
(8 s com disco frio). Gate no clone: 5/5.

## Pendente
Ainda sobra um ponto (`LongformDraftRepository.A02` @1007, `new X/0RBg` + `Object.<init>`) que a
inferência não reaponta. O treino termina por ele depois do feed, mas a abertura já está coberta.
