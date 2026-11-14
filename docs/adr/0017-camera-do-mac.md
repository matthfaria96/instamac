# ADR 0017 — Página de câmera do Instagram com a câmera do Mac

**Status:** aceito em 2026-11-12 (patch `0023`); disparo de foto e grade da galeria abertos

## Contexto
Pedido do dono: "a tela que envolve câmera tem que usar a nossa do Mac". A página de
câmera do Instagram (Story, Post, Reel; `QuickCaptureFragment`) ficava em branco.

## O que estava errado (medido, em ordem)
1. **Margens da janela nunca assentavam.** `requestApplyInsets()` marcava só a view que
   pediu; o runtime despacha a partir da raiz. Corrigido: sobe até a raiz e agenda quadro.
2. **`ServiceManager.getService("window")` devolvia nulo.** O `WindowInsetsManager` do
   Instagram converte isso em `IBinder` não nulo → NPE no ouvinte de margens → alturas das
   barras ficavam -1 e **35 tarefas pendentes** (a página de câmera entre elas) nunca rodavam.
   Agora há um `Binder` inerte para "window" (diagnóstico com `MACAPK_DUMP_FRAGMENTS=1`: o
   fragmento estava RESUMED com view; quem segurava era essa fila).
3. **Câmera sem JPEG.** O Optic exige tamanhos JPEG ("Invalid picture size: 'null'").
   JPEG passou a ser anunciado; captura avulsa para um `ImageReader` JPEG recebe o quadro
   codificado.
4. **Taxa de quadros de webcam UVC** (C922) fora da lista → `NSException` dentro de JNI →
   SIGABRT. Agora usa a duração da faixa listada; `@try` como rede.
5. **Textura externa** (`samplerExternalOES`) inexistente no ANGLE-Metal: a ponte GLES compila
   o shader como `sampler2D` e mapeia `GL_TEXTURE_EXTERNAL_OES` → `GL_TEXTURE_2D`.

## Medição (Instagram 455, Logitech C922)
- Página de câmera monta; **prévia ao vivo e na orientação certa** em Story e Post
  (`build/shots/camera-3.png`, `foto-tirada.png`).
- Menu Arquivo volta a ter Novo Story… e Novo Reel…; foto do Mac para o Story abre o editor
  de Story com a imagem.
- Galeria: o launcher concede as permissões de mídia (`MACAPK_MEDIA_PERMS_ASK=0`); o
  MediaStore lista 1187 itens de Imagens/Filmes.
- Boot depois de todas as trocas: `boot-loop.sh 10 -` → 10/10, com a janela atrás e sem
  tomar o foco (nenhuma das aberturas medidas ativou o app).
- Custo: a thread `Lite-SurfacePipe-Thread` (pipeline GL da câmera) ~14% de um núcleo com a
  prévia aberta.

## Aberto
- **Disparador não reage ao toque injetado** (nem a toque longo). O `ShutterButton` só aceita
  toque quando o controlador o marca pronto (`0HOQ.A09`); não verificado se é o estado ou o
  injetor. Teclas Enter/Espaço também disparam no código do Instagram — testar à mão.
- **Grade da galeria da página de câmera com células vazias**: o carregador interno nunca
  pede a miniatura (`drawable=null`, nenhum `loadThumbnail`). A prévia grande carrega.
- Editor de Story com a foto do Mac mostra um indicador de carregamento por cima.
- "+" do feed segue abrindo o painel do Mac em Imagens (ADR 0015), como pedido.
