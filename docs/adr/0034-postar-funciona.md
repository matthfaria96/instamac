# ADR 0034 — Postar funciona: SQLite aninhado, fundo de diálogo e folhas inferiores

**Status:** aceito em 2026-11-12 (patch `0042`)

## Medido (conta de teste do dono)
- Compartilhar não fazia nada: o banco de mídias pendentes do Instagram executa `BEGIN` cru
  dentro do `onCreate` (já em transação) e falhava ("cannot start a transaction within a
  transaction"); o post renderizado nunca era registrado. Agora BEGIN/COMMIT/ROLLBACK crus viram
  transações aninhadas, como no `SQLiteSession.executeSpecial` do AOSP.
- Folhas inferiores (seletor de contas, Adicionar perfil) abriam como caixa cinza ou ficavam
  abaixo da tela: fundo padrão de diálogo por cima do tema transparente; layout da janela a todo
  quadro (reiniciava o deslize); OnGlobalLayout/OnPreDraw nunca entregues a janelas de diálogo.

## Resultado
Dois posts publicados na conta de teste, um com legenda e música sugerida. Seletor de contas e
"Adicionar Instagram" abrem e deslizam como no celular.

## Pendente
Campo de usuário do login não recebe foco ao toque (o texto vai para a senha); senha aparece em
texto aberto; miniatura da tela de legenda fica no placeholder; música sugerida às vezes demora.
O toque injetado e o `hosttap` não acionam botões dentro de folhas (só o mouse real).

## Adendo: prévia de música sem som (patch `0043`)
O conversor AAC do macOS recusava o config cru das prévias de música ('!dat'); nada era
decodificado e o painel de música girava sem som. Agora, nessa recusa, o conversor é refeito a
partir do ES_Descriptor completo. Medido: painel carrega, forma de onda e progresso andam.

## Adendo: destaques e stories sem som (patch `0044`)
O Instagram começa mudo até uma tecla de volume, que no Mac vai para o sistema. Padrão agora é
"Som dos Vídeos ao Abrir: Ativado", com o volume + enviado após o primeiro foco da janela.

## Adendo: cache de medida (patch `0045`)
onMeasure só roda quando pedido ou com spec nova (regra do AOSP). Layout da galeria 4,1→1,5 ms,
música 6,2→3,4 ms; gate 5/5; abertura 8–9 s. `MACAPK_MEASURE_CACHE=0` desliga.
