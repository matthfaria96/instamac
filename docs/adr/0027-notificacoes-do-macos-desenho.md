# ADR 0027 — Notificações do macOS: o que falta (desenho, não implementado)

**Status:** substituído pelo ADR 0037 (implementado em 2026-11-13).

## Contexto
`NotificationManager.notify` do runtime é vazio: notificações do Instagram somem. Mas o
Instagram só posta notificação de sistema quando se acha em segundo plano, e o runtime nunca
leva a atividade a `onPause`/`onStop`: janela minimizada, escondida (⌘H) ou coberta só muda a
apresentação (`macapk_update_window_hidden_state`, "tracked only").

## Desenho proposto (duas partes, nesta ordem)
1. **Ciclo de vida espelhando a janela:** minimizada/escondida/coberta → `onPause` + `onStop`;
   de volta → `onRestart`/`onStart`/`onResume`. Efeitos a medir: vídeo e som param (como no
   celular), a conexão em tempo real pode cair para o push (FBNS) depois de um tempo.
2. **Ponte de notificações:** o processo do runtime não é um bundle registrado (executa
   `Contents/Resources/runtime/Resources/macapk-runtime`, identidade `dev.instamac.runtime`), e o
   `UNUserNotificationCenter` exige um. Um app auxiliar em `Contents/Helpers`
   (`dev.instamac.notifier`, sem Dock, nome e ícone do Instamac) recebe por notificação
   distribuída {chave, título, texto} e posta pelo `UNUserNotificationCenter`; o clique volta
   pelo mesmo canal, o runtime traz a janela e dispara o `contentIntent`. Pula notificações
   contínuas, de progresso e resumos de grupo; nada é postado com o Instamac ativo. Selo do
   Dock = notificações ativas. Pedido de permissão do macOS uma vez (para o auxiliar).

## Por que não agora
Os dois passos mudam o comportamento de todo o app e só se validam com mensagens reais
chegando (alguém escrevendo para o dono) — teste a combinar.
