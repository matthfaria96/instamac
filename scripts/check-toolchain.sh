#!/usr/bin/env bash
# Verifica o que o Instamac precisa para compilar e testar.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RT="${INSTAMAC_RUNTIME:-$HOME/Library/Application Support/Mac.apk/runtime}"
JDK="${INSTAMAC_JDK:-/opt/homebrew/opt/openjdk@25}"
fail=0

say()  { printf '%s\n' "$*"; }
ok()   { printf '  ok    %s\n' "$*"; }
bad()  { printf '  FALTA %s\n' "$*"; fail=1; }

say "toolchain"
[ -x "$JDK/bin/javac" ] && ok "javac ($("$JDK/bin/javac" -version 2>&1))" \
  || bad "JDK 25 em $JDK (brew install openjdk@25, ou defina INSTAMAC_JDK)"
command -v cmake >/dev/null 2>&1 && ok "cmake ($(cmake --version | head -1))" \
  || bad "cmake (só necessário para rebuildar o runtime C++)"
[ -d "$ROOT/vendor/macapk/runtime/java/com/macapk/dex" ] && ok "vendor/macapk" \
  || bad "vendor/macapk (git submodule update --init --recursive)"

say "runtime do Mac.apk"
if [ -f "$RT/lib/macapk-loader.jar" ]; then
  ok "runtime em $RT"
  [ -x "$RT/Resources/jre/bin/java" ] && ok "JRE embutido" || bad "JRE embutido em $RT/Resources/jre"
else
  bad "runtime instalado (abra o Mac.apk e clique Install em Runtime:, ou rode macapk-installhelper runtime-install)"
fi

say "payload"
ls "$ROOT"/payload/*.xapk "$ROOT"/payload/*.apk >/dev/null 2>&1 && ok "APK/XAPK do Instagram em payload/" \
  || bad "payload/: coloque o seu APK ou XAPK do Instagram (não versionado)"

say ""
[ "$fail" -eq 0 ] && say "tudo pronto." || say "resolva os itens FALTA acima."
exit "$fail"
