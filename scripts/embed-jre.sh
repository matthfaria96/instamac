#!/usr/bin/env bash
# embed-jre.sh <app> <runtime-binary> <jre-dir> <patch-lib-dir>
#
# Puts a JDK 25 runtime into an Instamac bundle without anything from Homebrew in
# the JVM path:
#   - <jre-dir> (vendor/macapk/scripts/stage_jre.sh, patches baked in) goes to
#     Contents/Resources/runtime/Resources/jre;
#   - <runtime-binary> (built against JDK 25) replaces macapk-runtime, its libjvm /
#     libjli load commands rewritten to @executable_path/jre/... and re-signed WITH
#     the JIT/x18 entitlements (a plain `codesign --force` drops them and the boot
#     dies in [x18] FATAL);
#   - <patch-lib-dir>/{java_base_patch,jdk_unsupported_patch} replace the JDK 21
#     ones: the runtime drops --patch-module only when these match the digests
#     baked into the image (lib/macapk-baked-patches), which is what lets the AOT
#     cache map.
# <jre-dir> or <patch-lib-dir> "-" keeps what the bundle already has (a new
# runtime binary only). The app must be closed. Data is not touched.
set -euo pipefail
APP="${1:?uso: embed-jre.sh <app> <runtime-binary> <jre-dir> <patch-lib-dir>}"
BIN="${2:?}"
JRE="${3:?}"
PATCHES="${4:?}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ENT="$ROOT/vendor/macapk/runtime/scripts/jit-entitlements.plist"
RT="$APP/Contents/Resources/runtime"

if [ "$JRE" != - ]; then
    [ -x "$JRE/bin/java" ] || { echo "erro: $JRE não é uma JRE" >&2; exit 1; }
    [ -f "$JRE/lib/macapk-baked-patches" ] || echo "aviso: $JRE sem correções assadas; o cache AOT ficará desligado" >&2
else
    [ -x "$RT/Resources/jre/bin/java" ] || { echo "erro: o bundle não tem JRE embutida" >&2; exit 1; }
fi
pgrep -f "$RT/Resources/macapk-runtime" >/dev/null && { echo "erro: o app está aberto" >&2; exit 1; }

chmod -R u+w "$RT"
if [ "$JRE" != - ]; then
    rm -rf "$RT/Resources/jre"
    ditto "$JRE" "$RT/Resources/jre"
fi

jvm_old="$(otool -L "$BIN" | awk '/libjvm.dylib/ {print $1}')"
jli_old="$(otool -L "$BIN" | awk '/libjli.dylib/ {print $1}')"
cp "$BIN" "$RT/Resources/macapk-runtime"
install_name_tool \
    -change "$jvm_old" "@executable_path/jre/lib/server/libjvm.dylib" \
    -change "$jli_old" "@executable_path/jre/lib/libjli.dylib" \
    "$RT/Resources/macapk-runtime" 2>/dev/null
SIGN_ID="$("$ROOT/scripts/sign-identity.sh")"
codesign --force -s "$SIGN_ID" --options runtime --identifier dev.instamac.runtime \
    --entitlements "$ENT" "$RT/Resources/macapk-runtime" 2>/dev/null

if [ "$PATCHES" != - ]; then
    for d in java_base_patch jdk_unsupported_patch; do
        rm -rf "$RT/lib/$d"
        ditto "$PATCHES/$d" "$RT/lib/$d"
    done
fi

otool -L "$RT/Resources/macapk-runtime" | grep -q "@executable_path/jre/lib/server/libjvm.dylib" \
    || { echo "erro: libjvm não foi reapontada" >&2; exit 1; }
codesign -d --entitlements - "$RT/Resources/macapk-runtime" 2>&1 | grep -q "allow-jit" \
    || { echo "erro: entitlements perdidas" >&2; exit 1; }
echo "   assinatura: $SIGN_ID"
echo "ok: JRE $("$RT/Resources/jre/bin/java" -version 2>&1 | head -1 | awk '{print $3}') em $RT/Resources/jre ($(du -sh "$RT/Resources/jre" | cut -f1))"
