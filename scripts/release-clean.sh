#!/usr/bin/env bash
# release-clean.sh <Instamac.app> -- deixa um app montado pronto para distribuir: tira o que o
# preseed criou e é de UMA instalação (android_id, INSTALLATION, preferências, bancos, telemetria,
# caches de GPU, índice de mídia, caminhos com o usuário de quem compilou) e mantém o trabalho
# caro e igual para todos (código traduzido, libs, módulos, recursos baixados). Sem isso, todos
# que baixassem o DMG teriam o mesmo identificador de aparelho. Rodar com o app fechado.
set -euo pipefail
APP="${1:?uso: release-clean.sh <Instamac.app>}"
A="$APP/Contents/android"
[ -d "$A/data/data" ] || { echo "erro: $A/data/data não existe" >&2; exit 1; }

# Permissões mexidas só no que sai: lib-compressed (0555) e os módulos (0444) ficam como estão.
gone() { chmod -R u+w "$@" 2>/dev/null || true; rm -rf "$@"; }
chmod u+w "$A/data/data" "$A/data/data"/*/ 2>/dev/null || true
gone "$A/data/data/.macapk-settings" "$A/data/data/.macapk-media" "$A/data/data/.windowtraits" \
       "$A/data/data/.angle_blob" "$A/data/data/.gles31cache"
for d in "$A/data/system" "$A/data/user_de"; do for e in "$d"/* "$d"/.[!.]*; do [ -e "$e" ] && gone "$e"; done; done
rm -f "$A/.macapk/runtime_env" "$A/.macapk/ui_scale" "$A/.macapk/restart_none"
# Primeira abertura no modo Celular (sem o arquivo, o runtime abre no Tablet).
mkdir -p "$A/.macapk/window_pref"
for P in "$A"/data/data/*/; do
  pkg="$(basename "$P")"; echo portrait > "$A/.macapk/window_pref/${pkg%%_[0-9]*}"
done

for P in "$A"/data/data/*/; do
  P="${P%/}"
  for e in "$P"/* "$P"/.[!.]*; do
    [ -e "$e" ] || [ -L "$e" ] || continue
    case "$(basename "$e")" in
      lib-compressed|modules|app_restricks|app_strings|app_overtheair|.x18cache|icon.png|meta.json) ;;
      cache) [ -L "$e" ] || for c in "$e"/* "$e"/.[!.]*; do [ -e "$c" ] && gone "$c"; done ;;
      *) gone "$e" ;;
    esac
  done
done

# Caminhos neutros (/Applications): o runtime regrava meta.json e .shimdir com o lugar real ao
# abrir; o carimbo do ícone é cache (sem ele, o ícone é refeito uma vez).
apk="$(cd "$A/data/app" && ls -d */*/base.apk | head -1)"
for m in "$A"/data/data/*/meta.json "$A"/.macapk/code/*/meta.json; do
  [ -f "$m" ] || continue
  python3 - "$m" "/Applications/Instamac.app/Contents/android/data/app/$apk" <<'PY'
import json, sys
p, apk = sys.argv[1], sys.argv[2]
d = json.load(open(p))
d["apkPath"] = d["installedApk"] = apk
json.dump(d, open(p, "w"), indent=2)
PY
done
rm -f "$A"/.macapk/code/*/.macapk-icon-stamp
for s in "$A"/data/app/*/*/lib/.macapk-elfexec/*/.shimdir; do
  [ -f "$s" ] && echo "/Applications/Instamac.app/Contents/Resources/runtime/bin" > "$s"
done

# Nada com o caminho de quem compilou (nome de usuário) pode sobrar no bundle.
left="$(grep -rlI "$HOME" "$A" 2>/dev/null | head -5 || true)"
[ -z "$left" ] || { echo "erro: caminho pessoal em:" >&2; echo "$left" >&2; exit 1; }
echo "ok: $APP limpo para distribuir"
