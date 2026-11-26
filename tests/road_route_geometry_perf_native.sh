#!/usr/bin/env bash
# Compare bought, routed fleets against a specific pre-cache Git revision.
set -euo pipefail
[[ $# == 3 ]] || { echo "usage: $0 LUANTI_SERVER BASELINE_GIT_REV NEW_OUTPUT_DIRECTORY" >&2; exit 64; }
server=$1
if [[ "$server" == */* ]]; then server=$(realpath "$server"); fi
base=$2
mkdir "$3"
out=$(realpath "$3")
cd "$(dirname "$0")/.."
mod="$out/games/roadshare/mods/luanttd_core"
mkdir -p "$mod" "$out/home" "$out/world"
printf 'title = Road route geometry comparison\n' > "$out/games/roadshare/game.conf"
printf 'name = luanttd_core\n' > "$mod/mod.conf"
cp mods/luanttd_core/*.lua "$mod/"
cp -a mods/luanttd_core/openttd "$mod/"
cp tests/road_fleet_perf.lua "$mod/"
cp tests/road_route_geometry_perf_native.lua "$mod/init.lua"
sed 's|"/sim.lua"|"/baseline_sim.lua"|' "$mod/road_fleet_perf.lua" > "$mod/baseline_fleet.lua"
git show "$base:mods/luanttd_core/sim.lua" | sed 's/"road_yapf_route.lua"/"baseline_road_route.lua"/' > "$mod/baseline_sim.lua"
git show "$base:mods/luanttd_core/road_yapf_route.lua" > "$mod/baseline_road_route.lua"
printf 'port = %s\nbind_address = 127.0.0.1\nserver_announce = false\n' "${BAYLINE_NATIVE_PORT:-44049}" > "$out/conf"
printf 'gameid = roadshare\nbackend = sqlite3\nmod_storage_backend = sqlite3\nplayer_backend = sqlite3\nauth_backend = sqlite3\n' > "$out/world/world.mt"
export HOME="$out/home" MINETEST_GAME_PATH="$out/games" LUANTI_GAME_PATH="$out/games"
timeout 130 "$server" --world "$out/world" --config "$out/conf" --gameid roadshare --logfile '' > "$out/log" 2>&1 ||
  { tail -50 "$out/log"; exit 1; }
grep 'ROUTE_SHARE' "$out/log"
! grep -E 'ERROR\[' "$out/log"
