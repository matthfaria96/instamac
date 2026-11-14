# ADR 0028 — Galeria vazia: a varredura de mídia travava numa pasta protegida

## Contexto
"Novo post" (e a grade da página de câmera) mostravam só a célula da câmera. Rastreio
(`DEX2JVM_TRACE_ENTRY`) da galeria do Instagram: `X.0Hv2.A03` só consulta as fotos depois de
`A04`, que testa a coluna `is_favorite` em `content://media/external/file`. Essa consulta
nunca voltava: o `sync` do `MediaStoreProvider` varre `sdcard/Movies` (link para `~/Movies`),
e `opendir("~/Movies/TV")` — a biblioteca do app TV, protegida pelo macOS — fica esperando
indefinidamente (medido também fora do app: `ls ~/Movies/TV` não responde). Sem resposta, o
Instagram conclui que o MediaStore não serve e não lista nada.

## Decisão
- A varredura pula as bibliotecas de mídia protegidas conhecidas (`~/Movies/TV`,
  `~/Music/Music`, `~/Music/iTunes`).
- Toda pasta do Mac é listada com prazo (`MACAPK_MEDIA_LIST_TIMEOUT_MS`, 1500 ms) numa thread
  à parte; se não responder, é pulada pelo resto da sessão (com linha no log).
- Diagnóstico no `ContentResolver`: consulta sem provider e exceção de provider são
  registradas (uma vez por autoridade/tipo), em vez de sumirem no app. `MACAPK_THUMB_TRACE=1`
  registra miniaturas geradas (tamanho, pixel central, tempo).
Patch 0035.

## Medição (clone)
`scan: skipping …/Movies/TV`; a consulta de teste responde (1200 itens) e a galeria consulta
**1187 fotos e vídeos**; a prévia da foto mais recente aparece. Miniaturas: geradas em 1–65 ms.

## Pendente
As células da grade às vezes ficam no fundo cinza: as miniaturas são geradas, mas o
`BitmapDrawable` da célula não é desenhado. Intermitente (com e sem o cache de desenho); falta
achar o que segura a célula (provável animação de entrada).

> Células cinza resolvidas no ADR 0031.
