# ADR 0002 — Modo de resolução fixa (P1)

**Status:** substituído pelo ADR 0010 em 2026-11-11 (o dono decidiu: dois modos redimensionáveis com tamanho padrão; a trava virou opção do menu, desligada por padrão)

Pedido do dono: presets fixos, sem redimensionar, sem tela cheia, menu "travar resolução"
sempre ativo com opção de destravar (desaconselhada).

Estado: implementado em `cocoa_bridge.mm` — presets **widescreen 1280×800** e **retrato
832×1280**, menu `View → Resolução fixa`, sem alça/botão verde/`FullScreenPrimary` quando
travado, preferência em `<root>/.macapk/resolution`. Ligado por `MACAPK_RESOLUTION_UI=1`.

**Medido em 2026-11-11 (depois da correção do P0):** com o lock ligado, **10/10 aberturas
logadas** no feed (`build/boot/p1-lock/summary.txt`) — o "lock derruba o boot" era a mesma
correlação do P0. O botão verde some. **Mas a janela fica 500×800**, não 1280×800: a
preferência de orientação `pref=portrait (file)` (gravada por `set-orientation.sh
portrait`, em `.macapk/window_pref/`) faz a política reformatar a janela **depois** do lock
(`reshaping placeholder 1280x800 -> 500x800`).

Decisões do dono antes de ligar por padrão:
1. o lock manda na orientação (widescreen ignora `pref=portrait`) ou segue a preferência?
2. tamanho do retrato: 832×1280 **não cabe** nesta tela (área visível 1284 pt menos a barra
   de título); caber exige ~780×1250 ou escalar.

Implementação recomendada: o preset do lock vira a entrada da política de janela
(orçamento + orientação) em vez de um resize posterior; aí `MACAPK_RESOLUTION_UI=1` entra
como padrão no launcher. Critério: 10/10 com lock e janela 1280×800 sem alça
(`tools/winid.swift` + `screencapture -l<id>`).
