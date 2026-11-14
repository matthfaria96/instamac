# ADR 0008 — Bundle compacto: sem duplicata, comprimido, cache fora do .app

**Status:** aceito em 2026-11-11

## Medição do ponto de partida (app instalado, 1,6 GB)
`classes.jar` 454 MB · `data/app` (base.apk + split) 267 MB · `.xapk` embutido 264 MB ·
cache do Instagram 189 MB · `lib_native` 127 MB · `lib-compressed` 109 MB · runtime 164 MB.

## Decisão
1. **Sem o container embutido depois do preseed.** `app/embedded/*.xapk` é cópia byte a byte
   do `base.apk` instalado; o launcher já abre pelo instalado quando não há container
   (`largestApk(under: data/app)`), sem reconverter (7 s, igual a antes).
2. **Compressão transparente do APFS** (`ditto --noclone --hfsCompression`) no que não muda
   em uso: runtime 165→115 MB, `classes.jar` 455→239, `lib_native` 128→68, `base.apk`
   257→155, `lib-compressed` 109→62. O kernel descomprime na leitura: mesmos bytes, mesma
   assinatura, mesmo mtime. Sem `--noclone` o `ditto` clona e não comprime nada.
3. **Cache fora do bundle.** O launcher mantém `data/data/<pkg>/cache` como link para
   `~/Library/Caches/dev.instamac.app/<pkg>/cache` (refeito a cada abertura). O `.app` deixa
   de crescer com o uso e o macOS pode limpar o cache.

Tudo em `scripts/compact-app.sh <app>` (passo 7c do build; roda também no app instalado,
fechado) e em `keepCachesOutOfBundle()` no launcher.

## Resultado
App instalado: **1,6 GB → 742 MB**; vídeo dos Reels toca com o cache realocado (227
arquivos escritos em 1 min). Gate de boot depois de compactar: **10/10 em 5–8 s**
(`scripts/boot-loop.sh 10 -`), igual a antes — a descompressão não custa no boot.

## Consequências e o que sobra
- Cópia pelo Finder ou `cp` descomprime; use `ditto` (os scripts usam) ou distribua em DMG/zip.
- Arquivo que o app reescrever perde a compressão (não quebra nada).
- Trocar de versão: `Instamac --apk <novo>` continua copiando para `app/embedded`; rode
  `compact-app.sh` depois da primeira abertura.
- Ainda dá para cortar: a JRE embutida (59 MB) não é usada (o runtime carrega a `libjvm` do
  Homebrew — P5); `Resources/tools` (22 MB) e `libskiko` (20 MB) precisam de prova de que
  nada os carrega; os `.dex` dentro do `base.apk` são peso morto mas mexer no APK muda a
  identidade dele.

## Atualização (mesmo dia): até onde a compressão vai
- App instalado agora: **646 MB em disco** (1,6 GB no começo do dia).
- A JRE embutida saiu do bundle (43 MB em disco): o `macapk-runtime` compilado aqui liga a
  `libjvm` do Homebrew por caminho absoluto e nenhum arquivo dela é aberto (`lsof`). O
  `compact-app.sh` só a remove nessa condição (`otool -L`); `COMPACT_KEEP_JRE=1` mantém.
- `modules`, `files`, `app_restricks` e `app_analytics` também comprimidos (-46 MB).
- `--zlibCompressionLevel 9` **não ganha nada** sobre o padrão do `ditto` (classes.jar
  239 → 252 MB): a compressão transparente do APFS já está no teto.
- As classes convertidas já não têm informação de depuração (sem `LineNumberTable`).
- O Finder mostra dois números: tamanho lógico (~1,1 GB) e **em disco (646 MB)**. O que
  ocupa o SSD é o segundo.

## O que ainda pesa e por que não mexi
| parte | em disco | por quê fica |
|---|---|---|
| `classes.jar` | 239 MB | as 228 mil classes do Instagram; formato com acesso aleatório exigido pela JVM |
| `base.apk` | 155 MB | 184 MB dele são `.dex` já convertidos (peso morto), mas tirar muda os bytes do APK oficial — o app pode conferir a própria integridade |
| `lib_native` + `lib-compressed` | 122 MB | bibliotecas nativas traduzidas + as originais que o app exige presentes |
| runtime | 71 MB | binários, jars, ANGLE/MoltenVK |

Um arquivo "sólido" (zstd/xz de tudo) cairia para uns 250–300 MB, mas precisaria ser
expandido na primeira abertura — o que a regra 3 do produto proíbe.

