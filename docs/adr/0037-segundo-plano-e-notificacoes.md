# ADR 0037 — Janela fora de vista = app em segundo plano; notificações do macOS; barra de título

**Status:** aceito em 2026-11-13 (patches `0049`, `0050`). Substitui o desenho do ADR 0027.

## Segundo plano
Janela minimizada, app oculto (⌘H), janela totalmente coberta ou telas dormindo → depois de
1 s, a atividade do topo vai a `onPause`/`onStop` (o par `hostCover` do `ActivityHost`), como um
celular com o app em segundo plano; janela de volta → `onRestart`/`onStart`/`onResume`. Visível
atrás de outro app = continua ativo (vídeo segue tocando). Com o app em `onStop`, a apresentação
do lado do Mac cai para 2 Hz mesmo com `MACAPK_PAUSE_WHEN_HIDDEN=0` (o launcher desliga esse
freio porque uma janela só coberta voltava preta; com `onStop` a volta reinstala o conteúdo).

Knobs: `MACAPK_BACKGROUND_WHEN_HIDDEN=0` desliga; `MACAPK_BACKGROUND_ON_OCCLUSION=0` faz só
minimizar/⌘H/tela contarem (os scripts de teste usam, porque abrem o app atrás das janelas do
dono; `UI_OCCLUSION=1` no `ui.sh` mantém a regra do produto).

Medido (Instagram, tempo de CPU do processo em 10–15 s): visível 20–21%; minimizado/oculto
9–14%. O Instagram registra "Moving to background", libera os players e os recria na volta;
vídeo e som voltam (minimizar → restaurar nos Reels).

## Notificações
O `UNUserNotificationCenter` exige um bundle registrado; o runtime não é um (executável em
`Contents/Resources/runtime/Resources`, via `execv`). Um auxiliar `Contents/Helpers/
InstamacNotifier.app` (`dev.instamac.notifier`, sem Dock, nome e ícone do Instamac;
`tools/notifier/main.swift`, `scripts/build-notifier.sh`) posta e devolve o clique por
notificação distribuída. `NotificationManager.notify` pula notificações contínuas, de
progresso, resumos de grupo, canais desligados e tudo com o Instamac na frente; clique →
janela volta e o `contentIntent` dispara. Selo do Dock = postadas e não canceladas.

**Neste macOS (27.2), o `UNUserNotificationCenter` nega na hora, sem pedido, qualquer app
sem assinatura emitida pela Apple** ("Notifications are not allowed for this application"):
medido com o auxiliar ad-hoc, com a identidade local e com um app mínimo separado. O
`NSUserNotificationCenter` (obsoleto) entrega sem autorização; o auxiliar usa ele enquanto o
outro negar. Com Developer ID, o caminho novo entra sozinho.

Medido com `MACAPK_NOTIFY_SELFTEST=1` (posta uma notificação real pelo `NotificationManager`
ao ir para o segundo plano): post → Central de Notificações (legado) → clique (sinal do
auxiliar) → janela restaurada, `onRestart/onStart/onResume`, `contentIntent` → `onNewIntent`.

**Não medido:** se o Instagram em segundo plano recebe mensagens (MQTT/FBNS no mesmo
processo) e chama `notify`. Validar: mandar uma DM para a conta de teste com o Instamac
minimizado.

## Barra de título (pedido do dono)
Sem o título "Instamac"; três botões centralizados, retângulos de cantos arredondados com borda
fina, mais claros sob o ponteiro: Voltar, Girar (⌘R) e Criar (menu: Nova Publicação, Novo
Story, Novo Reel, Enviar por Mensagem, a partir de arquivos do Mac).
