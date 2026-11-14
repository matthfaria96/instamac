#!/usr/bin/env bash
# Monta Instamac.app: UM app macOS com o Instagram já instalado dentro.
# Sem Mac.apk instalado, sem seletor de APK, sem conversão no primeiro uso.
#
#   scripts/build-instamac.sh                     embute o payload/ e pré-instala
#   INSTAMAC_APK=<arquivo> scripts/build-instamac.sh   usa outro APK/container
#   INSTAMAC_DEV=1 scripts/build-instamac.sh      modo dev: herda de Instagram.app
#   INSTAMAC_SKIP_PRESEED=1 scripts/build-instamac.sh  não pré-instala (rápido)
#
# Saída: build/Instamac.app
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC_APP="${INSTAMAC_SRC_APP:-/Applications/Instagram.app}"
# O APK vai DENTRO do bundle e os dados ficam em Contents/android: o app abre
# direto no Instagram, sem seletor e sem nada em ~/Library. O build termina com
# o app já instalado (scripts/preseed.sh) -- "por natureza", não no primeiro uso.
EMBED_APK="${INSTAMAC_APK:-}"
# Modo dev antigo (herda app+recursos de um /Applications/Instagram.app já
# preparado), útil só para depurar o runtime fora do bundle.
DEV_MODE="${INSTAMAC_DEV:-0}"
RT="${INSTAMAC_RUNTIME:-$HOME/Library/Application Support/Mac.apk/runtime}"
JDK="${INSTAMAC_JDK:-/opt/homebrew/opt/openjdk@25}"
APP="$ROOT/build/Instamac.app"
DATA="$HOME/Library/Application Support/Instamac/com.instagram.android"
SRC_DATA="$(readlink "$SRC_APP/Contents/android" || true)"

say() { printf '\n== %s\n' "$*"; }
die() { printf 'erro: %s\n' "$*" >&2; exit 1; }

# Fonte do runtime, em ordem: o instalado, o app já instalado, o build anterior.
# Assim o ciclo de deploy não depende do Mac.apk estar instalado na máquina.
if [ ! -f "$RT/lib/macapk-loader.jar" ]; then
  for cand in "$ROOT/runtime" \
              "/Applications/Instamac.app/Contents/Resources/runtime" \
              "$APP/Contents/Resources/runtime"; do
    if [ -f "$cand/lib/macapk-loader.jar" ]; then RT="$cand"; break; fi
  done
fi
[ -f "$RT/lib/macapk-loader.jar" ] || die "runtime não encontrado (nem em ~/Library nem no app instalado)"

