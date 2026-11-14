#!/usr/bin/env bash
# Reescreve symlinks ABSOLUTOS de dentro do bundle como relativos.
#
#   scripts/link-relativize.sh build/Instamac.app
#
# O runtime cria `data/app/<pkg>/lib/arm64/*.dylib` apontando, em caminho
# absoluto, para `Contents/android/.macapk/code/<pkg>_<ver>/lib_native/*.dylib`.
# Absoluto funciona enquanto o bundle está onde foi gerado -- e quebra no
# instante em que ele é copiado (ditto, DMG, arrastar para Applications), porque
# o link continua mirando o diretório de build. Além disso o codesign trata
# destino absoluto fora do destino final como "invalid destination for symbolic
# link in bundle".
#
# A regra: link absoluto que aponta para dentro do bundle vira relativo; link
# que aponta para fora é reportado (não silenciado).
set -euo pipefail

APP="${1:?uso: scripts/link-relativize.sh <App.app>}"
ROOT="$(cd "$APP" && pwd -P)"
changed=0
outside=0

relative_to() {
  local link="$1" target="$2"
  python3 - "$link" "$target" <<'PY'
import os, sys
link, target = sys.argv[1], sys.argv[2]
print(os.path.relpath(target, os.path.dirname(link)))
PY
}

while IFS= read -r -d '' l; do
  t="$(readlink "$l")"
  case "$t" in
    /*)
      if [[ "$t" == "$ROOT/"* ]]; then
        ln -sfn "$(relative_to "$l" "$t")" "$l"
        changed=$((changed + 1))
      elif [[ "$t" == *"/Contents/"* ]] \
           && [[ -e "$ROOT/Contents/${t#*/Contents/}" ]]; then
        # Link de um bundle ANTERIOR (ex.: /Applications/... copiado para o
        # build): o destino existe aqui com o mesmo sufixo depois de Contents/.
        ln -sfn "$(relative_to "$l" "$ROOT/Contents/${t#*/Contents/}")" "$l"
        changed=$((changed + 1))
      else
        printf 'aviso: link aponta para fora do bundle: %s -> %s\n' "$l" "$t" >&2
        outside=$((outside + 1))
      fi
      ;;
  esac
done < <(find "$ROOT" -type l -print0)

printf '   symlinks relativizados: %d%s\n' "$changed" \
  "$([ "$outside" -gt 0 ] && printf ' (%d apontam para fora)' "$outside" || true)"
