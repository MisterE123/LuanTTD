#!/usr/bin/env bash
# Headless native comparison against the previous full-industry scan.
set -euo pipefail
[[ $# == 3 ]] || { echo "usage: $0 LUANTI_SERVER BASELINE_GIT_REV NEW_OUTPUT_DIRECTORY" >&2; exit 64; }
server=$1
if [[ "$server" == */* ]]; then server=$(realpath "$server"); fi
base=$2
mkdir "$3"
out=$(realpath "$3")
cd "$(dirname "$0")/.."
game="$out/games/freightbench"
mod="$game/mods/luanttd_core"
mkdir -p "$mod" "$out/world" "$out/home"
cp mods/luanttd_core/*.lua "$mod/"
cp -a mods/luanttd_core/openttd "$mod/"
cp tests/freight_catchment_perf_native.lua "$mod/init.lua"
git show "$base:mods/luanttd_core/timber_industry_runtime.lua" > "$mod/baseline_industry.lua"
git show "$base:mods/luanttd_core/road_farm_service.lua" > "$mod/baseline_road.lua"
printf 'title = Native freight catchment benchmark\n' > "$game/game.conf"
printf 'name = luanttd_core\n' > "$mod/mod.conf"
printf 'gameid = freightbench\nbackend = sqlite3\nplayer_backend = sqlite3\nauth_backend = sqlite3\nmod_storage_backend = sqlite3\n' > "$out/world/world.mt"
printf 'port = %s\nbind_address = 127.0.0.1\nserver_announce = false\n' "${BAYLINE_NATIVE_PORT:-44429}" > "$out/conf"
export HOME="$out/home" LUANTI_GAME_PATH="$out/games" MINETEST_GAME_PATH="$out/games"
timeout 60 "$server" --world "$out/world" --config "$out/conf" --gameid freightbench --logfile '' > "$out/log" 2>&1 ||
  { tail -40 "$out/log"; exit 1; }
test "$(grep -c 'NATIVE FREIGHT CATCHMENT' "$out/log")" = 4
grep 'NATIVE FREIGHT CATCHMENT' "$out/log"
! grep -q 'ERROR\[' "$out/log"
