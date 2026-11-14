#!/bin/bash
# compact-app.sh <Instamac.app> -- encolhe o bundle sem tirar nada que o app usa.
#
#   1. Remove o container embutido (Contents/app/embedded/*.xapk) quando o
#      Instagram já está instalado: ele é cópia byte a byte de
#      android/data/app/**/base.apk (+ split), e o launcher abre pelo instalado
#      quando não há container. Medido: -264 MB.
#   2. Compressão transparente do APFS (decmpfs) nas partes que não mudam em uso:
#      runtime, classes.jar, lib_native, apks instalados, lib-compressed. Quem lê
#      recebe os mesmos bytes (o kernel descomprime), então assinatura, mtime e a
#      identidade gravada em .installed ficam iguais. Medido: 454->254 MB
#      (classes.jar), 127->63 (lib_native), 256->160 (base.apk), 164->118 (runtime).
#
#   3. Remove a JRE embutida quando o runtime não a usa: o `macapk-runtime`
#      compilado aqui liga a `libjvm` do Homebrew (caminho absoluto fora do
#      bundle), e nenhum arquivo de Resources/runtime/Resources/jre é aberto em
#      uso (medido com lsof). Se o binário ligar a JRE de dentro do bundle, ela
#      fica. Medido: -43 MB em disco.
#
# Medido também: `--zlibCompressionLevel 9` não ganha nada sobre o padrão do
# ditto (classes.jar 239 -> 252 MB, base.apk 155 -> 161), então fica o padrão.
#
# Idempotente. Roda no fim do build (antes de assinar) e pode rodar no app
# instalado, fechado. COMPACT_KEEP_PAYLOAD=1 mantém o container embutido;
# COMPACT_KEEP_JRE=1 mantém a JRE.
set -euo pipefail
APP="${1:?uso: compact-app.sh <Instamac.app>}"
C="$APP/Contents"
[ -d "$C/android" ] || { echo "erro: $APP não tem Contents/android" >&2; exit 1; }
if pgrep -f "$C/Resources/runtime/Resources/macapk-runtime" >/dev/null 2>&1; then
  echo "erro: o app está aberto; feche antes de compactar" >&2; exit 1
fi

size_mb() { du -sm "$1" 2>/dev/null | cut -f1; }
before=$(size_mb "$APP")

if [ "${COMPACT_KEEP_PAYLOAD:-0}" != "1" ]; then
  installed=$(ls "$C"/android/data/app/*/*/base.apk 2>/dev/null | head -1 || true)
  converted=$(ls "$C"/android/.macapk/code/*/classes.jar 2>/dev/null | head -1 || true)
  if [ -n "$installed" ] && [ -n "$converted" ] && [ -d "$C/app/embedded" ]; then
    for f in "$C"/app/embedded/*; do
      [ -e "$f" ] || continue
      echo "   - $(basename "$f") (duplicata do instalado, $(size_mb "$f") MB)"
      rm -f "$f"
    done
  fi
fi

# Copia comprimindo e troca no lugar; modos e datas vêm da origem (lib-compressed
# é 0555: só o original precisa de u+w, para poder ser removido).
compress_in_place() {
  local p="$1" tmp="$1.compact.$$" a b
  [ -e "$p" ] || return 0
  a=$(size_mb "$p")
  rm -rf "$tmp"
  ditto --noclone --hfsCompression "$p" "$tmp"
  chmod -R u+w "$p" 2>/dev/null || true
  rm -rf "$p"
  mv "$tmp" "$p"
  b=$(size_mb "$p")
  printf '   %4s -> %4s MB  %s\n' "$a" "$b" "${p#"$C"/}"
}

JRE="$C/Resources/runtime/Resources/jre"
RT_BIN="$C/Resources/runtime/Resources/macapk-runtime"
if [ "${COMPACT_KEEP_JRE:-0}" != "1" ] && [ -d "$JRE" ] && [ -x "$RT_BIN" ]; then
  jvm="$(otool -L "$RT_BIN" 2>/dev/null | awk '/libjvm\.dylib/ {print $1; exit}')"
  case "$jvm" in
    /*) if [ -f "$jvm" ] && [ "${jvm#"$C"}" = "$jvm" ]; then
          echo "   - JRE embutida ($(size_mb "$JRE") MB): o runtime usa $jvm"
          rm -rf "$JRE"
        fi ;;
  esac
fi

compress_in_place "$C/Resources/runtime"
for d in "$C"/android/.macapk/code/*/; do
  compress_in_place "${d}classes.jar"
  compress_in_place "${d}lib_native"
done
for f in "$C"/android/data/app/*/*/*.apk; do compress_in_place "$f"; done
# Dados que o app grava uma vez e depois só lê (o que ele reescrever perde a
# compressão, sem outro efeito).
for d in "$C"/android/data/data/*/; do
  for sub in lib-compressed modules files app_restricks app_analytics; do
    compress_in_place "${d}${sub}"
  done
done

echo "   bundle: ${before} -> $(size_mb "$APP") MB"