# Sem INSTAMAC_APK, o payload do próprio repositório manda: payload/ primeiro,
# depois um container solto na raiz. É o que faz `scripts/build-instamac.sh`
# sozinho produzir o app completo -- sem variável, sem escolha, sem primeiro uso
# pela metade.
if [ -z "$EMBED_APK" ] && [ "$DEV_MODE" != "1" ]; then
  for cand in "$ROOT"/payload/*.apk "$ROOT"/payload/*.xapk \
              "$ROOT"/payload/*.apkm "$ROOT"/payload/*.apks \
              "$ROOT"/*.apk "$ROOT"/*.xapk "$ROOT"/*.apkm "$ROOT"/*.apks; do
    if [ -f "$cand" ]; then EMBED_APK="$cand"; break; fi
  done
fi
if [ -n "$EMBED_APK" ]; then
  [ -f "$EMBED_APK" ] || die "INSTAMAC_APK não existe: $EMBED_APK"
  case "$(basename "$EMBED_APK" | tr 'A-Z' 'a-z')" in
    *.apk|*.xapk|*.apkm|*.apks|*.apkx) ;;
    *) die "INSTAMAC_APK precisa ser .apk/.xapk/.apkm/.apks/.apkx" ;;
  esac
else
  [ -d "$SRC_APP" ] || die "$SRC_APP não existe (ou passe INSTAMAC_APK=<arquivo>)"
  [ -n "$SRC_DATA" ] && [ -d "$SRC_DATA" ] || die "payload de origem não encontrado ($SRC_DATA)"
fi
[ -x "$JDK/bin/jar" ] || die "JDK não encontrado em $JDK"

say "1/8 limpando build/"
chmod -R u+w "$APP" 2>/dev/null || true
rm -rf "$APP"
mkdir -p "$APP/Contents"

say "2/8 APK e identidade"
if [ -n "$EMBED_APK" ]; then
  mkdir -p "$APP/Contents/app/embedded" "$APP/Contents/android"
  cp "$EMBED_APK" "$APP/Contents/app/embedded/$(basename "$EMBED_APK")"
  # Info.plist base: um mínimo nosso, sem herdar nda de uma instalação antiga.
  cp "$SRC_APP/Contents/Info.plist" "$APP/Contents/Info.plist" 2>/dev/null \
    || cp "$ROOT/launcher/Info.plist" "$APP/Contents/Info.plist" 2>/dev/null || true
  printf '%s\n' "$(basename "$EMBED_APK")" > "$APP/Contents/app/embedded/EMBEDDED"
else
  ditto "$SRC_APP/Contents/app" "$APP/Contents/app"
  ditto "$SRC_APP/Contents/Resources" "$APP/Contents/Resources"
  cp "$SRC_APP/Contents/Info.plist" "$APP/Contents/Info.plist" 2>/dev/null || true
fi
mkdir -p "$APP/Contents/Resources"

say "2b/8 icone (assets/Instamac.icns; trocar com scripts/set-icon.sh)"
cp "$ROOT/assets/Instamac.icns" "$APP/Contents/Resources/AppIcon.icns"
# PNG do mesmo ícone: o runtime carrega ícone de Dock por ARQUIVO (NSImage), e é
# este que o launcher passa em MACAPK_APP_ICON. Fixo no Instamac, sempre.
cp "$ROOT/assets/instamac-icon-1024.png" "$APP/Contents/Resources/InstamacIcon.png"

say "3/8 embutindo o runtime"
mkdir -p "$APP/Contents/Resources"
ditto "$RT" "$APP/Contents/Resources/runtime"
# O fallback de ícone do runtime (usado quando MACAPK_APP_ICON não resolve) é o
# mesmo PNG dos assets: uma fonte só, qualquer que seja o runtime de origem.
cp "$ROOT/assets/instamac-icon-1024.png" \
   "$APP/Contents/Resources/runtime/Resources/macapk_default_icon.png"
# Os nativos compilados do vendor/ (com os patches de contrib/upstream/patches)
# vencem os do runtime extraído: sem isto, um build a partir de runtime/ embarca
# o shim antigo e traz de volta o boot travado da sessão logada (PRODUTO.md F1q).
# Copiar preserva a assinatura do build (as entitlements de x18/JIT do runtime);
# nunca reassinar o binário aninhado.
# (O binário do runtime entra no passo 4c, o da JDK 25.)
for pair in \
    "vendor/macapk/runtime/translator/build/libmacapk-bionic-shim.dylib:bin/libmacapk-bionic-shim.dylib"; do
  src="$ROOT/${pair%%:*}"; dst="$APP/Contents/Resources/runtime/${pair#*:}"
  if [ -f "$src" ] && [ -f "$dst" ] && ! cmp -s "$src" "$dst"; then
    cp "$src" "$dst" && echo "   nativo do vendor: ${pair#*:}"
  fi
done

say "4/8 patch do tradutor (se compilado)"
if [ -f "$ROOT/build/classes/com/macapk/dex/MethodSplitter.class" ]; then
  # Os DOIS jars: android-framework.jar vem primeiro no classpath do converter e
  # tambem carrega com.macapk.dex.*, entao so patchear o loader nao adianta.
  for j in android-framework.jar macapk-loader.jar; do
    ( cd "$ROOT/build/classes" && "$JDK/bin/jar" --update \
        --file "$APP/Contents/Resources/runtime/lib/$j" com )
  done
  echo "   classes de build/classes injetadas nos jars do runtime"
else
  echo "   (sem build/classes; rode scripts/build-dexconv.sh para incluir o patch)"
fi

say "4b/8 classes Java nossas (se compiladas)"
# build/framework-classes = overlay de src/framework + patches Java do vendor
# (scripts/build-framework.sh). Sem elas o bundle perde, entre outras coisas: a
# normalização do Cipher nulo (o Instagram morre no boot com dados existentes), a
# identidade Android "Instamac" e a densidade em linhas de valor (a barra de abas
# inferior fica com altura 0).
if [ -d "$ROOT/build/framework-classes" ]; then
  "$ROOT/scripts/inject-classes.sh" "$ROOT/build/framework-classes" \
    "$APP/Contents/Resources/runtime/lib"
else
  echo "   (sem build/framework-classes; rode scripts/build-framework.sh)"
fi

say "4c/8 JVM embutida (JDK 25, sem Homebrew; INSTAMAC_JDK=21 mantém a do sistema)"
# ADR 0019: o runtime ligado à JDK 25 (vendor/macapk/runtime/build-jdk25), uma JRE
# mínima com as correções do java.base/jdk.unsupported GRAVADAS nos módulos (o que
# dispensa --patch-module e libera o cache AOT) e o binário reapontado para ela.
if [ "${INSTAMAC_JDK:-25}" = 25 ]; then
  J25="${INSTAMAC_JDK25_HOME:-/opt/homebrew/opt/openjdk@25/libexec/openjdk.jdk/Contents/Home}"
  RT25_BIN="$ROOT/vendor/macapk/runtime/build-jdk25/macapk-runtime"
  [ -x "$J25/bin/jlink" ] || die "JDK 25 não encontrada em $J25 (brew install openjdk@25)"
  [ -x "$RT25_BIN" ] || die "runtime JDK 25 não compilado ($RT25_BIN); veja ADR 0019"
  P25="$ROOT/build/lib-jdk25"
  rm -rf "$P25" && mkdir -p "$P25/java_base_patch" "$P25/jdk_unsupported_patch"
  "$J25/bin/javac" -nowarn --patch-module "java.base=$ROOT/vendor/macapk/runtime/java_base_patch_jdk25" \
    -d "$P25/java_base_patch" $(find "$ROOT/vendor/macapk/runtime/java_base_patch_jdk25" -name '*.java')
  "$J25/bin/javac" -nowarn --patch-module "jdk.unsupported=$ROOT/vendor/macapk/runtime/jdk_unsupported_patch" \
    --add-exports java.base/jdk.internal.misc=jdk.unsupported \
    -d "$P25/jdk_unsupported_patch" $(find "$ROOT/vendor/macapk/runtime/jdk_unsupported_patch" -name '*.java')
  rm -rf "$ROOT/build/jre25"
  MACAPK_JDK=25 MACAPK_JRE_BAKE_PATCHES="$P25" \
    bash "$ROOT/vendor/macapk/scripts/stage_jre.sh" "$J25" "$ROOT/build/jre25" | tail -1
  "$ROOT/scripts/embed-jre.sh" "$APP" "$RT25_BIN" "$ROOT/build/jre25" "$P25"
fi

say "5/8 dados do app"
if [ -n "$EMBED_APK" ]; then
  # autocontido: nada em ~/Library, o android-root é Contents/android
  echo "   modo autocontido: dados em Contents/android"
else
  echo "   modo dev: dados em ~/Library/Application Support/Instamac"
mkdir -p "$(dirname "$DATA")"
chmod -R u+w "$DATA" 2>/dev/null || true
rm -rf "$DATA"
ditto "$SRC_DATA" "$DATA"
# Codigo preparado NAO vem do app antigo: precisa ser reconvertido pelo
# tradutor que esta embutido neste bundle (senao herda classes com stub).
chmod -R u+w "$DATA/.macapk" 2>/dev/null || true
rm -rf "$DATA/.macapk/code"/* 2>/dev/null || true
rm -rf "$DATA/android/.macapk/code"/* 2>/dev/null || true

# data/app aponta para o APK retido DENTRO deste bundle
rm -rf "$DATA/data/app"
mkdir -p "$DATA/data"
ln -s "$APP/Contents/app" "$DATA/data/app"
fi

say "5b/8 tornando as libs nativas reais (sem symlink para fora do bundle)"
# O instalador deixa lib/arm64/*.dylib como symlink para o código preparado em
# ~/Library. Se ficarem assim, o Instamac depende do app antigo e o bundle não
# sela. Aqui cada link vira uma cópia de verdade.
find "$APP/Contents/app" -type l -print0 2>/dev/null | while IFS= read -r -d '' l; do
  target="$(readlink "$l")"
  if [ -f "$target" ]; then
    cp -p "$target" "$l.copy" && mv "$l.copy" "$l"
  else
    rm -f "$l"
  fi
done

say "6/8 instalando o Instagram DENTRO do bundle (converter + traduzir)"
# Isto é o que faz o app ser o Instagram instalado, e não um instalador dele:
# o runtime roda uma vez contra Contents/android, faz o trabalho pesado no build
# e o resultado viaja assinado. O primeiro uso passa a ser igual ao segundo.
if [ -n "$EMBED_APK" ] && [ "${INSTAMAC_SKIP_PRESEED:-0}" != "1" ]; then
  INSTAMAC_PRESEED_VERIFY="${INSTAMAC_PRESEED_VERIFY:-1}" \
    "$ROOT/scripts/preseed.sh" "$APP"
else
  echo "   (pulado: INSTAMAC_SKIP_PRESEED=1 ou build de desenvolvimento)"
fi

say "7/8 launcher + identidade"
mkdir -p "$APP/Contents/MacOS"
swiftc -O -target arm64-apple-macos26.0 -o "$APP/Contents/MacOS/Instamac" \
  "$ROOT/launcher/InstamacMain.swift"
chmod +x "$APP/Contents/MacOS/Instamac"
rm -f "$APP/Contents/MacOS/Instagram" "$APP/Contents/MacOS/.Instagram" 2>/dev/null || true
# link plano em Contents/MacOS, nomeado como o app: é o que faz o menu,
# o ps e o relatório de crash dizerem "Instamac" em vez de "macapk-runtime"
ln -sfn "../Resources/runtime/Resources/macapk-runtime" \
  "$APP/Contents/MacOS/.Instamac"

PB=/usr/libexec/PlistBuddy
"$PB" -c "Set :CFBundleExecutable Instamac" "$APP/Contents/Info.plist"
"$PB" -c "Set :CFBundleName Instamac" "$APP/Contents/Info.plist"
"$PB" -c "Set :CFBundleDisplayName Instamac" "$APP/Contents/Info.plist"
"$PB" -c "Set :CFBundleIdentifier dev.instamac.app" "$APP/Contents/Info.plist" 2>/dev/null \
  || "$PB" -c "Add :CFBundleIdentifier string dev.instamac.app" "$APP/Contents/Info.plist"
"$PB" -c "Delete :CFBundleURLTypes" "$APP/Contents/Info.plist" 2>/dev/null || true
# Idiomas: o bundle não tem .lproj; sem esta lista os painéis do sistema (abrir
# arquivo, alertas) saem em inglês mesmo num Mac em português.
"$PB" -c "Delete :CFBundleLocalizations" "$APP/Contents/Info.plist" 2>/dev/null || true
"$PB" -c "Add :CFBundleLocalizations array" "$APP/Contents/Info.plist"
for loc in pt_BR pt en; do "$PB" -c "Add :CFBundleLocalizations: string $loc" "$APP/Contents/Info.plist"; done
"$PB" -c "Delete :CFBundleAllowMixedLocalizations" "$APP/Contents/Info.plist" 2>/dev/null || true
"$PB" -c "Add :CFBundleAllowMixedLocalizations bool true" "$APP/Contents/Info.plist"
"$PB" -c "Delete :LSMultipleInstancesProhibited" "$APP/Contents/Info.plist" 2>/dev/null || true

say "7a/8 bibliotecas de fora do sistema para dentro do app (sem Homebrew)"
# O shim do tradutor liga contra capstone e libpng do Homebrew: copiadas para
# runtime/lib-host e reapontadas por @loader_path. O passo falha se sobrar
# qualquer dependência de /opt/homebrew ou /usr/local.
"$ROOT/scripts/bundle-host-libs.sh" "$APP"

say "7a2/8 notificações do macOS (Contents/Helpers/InstamacNotifier.app, ADR 0037)"
"$ROOT/scripts/build-notifier.sh" "$APP"

say "7b/8 symlinks relativos (o bundle tem de sobreviver a ser copiado)"
# O runtime escreve links ABSOLUTOS do data/app para o código preparado, o que
# aponta para o diretório de build e quebra qualquer cópia do app. Depois do
# preseed, todo link interno vira relativo.
"$ROOT/scripts/link-relativize.sh" "$APP"

say "7c/8 compactando (payload duplicado + compressão transparente do APFS)"
# Depois do preseed o container embutido é cópia do que já está instalado, e o
# que não muda em uso comprime ~45% sem mudar um byte do que o app lê.
"$ROOT/scripts/compact-app.sh" "$APP"

say "8/8 assinatura ad-hoc"
# Identidade estável quando existe no chaveiro (scripts/sign-identity.sh): o macOS
# mantém as permissões do app entre builds; senão ad-hoc.
codesign --force --sign "$("$ROOT/scripts/sign-identity.sh")" "$APP" 2>&1 | tail -2
# Sem --deep: o bundle carrega o Instagram instalado (classes.jar, libs
# traduzidas, data/) -- artefatos gerados, não código do bundle. O selo que
# importa é o externo; verificar --deep aqui acusa os .dylib traduzidos como
# "file modified" e transforma o gate em ruído.
codesign --verify --strict "$APP" && echo "   assinatura ok"

say "pronto: $APP ($(du -sh "$APP" | cut -f1))"
echo "open \"$APP\""
