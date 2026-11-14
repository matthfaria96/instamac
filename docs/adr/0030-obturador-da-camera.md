# ADR 0030 — Obturador da câmera: metadados de zoom e estado 3A

**Status:** aceito em 2026-11-12 (patch `0037`)

## Contexto
A página de câmera do Instagram (ADR 0017) registrava o toque no obturador e não tirava a foto.

## O que estava errado (medido)
Rastreio (`DEX2JVM_TRACE_ENTRY`) do botão (`ShutterButton`, `X.0HOQ`): o toque passa e a captura
roda, mas a tarefa do Optic morre com `IndexOutOfBoundsException` em `X.064Z.A00`, um `get(0)`
na lista de razões de zoom, que estava vazia. Nossa câmera não anunciava
`SCALER_AVAILABLE_MAX_DIGITAL_ZOOM`, chave que o camera2 exige de todo aparelho, e o Optic a tratou
como câmera sem metadados de zoom.

## Decisão
- Características: zoom máximo 1,0, `CONTROL_ZOOM_RATIO_RANGE` [1,0, 1,0] e recorte `CENTER_ONLY`.
  É o que o shim legado do AOSP anuncia para uma câmera sem zoom.
- Resultados: estado 3A como no `LegacyResultMapper` (AE CONVERGED, ou PRECAPTURE no quadro do
  gatilho; AF INACTIVE; AWB CONVERGED; flash UNAVAILABLE; lente STATIONARY), modos e gatilhos ecoados.

## Medição (Logitech C922)
Toque no obturador: JPEG 1920×1080, e o editor de Story abre com a foto (descartado sem publicar).

## Consequências
- O toque injetado (`ui.sh tap`) atravessa diálogos e cai na janela da atividade; num diálogo use
  `ui.sh raw "hosttap fx fy"` (exige `MACAPK_EXTERNAL_URLS=0`).
- No diálogo "Deseja descartar as edições?" aparece um retângulo cinza atrás do cartão (pendente).
