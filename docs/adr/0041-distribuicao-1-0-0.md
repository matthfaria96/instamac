# ADR 0041 — Distribuição: DMG 1.0.0 limpo, repositório público

**Status:** aceito em 2026-11-14 (`scripts/release-clean.sh`, `scripts/make-dmg.sh`)

## Contexto
O dono decidiu publicar o DMG (com o Instagram dentro) no GitHub e no witchmymac, aceitando o
risco de pedido de remoção pela Meta. O app montado pelo build não pode ir como está: o preseed
abre o Instagram duas vezes e deixa estado de UMA instalação, que seria igual para todos.

## O que o preseed deixa e a limpeza tira
- identidade: `data/data/.macapk-settings` (`android_id`), `files/INSTALLATION`, `shared_prefs`
  (cabeçalhos de autenticação, ids do MQTT), bancos, `no_backup`, telemetria e relatórios;
- caches de GPU (`.angle_blob`, `.gles31cache`), índice de mídia, `data/system`;
- caminhos absolutos com o usuário de quem compilou: `meta.json` (dados e código), `.shimdir` do
  executor nativo e o carimbo do ícone. O runtime regrava os três com o lugar real ao abrir.
Fica o trabalho caro e igual para todos: código traduzido, `lib-compressed` (0555), módulos
(0444), `app_restricks`, `app_strings`, `.x18cache`. O script falha se sobrar `$HOME` no bundle.

**Modo inicial:** sem `.macapk/window_pref/<pacote>` o runtime abre no Tablet; o lançamento grava
`portrait` (Celular), que com o Tamanho da Interface automático é a janela que o dono escolheu.

## Medição
- Cópia limpa: abre na tela "Participe do Instagram", modo Celular 515×1144, sem conta.
- DMG 608 MB (app 649 MB em disco); `codesign --verify --deep` ok; entitlements de JIT/x18 do
  runtime preservadas; nenhum arquivo com o caminho pessoal.
- Requer macOS 26.4 (`LSMinimumSystemVersion`) em Apple Silicon. Sem Developer ID: a primeira
  abertura exige tirar a quarentena (comando do site) ou Abrir pelo botão direito.

## Repositório
O histórico privado tinha um log com caminhos da máquina do dono e um telefone (já apagados da
árvore, mas presentes em commits antigos). O repositório público começa num commit único; o
histórico antigo foi apagado, a pedido do dono (sem chaves, senhas nem dados pessoais).
