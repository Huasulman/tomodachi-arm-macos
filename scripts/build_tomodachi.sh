#!/bin/zsh
# Uso | usage: scripts/build_tomodachi.sh <juego.nsp> <prod.keys>
# Extrae el juego, reescribe su código, traduce los shaders, compila el host y crea la app en /Applications.
# Extracts the game, rewrites its code, translates the shaders, builds the host and creates the app in /Applications.
# El .nsp (juego base v0) y prod.keys tienen que salir de tu propia consola; nunca van en el repo.
# The .nsp (base game v0) and prod.keys must come from your own console; they never go in the repository.
set -euo pipefail

NSP=${1:?Falta la ruta al NSP del juego base (v0) | missing path to the base game NSP (v0)}
KEYS=${2:?Falta la ruta a prod.keys | missing path to prod.keys}
REPO=${0:A:h:h}

# Entorno de Python: $TOMODACHI_VENV, .venv del repo o .venv de la carpeta de arriba
# Python env: $TOMODACHI_VENV, the repo's .venv or a .venv one folder up
VENV=${TOMODACHI_VENV:-}
[ -z "$VENV" ] && [ -d "$REPO/.venv" ] && VENV=$REPO/.venv
[ -z "$VENV" ] && [ -d "$REPO/../.venv" ] && VENV=${REPO:h}/.venv
[ -n "$VENV" ] && export PATH="$VENV/bin:$PATH"
export PATH="/opt/homebrew/bin:$PATH"
export DOTNET_ROOT=${DOTNET_ROOT:-/opt/homebrew/opt/dotnet/libexec}
G=010051F0207B2000; W=~/$G-work; VER=v0

xcrun -sdk macosx metal --version >/dev/null 2>&1 || { echo "Falta el compilador de Metal: instala Xcode y ejecuta 'sudo xcode-select -s /Applications/Xcode.app'"; exit 1; }
cd "$REPO"

echo "== 1. Extraer el NSP"
[ -x $W/build/nx_extract/nx_extract ] || dotnet build dm/tools/nx_extract -c Release -o $W/build/nx_extract
[ -d $W/data/$VER/RomFS ] || $W/build/nx_extract/nx_extract "$KEYS" "$NSP" - $W/data/$VER

echo "== 2. Reescribir los módulos de código"
for m in $(python3 dm/games/game.py $G modules); do
  DM_RULESET=native python3 dm/tools/patch_nso.py $W/data/$VER/ExeFS/$m $W/build/patched_$VER $m
done

echo "== 3. Shaders (tarda bastante la primera vez)"
DM_GAME=$G python3 dm/gfx/tools/shader_split.py $W/data/v0/RomFS $W/data/v0/ExeFS/main $W/shader/pkg \
  dm/games/$G/shader_map.tsv dm/games/$G/shader_facts.tsv dm/games/$G/shader_pairs.tsv
DM_GAME=$G python3 dm/gfx/tools/dmsh_chain.py --header
DM_GAME=$G python3 dm/gfx/tools/dmsh_build.py $W/shader/pkg $W/build/cache/metal_shader_cache
CHAIN=$(ls -d $W/build/cache/metal_shader_cache/b-* | head -1)
python3 dm/gfx/tools/c1_guard.py $CHAIN dm/games/$G/c1_full.tsv

echo "== 4. Host y fuente"
make -C dm/host GAME=$G dmhost
mkdir -p $W/build/font && python3 dm/tools/make_ext_font.py $W/build/font/nintendo_ext.ttf

echo "== 5. Crear la app"
python3 scripts/build_mac_app.py $G -w $W -o "/Applications/Tomodachi Life.app" --embed
echo "Listo: abre 'Tomodachi Life' desde Aplicaciones."
