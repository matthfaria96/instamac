# ADR 0006 — Girar relança a atividade; a tela é da tela

**Status:** aceito e ligado por padrão em 2026-11-11 (patch `0015`)

## Contexto
View → Girar (Cmd+R) troca a janela entre 500×800 (telefone) e 1280×800 (tablet). O
Instagram só decide telefone × tablet no `onCreate` (`X.01rq.A0F`), então a troca "no
lugar" deixava a tela meio convertida, e depois de pedir PORTRAIT numa tela de telefone
ele não saía mais do retrato.

## Decisão
1. `MACAPK_ROTATE_RELAUNCH=1` (o launcher liga): o giro pedido pelo **usuário** relança as
   atividades vivas e descarta o pedido de orientação feito para a tela antiga.
2. Os campos de tela (`screenWidthDp`, `smallestScreenWidthDp`, orientação…) do
   `Resources` compartilhado pertencem à tela confirmada: se o app reaplica uma
   `Configuration` guardada de uma tela que já não existe, os campos de tela ficam.

## Medição
Sem (2), relançado em 1280×800 o app reaplicava a configuração do boot (500×800dp sw500):
layout de telefone esticado em 1280 px, e a volta via `diff=0x0` (não fazia nada). Com (2)
o log diz `app updateConfiguration replayed a past display (500x800dp sw500); kept
1280x800dp sw800 land`; retrato→paisagem sobe com trilho lateral e feed centralizado,
paisagem→retrato com barra de abas. Teste: `scripts/ui.sh start MACAPK_DEBUG_AUTOROTATE=30,60`
e capturas `build/shots/rot1-girou.png`, `rot2-voltou.png`.

## Consequências
O giro perde o estado da tela aberta (rolagem, tela empilhada), como girar um aparelho com
um app que não declara `orientation`. Redimensionar arrastando continua sem relançar.
