#!/usr/bin/env bash
# Headless Luanti differential for cold open sea, shoals, locks and spans.
set -euo pipefail
[[ $# == 2 ]] || { echo "usage: $0 LUANTI_SERVER NEW_OUTPUT_DIRECTORY" >&2; exit 64; }
server=$1
if [[ "$server" == */* ]]; then server=$(realpath "$server");fi
mkdir "$2"
o=$(realpath "$2")
cd "$(dirname "$0")/.."
g="$o/games/shiptide";m="$g/mods/luanttd_core"
mkdir -p "$m" "$o/home" "$o/world"
cp mods/luanttd_core/*.lua "$m/"
cp -a mods/luanttd_core/openttd "$m/"
cp tests/ship_solid_region_perf_native.lua "$m/init.lua"
printf 'title = Native ship regions tide probe\n' > "$g/game.conf"
printf 'name = luanttd_core\n' > "$m/mod.conf"
printf 'gameid = shiptide\nbackend = sqlite3\n' > "$o/world/world.mt"
printf 'port = %s\nbind_address = 127.0.0.1\nserver_announce = false\n' "${BAYLINE_NATIVE_PORT:-44406}" > "$o/conf"
export HOME="$o/home" LUANTI_GAME_PATH="$o/games" MINETEST_GAME_PATH="$o/games"
timeout 120 "$server" --world "$o/world" --config "$o/conf" --gameid shiptide --logfile '' > "$o/log" 2>&1 || { tail -40 "$o/log";exit 1; }
test "$(grep -c 'NATIVE SOLID SEA REGIONS' "$o/log")" = 4
grep -E 'NATIVE (SOLID SEA REGIONS|FIRST FERRY ROUTE)' "$o/log"
! grep -q 'ERROR\[' "$o/log"
