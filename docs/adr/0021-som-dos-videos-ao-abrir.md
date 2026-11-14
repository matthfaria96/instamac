# ADR 0021 — Som dos vídeos ao abrir (menu Visualizar)

## Contexto
O dono pediu uma opção no menu para os vídeos/Reels começarem sempre com som ou sempre sem som
ao abrir o app. O estado do som é do Instagram (controlador do feed `X.06yS`, do Reels
`X.04OW`, estado global lido pelos dois). Mexer nele por dentro amarraria o runtime a nomes
ofuscados de uma versão.

## Decisão
Mandar a escolha como um celular manda: pela tecla de volume.
- **Ativado:** volume de mídia +1 e `KEYCODE_VOLUME_UP`.
- **Desativado:** volume de mídia 0 e `KEYCODE_VOLUME_DOWN`; o volume volta em silêncio depois
  que a tecla é tratada. O Instagram lê "abaixar com o volume em 0" como som desligado.
- Enviado quando uma faixa começa a tocar (`AudioTrack.play`): é quando há vídeo na tela e o
  controlador dele escuta a tecla (o do feed só a aceita com um vídeo do feed tocando). Se
  ninguém aceitar, tenta de novo numa faixa seguinte (3 s de intervalo, até 6 vezes). No modo
  desligado, a faixa da tentativa fica muda até o player aplicar o volume novo (sem estalo).
- Menu Visualizar › Som dos Vídeos ao Abrir: Ativado / Desativado / Padrão do Instagram. Fica
  nas preferências do runtime (`dev.instamac.runtime`, chave `VideoSoundAtStart` 0/1/2), é
  copiado antes da JVM para `MACAPK_VIDEO_SOUND_AT_START` (que continua mandando se definido)
  e vale na hora quando trocado pelo menu.
- O `AudioManager` passou a se comportar como volume observável: volumes compartilhados,
  `setStreamVolume/adjustStreamVolume` notificam `content://settings/system` e mandam
  `VOLUME_CHANGED_ACTION`.

Descartado: perda de foco de áudio (`AUDIOFOCUS_LOSS`) — o Reels só baixa a faixa atual e
volta a 1.0 na seguinte; `KEYCODE_VOLUME_MUTE` não é tratado; volume 0 + campainha em
silêncio é ignorado.

## Medição (clone)
- Desativado (preferência gravada, sem variável): Reels abre, `volume key 25 … handled=true`,
  `AudioTrack setVolume 0.0` na faixa do Reel.
- Ativado: no feed, a tecla para cima troca o botão do vídeo para "Desativar som".

## Consequências
- Não testado à mão pelo dono (menu e sensação). Patch 0028.
- `MACAPK_AUDIO_VOLUME_TRACE=1` registra cada `setVolume` com quem chamou.
