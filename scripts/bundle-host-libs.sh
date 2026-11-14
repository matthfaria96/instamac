#!/usr/bin/env bash
# bundle-host-libs.sh <app> -- traz para dentro do app toda biblioteca que um
# binário do bundle carrega de fora do sistema (/opt/homebrew, /usr/local) e
# reaponta as referências para @loader_path: o app abre num Mac sem Homebrew.
#
# As cópias vão para Contents/Resources/runtime/lib-host/. Cada binário alterado
# é reassinado ad-hoc preservando entitlements e flags (o runtime precisa das
# de JIT/x18; o runtime aceita as cópias porque tem disable-library-validation).
# Idempotente: rodar de novo não muda nada. O app deve estar fechado.
set -euo pipefail
APP="${1:?uso: bundle-host-libs.sh <app>}"
RT="$APP/Contents/Resources/runtime"
DEST="$RT/lib-host"
[ -d "$RT" ] || { echo "erro: $RT não existe" >&2; exit 1; }
pgrep -f "$RT/Resources/macapk-runtime" >/dev/null && { echo "erro: o app está aberto" >&2; exit 1; }
mkdir -p "$DEST"

external_deps() {   # dependências fora do sistema de um Mach-O
    otool -L "$1" 2>/dev/null | awk 'NR>1 {print $1}' | grep -E '^(/opt/homebrew|/usr/local)/' || true
}
relpath() { python3 -c 'import os,sys; print(os.path.relpath(sys.argv[1], sys.argv[2]))' "$1" "$2"; }
SIGN_ID="$("$(cd "$(dirname "$0")" && pwd)/sign-identity.sh")"
resign() {
    codesign --force --sign "$SIGN_ID" --preserve-metadata=identifier,entitlements,flags,runtime "$1" 2>/dev/null \
        || codesign --force --sign "$SIGN_ID" "$1"
}

changed=1 copied=0 rewired=0
while [ "$changed" -eq 1 ]; do
    changed=0
    while IFS= read -r -d '' f; do
        file -b "$f" | grep -q 'Mach-O' || continue
        deps="$(external_deps "$f")"
        [ -n "$deps" ] || continue
        while IFS= read -r dep; do
            name="$(basename "$dep")"
            if [ ! -f "$DEST/$name" ]; then
                cp "$(python3 -c 'import os,sys; print(os.path.realpath(sys.argv[1]))' "$dep")" "$DEST/$name"
                chmod u+w "$DEST/$name"
                install_name_tool -id "@loader_path/$name" "$DEST/$name" 2>/dev/null
                resign "$DEST/$name"
                copied=$((copied + 1))
            fi
            rel="$(relpath "$DEST" "$(dirname "$f")")"
            chmod u+w "$f"
            install_name_tool -change "$dep" "@loader_path/$rel/$name" "$f" 2>/dev/null
            rewired=$((rewired + 1))
            changed=1
        done <<< "$deps"
        resign "$f"
    done < <(find "$APP/Contents" -type f \( -name '*.dylib' -o -name '*.so' -o -perm -u+x \) -not -path "*/jre/*" -print0)
done

left="$(find "$APP/Contents" -type f \( -name '*.dylib' -o -name '*.so' -o -perm -u+x \) -print0 \
        | xargs -0 -n1 sh -c 'otool -L "$0" 2>/dev/null | awk "NR>1 {print \$1}" | grep -E "^(/opt/homebrew|/usr/local)/" | sed "s|^|$0: |"' 2>/dev/null || true)"
[ -z "$left" ] || { echo "erro: ainda há dependências de fora:" >&2; echo "$left" >&2; exit 1; }
echo "ok: $copied biblioteca(s) trazida(s) para $DEST, $rewired referência(s) reapontada(s); nada fora do sistema"
