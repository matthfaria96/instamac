# ADR 0013 — Arquivos do Mac para o Instagram (menu Arquivo, arrastar) e menu Editar

**Status:** aceito em 2026-11-11 (patch `0019`); editor de foto resolvido no ADR 0014; story/reel abertos

## Contexto
Não havia como levar uma foto ou vídeo do Mac para o app: o Instagram só via a "galeria"
do Android, vazia. O app já declara atividades próprias de compartilhar (as que outro app
aciona pela folha de compartilhamento num aparelho).

## Decisão
1. **Menu Arquivo**: Nova Publicação… (⌘N) e Enviar por Mensagem… (⌘D). Story e Reel foram
   retirados no ADR 0015 (caem na página de câmera, em branco). Cada item abre o painel de arquivos do macOS (imagens e vídeos, vários).
2. **Arrastar para a janela**: Finder (URLs de arquivo) e Fotos (promessas de arquivo). Ao
   soltar, um menu no ponto da soltura pergunta o destino (os mesmos quatro).
3. **Entrega**: `ACTION_SEND` / `ACTION_SEND_MULTIPLE` para a atividade do destino, pelo
   caminho de chegada entre apps que o runtime já tinha, com URI `content://` do provedor
   de documentos do host e concessão de leitura. Tabela destino → atividade em
   `cocoa_bridge.mm` (`kShareTargets`).
4. **O app nunca lê o original**: cada arquivo é preparado antes em `$TMPDIR/macapk-share/`
   numa fila de fundo — clone APFS, ou JPEG sRGB quando a imagem é HEIC/TIFF/RAW. Lotes com
   mais de um dia são apagados no envio seguinte. Assim nenhuma thread do app toca
   `~/Documents`/`~/Desktop`/`~/Downloads` (pegadinha do diálogo do macOS).
5. `resolveContentProvider` passa a responder pela autoridade do provedor de documentos como
   num aparelho (outro pacote, outro uid). Sem isso o destino Mensagem recusava a URI
   (aviso e `finish()` no `onCreate`).
6. **Menu Editar** (Recortar, Copiar, Colar, Selecionar Tudo, Emojis e Símbolos), da rodada
   anterior, entra no mesmo patch.

## Medição
Com o verbo de teste `share <destino 0-3> <caminho>[|<caminho>]` no arquivo de
`MACAPK_DEBUG_HOSTKEY_FILE` (mesma função que o menu chama depois do painel):

| envio | resultado |
|---|---|
| 1 JPEG → Feed | editor abre com a foto importada; "Avançar" chega a "Novo post" |
| JPEG + HEIC → Feed | 2 de 2 preparados (HEIC virou `.jpg`), `SEND_MULTIPLE`, editor abre |
| 1 JPEG → Mensagem | lista de destinatários com "Enviar" |
| 1 JPEG → Story / Reel | o app aceita o intent e vai para a página de câmera, que fica **vazia** |

Boot depois das trocas: `boot-loop.sh 10 -` → 10/10.

## Defeito encontrado → resolvido no ADR 0014
A prévia do editor de foto saía preta: o Instagram renderiza num `ImageReader` e entrega os
quadros por `SurfaceControl.Transaction.setBuffer`. Implementado no patch `0020`. Story e
Reel caem na página de câmera, que aparece vazia (aberto, assunto de câmera).

## Não verificado por mim
- **Publicar de fato** (tocar em "Compartilhar"/"Enviar"): agiria na conta do dono. A imagem
  renderizada para o envio foi conferida no disco e está correta (ADR 0014).
- Painel de arquivos, arrasto real do Finder/Fotos e o menu que aparece ao soltar: precisam
  de mão humana (sem permissão de acessibilidade não há como dirigir). O que foi medido é o
  caminho do painel para dentro.
- Vídeos (`.mov`/`.mp4`) e itens do menu Editar em campos de texto.
