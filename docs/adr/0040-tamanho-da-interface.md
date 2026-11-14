# ADR 0040 — Tamanho da Interface: mais pixels por dp em telas 1x

**Status:** aceito em 2026-11-14 (patch `0055`; launcher)

## Contexto
Depois do recorte suavizado e dos mipmaps (ADR 0039, adendo), o dono ainda via os ícones do feed
(coração, comentário, compartilhar, abas) "menos suaves que no celular". Medido com ampliação
sem interpolação e um registro temporário de cada `drawPath` pequeno (removido): os ícones vetoriais do Instagram já são desenhados
com suavização (`drawPath`, aa ligado). O limite é a densidade: nas duas telas desta máquina
(1x), um ícone de 24 dp tem 24 px e traços de 2 px; no celular (~2,6x) o mesmo ícone tem ~63 px.
Desenhar maior e reduzir (supersampling) mudava o tamanho da janela e o layout: revertido.

## Decisão
Visualizar > **Tamanho da Interface**: Automático / 100% / 125% / 150%, gravado em
`Contents/android/.macapk/ui_scale`. O launcher define `MACAPK_DISPLAY_DENSITY = 160 × escala
da tela × tamanho` e multiplica os tamanhos das janelas (celular 412×915, tablet 1280×800, e o
`WINDOW_BUDGET`) pelo mesmo fator: o Instagram continua vendo 412 dp de celular, com mais pixels.
A densidade é fixa por processo (como no Android): trocar reabre o app.

**Automático (padrão, sem arquivo ou `auto`):** a maior escala em que a janela de celular, com a
barra de título e 16 pt de folga, cabe na área útil da tela principal; se o tablet a 100% cabe na
tela, ele também tem de caber na escala escolhida. Nesta máquina: 2560×1440 → 125%
(150% daria 1405 pt de altura); um MacBook Retina comum fica em 100%.

## Medição
- 125%: `display density: 200 dpi`, janela 515×1144; barra de abas embaixo (layout de celular);
  toque na Busca abre a Busca (coordenadas de superfície escalam junto: y = 1114 em vez de 891).
- `100` gravado: 160 dpi, 412×915, como antes.
- Ícones e texto visivelmente mais lisos (o dono: "bonito e bem de alta qualidade").

## Consequências
- Janela maior na tela; quem quiser a antiga escolhe 100%.
- Testes com `ui.sh tap` usam coordenadas de superfície: na escala 125% elas crescem 1,25×.
- O item do menu não foi clicado à mão (o injetor não alcança a barra de menus).
