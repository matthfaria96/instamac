#!/usr/bin/env bash
# runtime-patch.sh apply|export -- as mudanças do Instamac no runtime (vendor/macapk) num patch só.
#
#   apply   aplica contrib/upstream/runtime.patch ao submódulo limpo (commit fixado); é o
#           primeiro passo depois de `git submodule update --init`.
#   export  regrava o patch a partir do submódulo atual (rode depois de mexer no runtime).
#
# Os patches numerados em contrib/upstream/patches/ são as mesmas mudanças separadas por
# assunto, para propor ao upstream; este é o que o build usa.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
V="$ROOT/vendor/macapk"
PATCH="$ROOT/contrib/upstream/runtime.patch"
case "${1:-}" in
  apply)
    git -C "$V" apply --whitespace=nowarn "$PATCH"
    echo "ok: runtime com as mudanças do Instamac" ;;
  export)
    {
      git -C "$V" diff --binary
      # arquivos novos (fora dos diretórios de build do cmake)
      git -C "$V" ls-files --others --exclude-standard \
        | grep -vE '^runtime/(build[^/]*|translator/build)/' \
        | while IFS= read -r f; do
            git -C "$V" diff --no-index --binary -- /dev/null "$f" || true
          done
    } > "$PATCH"
    echo "ok: $PATCH ($(du -h "$PATCH" | cut -f1))" ;;
  *) echo "uso: scripts/runtime-patch.sh apply|export" >&2; exit 2 ;;
esac
