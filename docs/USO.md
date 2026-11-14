# Como usar o Instamac

O Instamac não é um instalador de Instagram: ele **é** o Instagram instalado, em um app
macOS de verdade. Não existe etapa de "escolher o APK", não existe primeiro uso pela
metade, não existe tela de conversão.

## O que você precisa (para construir)

- Mac com **Apple Silicon** e **macOS 26.4 ou mais novo** (o runtime exige).
- O **APK do Instagram** em `payload/` (`.apk`, `.xapk`, `.apkm`, `.apks`). Ele não é
  versionado: é o arquivo que você forneceu, e ele entra no *seu* bundle.
- **~4 GB livres**: o build gera ~1,4 GB de app e usa o dobro enquanto trabalha.

## Build

```bash
git submodule update --init --recursive
scripts/build-dexconv.sh        # tradutor dex→JVM com o patch do Instamac
scripts/build-instamac.sh       # embute payload/, instala o Instagram e assina
open build/Instamac.app
```

`scripts/build-instamac.sh` sozinho já encontra `payload/*.apk|*.xapk` (ou um container
solto na raiz) e pré-instala. O app que sai em `build/Instamac.app` abre direto na tela de
login — o Instagram dentro dele está instalado, convertido e com as libs traduzidas.

Variáveis úteis:

| variável | efeito |
|---|---|
| `INSTAMAC_APK=<arquivo>` | usa outro APK/container, fora do `payload/` |
| `INSTAMAC_SKIP_PRESEED=1` | monta sem pré-instalar (build rápido; o app converte na 1ª abertura) |
| `INSTAMAC_PRESEED_VERIFY=0` | pula a passada morna de verificação do preseed |
| `INSTAMAC_DEV=1` | modo dev antigo, herdando de `/Applications/Instagram.app` |

## Atualizar sem perder o login

```bash
scripts/build-framework.sh          # se src/framework mudou
INSTAMAC_SKIP_PRESEED=1 scripts/build-instamac.sh
scripts/patch-app.sh                # troca runtime + launcher, preserva dados
```

`patch-app.sh` substitui só `Contents/Resources` e `Contents/MacOS`. O Instagram
instalado em `Contents/android` (sessão, prefs, classes convertidas) não é tocado — é o
jeito de aplicar correção de código sem zerar o login. Use `deploy.sh` quando o APK ou o
tradutor mudarem, porque aí o código convertido precisa ser refeito.

## Janela: comportamento de tablet

A janela é uma janela Mac normal: redimensiona e o Android recalcula a configuração em
cima (`smallestScreenWidthDp` acompanha o lado menor). Em janela horizontal o Instagram
recebe um canvas de tela grande (classe tablet); em janela vertical, o vertical. O padrão
do launcher é `MACAPK_LETTERBOX_ASPECT=display`, que faz o app preencher a janela em vez
de ficar letterboxado em 4:3.

Dois arquivos em `Contents/android/.macapk/` ajustam sem recompilar:

| arquivo | conteúdo | efeito |
|---|---|---|
| `runtime_env` | `CHAVE=valor` por linha | variáveis do runtime (vencem o default do launcher) |
| `runtime_args` | argumentos separados por espaço | ex.: `--width 1200 --height 1600` |
| `runtime_env` | `CHAVE=valor` por linha | ex.: `MACAPK_PAUSE_WHEN_HIDDEN=1` para voltar a economizar energia quando a janela está coberta |

Exemplo para abrir sempre em tablet retrato:

```bash
echo "--width 1200 --height 1600" > \
  "/Applications/Instamac.app/Contents/android/.macapk/runtime_args"
```

## Celular ou tablet

Menu **Visualizar**: **Celular** (412×915, barra de abas embaixo) ou **Tablet** (1280×800,
trilho lateral). A escolha fica guardada (ADR 0010).

## Logs

Cada abertura grava `~/Library/Logs/macapk/app_com.instagram.android_<data>.log` (os 3
mais recentes ficam; o launcher apaga os antigos). É o primeiro lugar a olhar quando algo
falha: `grep -n "FATAL EXCEPTION"` e `grep -n "\[E\]"`.

## Ciclo de desenvolvimento: instalar por cima

```bash
scripts/reset-app-data.sh  # se o boot travar: afasta o estado do app e reabre
scripts/deploy.sh
```

Recompila, preserva a árvore já preparada do app instalado (sessão e código convertido),
assina e substitui `/Applications/Instamac.app`, depois abre. O APK vem de `payload/`
(ou de `INSTAMAC_APK=...`); o runtime vem de `runtime/`.

## Instalar

1. Monte o `Instamac.dmg` (`scripts/make-dmg.sh`) e arraste **Instamac** para
   **Applications**.
2. Abra pelo Launchpad ou pelo Dock. Primeira abertura = abertura normal: sem conversão,
   sem progresso, sem seletor.

## Uso normal

Duplo clique → janela do Instagram nativa, com menu próprio, ⌘Tab, Dock. Nada de
navegador, nada de runtime de terceiros à vista, nada gravado em `~/Library` além do log.

O log do runtime fica em `~/Library/Logs/macapk/` — é o que eu peço quando algo falha.

## Atualizar o Instagram

```bash
open -a Instamac --args --apk ~/Downloads/instagram-novo.xapk
```

O container novo é copiado para dentro do bundle, o código da versão antiga é descartado e
o runtime reinstala no lançamento seguinte. É a única atualização que ainda converte na
hora — o APK novo não existe no momento do build.

## Desinstalar

1. Arraste o Instamac para o Lixo.
2. Se quiser apagar também os logs: `rm -rf ~/Library/Logs/macapk`.

## Limitações conhecidas

- **Login**: a tela de login renderiza, mas o login real ainda não foi verificado (não
  tenho a sua conta).
- Três métodos gigantes do Instagram ainda não convertem e viram stub que lança se forem
  chamados: `X/09IF.A0p`, `X/0bRx.getValues` e um `invoke` de 168 KB. Detalhes em
  [F1B.md](F1B.md). Se algum recurso específico quebrar, provavelmente é um deles.
- Sem notarização: o app é assinado ad-hoc. Nesta máquina abre normalmente; em outra, pode
  ser preciso clicar com o botão direito → Abrir.
