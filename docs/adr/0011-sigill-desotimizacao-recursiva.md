# ADR 0011 — O "SIGILL em código JIT": a guarda contava PC, não quadro

**Status:** corrigido em 2026-11-11 (patch `0017`)

## Sintoma
Intermitente: o app abria e morria poucos segundos depois (2 de 10 aberturas, 7–8 s depois
do foco), ou deixava um `.ips` de `SIGILL` ao encerrar (1–2 de cada 10 nos gates
anteriores, que por isso ainda contavam 10/10). O log terminava em
`[sigill-emu] un-emulated trap at PC=… insn=0xd4ade001 -- chain looping on same PC;
restoring default and re-raising`.

## Causa
`0xd4ade001` é o `NativeDeoptInstruction` do HotSpot: a JVM o grava no ponto de retorno de
um método que está sendo desotimizado, e o tratador dela atende o sinal e continua. O nosso
tratador (que vem antes, para emular leituras de registradores de ID) encadeia para o da
JVM e tinha uma guarda contra laço: três traps seguidos no mesmo PC, na mesma thread,
matam o processo. Só que **toda ativação** do método ainda na pilha retorna por aquele
mesmo PC — um método recursivo (a inflação de layouts é) gera um trap por nível, todos
legítimos. O terceiro era tomado por laço.

## Decisão
"Mesmo lugar" passa a ser mesmo PC **e mesmo SP**. Um tratador que retorna sem avançar
re-executa com todos os registradores iguais, então o laço de verdade continua detectado.

## Medição
Gate de 20 aberturas depois da correção (`build/boot/loop-20261111-151232/`): **20/20, nenhuma
morte**, nenhuma linha `chain looping` em nenhum log (antes: 2 mortes em 10, mais 1–2 no
encerramento). Sobra, em 1 log, um trap atendido normalmente pela JVM no início do boot
(`chaining to saved SIGILL handler … count=1`) — é o caminho esperado.
