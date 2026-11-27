#!/usr/bin/env bash
set -euo pipefail
if [[ $# != 2 ]]; then echo "usage: $0 LUANTI_SERVER NEW_OUTPUT_DIR" >&2; exit 64; fi
server=$1
if [[ "$server" == */* ]]; then server=$(realpath "$server"); fi
mkdir "$2"
out=$(realpath "$2")
cd "$(dirname "$0")/.."
game="$out/games/municipalroad"
mod="$game/mods/luanttd_core"
mkdir -p "$mod" "$out/world" "$out/home"
printf 'title = Native Municipal Road Growth\n' > "$game/game.conf"
printf 'name = luanttd_core\n' > "$mod/mod.conf"
# Only simulation scripts are needed; the fixture checks the 3D-coordinate
# projection rather than loading all game textures or meshes.
if ! cp -l mods/luanttd_core/*.lua "$mod/" 2>/dev/null; then cp mods/luanttd_core/*.lua "$mod/"; fi
if ! cp -al mods/luanttd_core/openttd "$mod/" 2>/dev/null; then cp -a mods/luanttd_core/openttd "$mod/"; fi
rm "$mod/init.lua"
fixture=tests/town_municipal_roads_native.lua
if [[ ${LUANTTD_QA_MUNICIPAL_KIND:-} == months ]]; then fixture=tests/town_monthly_worker_native.lua; fi
cp "$fixture" "$mod/init.lua"
printf 'gameid = municipalroad\nbackend = sqlite3\nplayer_backend = sqlite3\nauth_backend = sqlite3\nmod_storage_backend = sqlite3\n' > "$out/world/world.mt"
port=$(printenv BAYLINE_NATIVE_PORT || printf '44583')
mode=$(printenv LUANTTD_QA_MUNICIPAL_KIND || printf 'road')
printf 'port = %s\nserver_announce = false\nbind_address = 127.0.0.1\ndedicated_server_step = .025\n' "$port" > "$out/server.conf"
printf 'luanttd_qa_municipal_kind = %s\n' "$mode" >> "$out/server.conf"
export HOME="$out/home" LUANTI_GAME_PATH="$out/games" MINETEST_GAME_PATH="$out/games"
if ! timeout 35 "$server" --config "$out/server.conf" --world "$out/world" --gameid municipalroad --logfile '' > "$out/server.log" 2>&1; then
  tail -60 "$out/server.log"; exit 1
fi
grep 'PASS NATIVE MUNICIPAL ROADS' "$out/server.log"
! grep -E 'ERROR\[' "$out/server.log"
