# ADR 0025 — Chips do perfil como no celular

## Contexto
O APK 455 declara `dimen/igds_chip_radius` = 99dp: chips em pílula. No celular do dono (outra
versão do Instagram) os mesmos chips são retângulos de cantos arredondados. O dono não quer
atualizar o APK e pediu o visual do celular ("faça tudo isso", 2026-11-12).

## Decisão
Substituição de recurso por nome no runtime (`MACAPK_RES_OVERRIDES`, `ResourceIndex`): o
launcher do Instamac define `dimen/igds_chip_radius=8dp`, o mesmo canto dos botões da tela de
perfil. Vale para toda leitura do valor (código e estilos). Patch 0031.

## Medição
Perfil no clone: os chips (Threads, "+ Adicionar") desenhados com cantos de 8dp.
