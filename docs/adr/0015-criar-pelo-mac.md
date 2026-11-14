# ADR 0015 — Criar pelo Mac: o "+" abre Imagens, colar na legenda, módulos baixados

**Status:** aceito em 2026-11-11 (patches `0019` regenerado e `0021`)

## Contexto
Pedido do dono: postar não pode abrir a tela "do Android" vazia; deve abrir uma pasta do
Mac (Imagens), e tem de dar para colar texto na legenda. Medido: o "+" do feed (e os
destinos Story/Reel) levam à página de câmera do Instagram (`QuickCaptureFragment`), que
neste runtime fica **em branco** — o fragmento existe, mas o contêiner
`quick_capture_fragment_container` nunca recebe conteúdo. Causa não encontrada.

## Decisão
1. **"+" do feed → painel de arquivos do Mac**, aberto em Imagens, com destino Feed (segue
   para o editor de foto do ADR 0014). Mecanismo genérico no runtime:
   `MACAPK_HOST_CLICK="id/<nome>=<destino>"` intercepta o clique na view com esse nome de
   recurso; o launcher define `id/action_bar_left_button=0` (só `MainFeedActionBar` usa
   esse id). O "+" do perfil (`profile_header_create_button`) **não** foi desviado.
2. **Arquivo e o menu de soltar oferecem só o que funciona**: Feed e Mensagem. Story e Reel
   voltam quando a página de câmera funcionar.
3. **Painel em português**: `CFBundleLocalizations` no plist embutido do runtime e no
   `Info.plist` do bundle (sem isso o painel do sistema sai em inglês).
4. **Galeria**: o launcher liga `sdcard/Pictures` e `sdcard/Movies` a `~/Pictures` e
   `~/Movies` (links absolutos que o MediaStore do runtime reconhece). Documentos e
   Downloads ficam de fora (diálogo do macOS). Consequência: "salvar" do Instagram cai em
   `~/Pictures/Instagram`.
5. **Colar**: funciona pelo menu Editar/⌘V (Ctrl+V para o Android + ponte de área de
   transferência). O aviso "colou da área de transferência" do Android 12 foi desligado
   (`MACAPK_CLIPBOARD_ACCESS_NOTICE=0`): saía em inglês e com o rótulo "Instagram".
6. **Módulos baixados** (defeito achado no caminho, patch `0021`): o shim devolvia
   permissão de escrita a todo arquivo dos dados a cada abertura; o Instagram exige módulo
   baixado somente-leitura e recusava todos ("Downloaded module file must be read only").
   Agora só é reparado arquivo que o dono não consegue **ler**.

## Medição
- Toque no "+": o feed continua na tela (quadro `RICH`), abre o painel "Abrir" em
  `Pictures` com a mensagem "Publicar no Feed" (`build/shots/painel.png`).
- ⌘V com 37 caracteres numa área de transferência de teste
  (`MACAPK_CLIPBOARD_TEST_PASTEBOARD`): a legenda de "Novo post" passou de 3 para 40
  caracteres. No harness é preciso `activate` antes (o Android só deixa ler a área de
  transferência com a janela em foco).
- Módulos: 0 erros de "read only" (antes: todos, toda abertura); `executorch` carrega;
  os `download.zip` continuam `0444` depois de reabrir.
- Boot depois de todas as trocas (shim, runtime, launcher, jars): `boot-loop.sh 10 -` → 10/10.

## Não verificado / aberto
- **Página de câmera em branco** (Story, Reel, "+" do perfil → Post): causa desconhecida.
  Não é falta de módulo (verificado depois da correção do item 6).
- A galeria mapeada não foi vista numa grade do Instagram (a única grade conhecida fica na
  página em branco); os links existem e o MediaStore do runtime os segue.
- Escolher o arquivo no painel e clicar "Enviar": é mão humana. O caminho do painel para
  dentro foi medido pelo harness (ADR 0013).
- Modo tablet: o "+" fica no trilho lateral, com outro id; não desviado.
