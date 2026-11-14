# ADR 0010 — Dois modos de janela e a barra de menus

**Status:** aceito em 2026-11-11 (substitui o ADR 0002; patches `0015`, `0016`)

## Decisão do dono
A janela tem dois modos, trocados pelo menu do macOS:

- **Celular — em pé** (⌘1): abre em 412×915 (um telefone) e mantém o layout de telefone
  por mais que seja redimensionada.
- **Tablet — deitado** (⌘2): abre em 1280×800 com o layout deitado (trilho lateral).

Os dois são redimensionáveis ("responsivos"), mas abrem em medida de aparelho. Nada fica
travado por padrão; tela cheia continua desligada.

## Como
- O launcher define `MACAPK_WINDOW_SIZE_PORTRAIT=412x915`, `MACAPK_WINDOW_SIZE_DEFAULT=1280x800`,
  `MACAPK_RESOLUTION_UI=1`, `MACAPK_MENU_CONTROLS=0`.
- O tamanho do modo entra como o redimensionamento que um gerenciador de janelas faz
  (`ApplyUserResize`), encadeado na mesma transição que escolheu o modo (boot, ⌘R, menu):
  o app recebe uma `Configuration` só. Sem isso a caixa retrato da política é a tela
  virada de lado (500×800).
- Limites de redimensionamento: celular com largura entre 320 e 599 pt (o Instagram vira
  tablet aos 600 dp); tablet no mínimo 720×480. O lado (mais alto que largo, ou o inverso)
  já era mantido pela política.
- Menus: **Instamac** (Sobre, Proxy de Rede, Ocultar, Ocultar Outros, Mostrar Todos,
  Encerrar) · **Visualizar** (Celular, Tablet, Girar ⌘R, Tamanho Padrão ⌘0, Travar Tamanho
  da Janela) · **Rolagem** (Velocidade 0,5×–2×; Inércia ao Soltar: do Instagram / do macOS;
  Rolagem Automática: desligada / a cada 3–30 s) · **Navegar** (Voltar ⌘[) · **Idioma** ·
  **Janela** (Minimizar, Zoom, Trazer Todas para a Frente).
- **Instamac → Limpar Cache…**: mostra quanto o cache ocupa e apaga o conteúdo de `cache/` e
  `code_cache/` (o que "Limpar cache" faz no Android). Conta, mensagens e ajustes não são
  tocados; o app continua aberto. Medido: 3.781 arquivos, 298 MB → 2 MB.
- Velocidade e inércia ficam nas preferências do usuário (`ScrollSpeed`,
  `ScrollHostInertia`); a rolagem automática vale só para a sessão.

## Medição
Abre em 412×947 (conteúdo 412×915), ⌘R → 1280×832 → 412×947, cada troca com um único
relançamento; `MACAPK_MENU_DUMP=1` imprime a barra (conferida). Rolagem automática a cada
12 s na aba Reels: 3 vídeos em 3 passos. Achado: soltando o dedo **parado**, um arrasto de
62% da tela voltava ao mesmo Reel (3/3); o gesto agora solta ainda em movimento (~600 pt/s).

## Não verificado por mim
- Arrastar a borda da janela com o mouse (os limites são `contentMinSize`/`contentMaxSize`
  do AppKit; não há como arrastar sem permissão de acessibilidade).
- "Inércia do macOS": precisa de eventos de inércia reais do trackpad; o injetor não os gera.
  Risco conhecido: um arremesso para baixo no topo do feed pode disparar o
  puxar-para-atualizar, e nos Reels pode avançar mais de um vídeo.
- Menus Editar e Arquivo vieram depois: ADR 0013.
