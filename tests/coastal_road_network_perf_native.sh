#!/usr/bin/env bash
# Compare real paid vehicle motion during unrelated stock coastal changes.
set -euo pipefail
[[ $# == 3 ]] || { echo "usage: $0 LUANTI_SERVER BASELINE_GIT_REV NEW_OUTPUT_DIRECTORY" >&2; exit 64; }
server=$1
if [[ "$server" == */* ]]; then server=$(realpath "$server"); fi
base=$2
mkdir "$3"
o=$(realpath "$3")
cd "$(dirname "$0")/.."
g="$o/games/coastnet"; m="$g/mods/luanttd_core"
mkdir -p "$m" "$o/world" "$o/home"
cp mods/luanttd_core/*.lua "$m/"
cp -a mods/luanttd_core/openttd "$m/"
cp tests/coastal_road_network_perf_native.lua "$m/init.lua"
cp tests/road_fleet_perf.lua "$m/"
git show "$base:mods/luanttd_core/sim.lua" | sed \
  -e 's/"road_junction_guard.lua"/"baseline_junction.lua"/' \
  -e 's/"water_flood_world.lua"/"baseline_flood.lua"/' > "$m/baseline_sim.lua"
git show "$base:mods/luanttd_core/road_junction_guard.lua" > "$m/baseline_junction.lua"
git show "$base:mods/luanttd_core/water_flood_world.lua" > "$m/baseline_flood.lua"
printf 'title = Coastal Road Test\n' > "$g/game.conf"
printf 'name = luanttd_core\n' > "$m/mod.conf"
printf 'gameid = coastnet\nbackend = sqlite3\nmod_storage_backend = sqlite3\nplayer_backend = sqlite3\nauth_backend = sqlite3\n' > "$o/world/world.mt"
printf 'port = %s\nbind_address = 127.0.0.1\nserver_announce = false\n' "${BAYLINE_NATIVE_PORT:-44384}" > "$o/conf"
export HOME="$o/home" LUANTI_GAME_PATH="$o/games" MINETEST_GAME_PATH="$o/games"
timeout 150 "$server" --world "$o/world" --config "$o/conf" --gameid coastnet --logfile '' >"$o/log" 2>&1 ||
  { tail -40 "$o/log";exit 1; }
test "$(grep -c 'COASTAL NETWORK' "$o/log")" = 8
grep 'COASTAL NETWORK' "$o/log"
! grep -q 'ERROR\[' "$o/log"
