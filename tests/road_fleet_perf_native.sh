#!/usr/bin/env bash
# Native worker benchmark against the actual baseline road update.
set -euo pipefail
cd "$(dirname "$0")/.."
[[ $# == 3 ]] || { echo "usage: $0 LUANTI_SERVER BASELINE_GIT_REV NEW_OUTPUT_DIRECTORY" >&2;exit 64; }
server=$1
if [[ "$server" == */* ]]; then server=$(realpath "$server"); fi
baseline=$2
mkdir "$3"
out=$(realpath "$3")
game="$out/games/fleetbench"
mod="$game/mods/luanttd_core"
mkdir -p "$mod" "$out/world" "$out/home"
printf 'title = Native road fleet benchmark\n' > "$game/game.conf"
printf 'name = luanttd_core\n' > "$mod/mod.conf"
cp mods/luanttd_core/*.lua "$mod/"
cp -a mods/luanttd_core/openttd "$mod/"
cp tests/road_fleet_perf_native.lua "$mod/init.lua"
cp tests/road_fleet_perf.lua "$mod/"
# Native async Lua does not have debug.getinfo: point baseline Sim at
# its two original modules without changing the normal nested loaders.
git show "$baseline:mods/luanttd_core/sim.lua" | sed -e 's/"road_speed_runtime.lua"/"baseline_speed.lua"/' -e 's/"road_junction_guard.lua"/"baseline_junction.lua"/' > "$mod/baseline_sim.lua"
git show "$baseline:mods/luanttd_core/road_speed_runtime.lua" > "$mod/baseline_speed.lua"
git show "$baseline:mods/luanttd_core/road_junction_guard.lua" > "$mod/baseline_junction.lua"
for variant in baseline current; do
  input="$mod/sim.lua"
  if [[ "$variant" == baseline ]]; then input="$mod/baseline_sim.lua"; fi
  sed '/^local function road_shape(s,id,t)$/a\  M.perf_road_shape_calls=(M.perf_road_shape_calls or 0)+1' "$input" > "$mod/profile_${variant}_sim.lua"
done
printf 'gameid = fleetbench\nbackend = sqlite3\nmod_storage_backend = sqlite3\nplayer_backend = sqlite3\nauth_backend = sqlite3\n' > "$out/world/world.mt"
port=${BAYLINE_NATIVE_PORT:-43042}
printf 'port = %s\nprometheus_listener_address = 127.0.0.1:%s\nserver_announce = false\nbind_address = 127.0.0.1\n' "$port" "$port" > "$out/server.conf"
export HOME="$out/home" LUANTI_GAME_PATH="$out/games" MINETEST_GAME_PATH="$out/games"
if ! timeout 90 "$server" --config "$out/server.conf" --world "$out/world" --gameid fleetbench --logfile '' >"$out/server.log" 2>&1; then
  cat "$out/server.log";exit 1
fi
grep "NATIVE ROAD FLEET BENCH" "$out/server.log"
! grep -E 'ERROR\[' "$out/server.log"
