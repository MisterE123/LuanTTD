#!/usr/bin/env bash
# Native worker replay of gradual loads and full-load reservations.
set -euo pipefail
cd "$(dirname "$0")/.."
[[ $# == 3 ]] || { echo "usage: $0 LUANTI_SERVER BASELINE_GIT_REV NEW_OUTPUT_DIRECTORY" >&2;exit 64; }
server=$1
if [[ "$server" == */* ]]; then server=$(realpath "$server"); fi
mkdir "$3"
out=$(realpath "$3")
game="$out/games/cargobench"
m="$game/mods/bench"
mkdir -p "$m/openttd" "$out/home" "$out/world"
cp tests/cargo_queue_perf_native.lua "$m/init.lua"
cp mods/luanttd_core/road_loading_runtime.lua "$m/"
cp mods/luanttd_core/openttd/{loading_timing,passengers}.lua "$m/openttd/"
git show "$2:mods/luanttd_core/road_loading_runtime.lua" >"$m/baseline.lua"
echo 'title = Cargo queue benchmark' >"$game/game.conf"
echo 'name = bench' >"$m/mod.conf"
printf 'gameid = cargobench\nbackend = sqlite3\nplayer_backend = sqlite3\nauth_backend = sqlite3\nmod_storage_backend = sqlite3\n' >"$out/world/world.mt"
export HOME="$out/home" LUANTI_GAME_PATH="$out/games" MINETEST_GAME_PATH="$out/games"
printf 'port = %s\nbind_address = 127.0.0.1\nserver_announce = false\n' "${BAYLINE_NATIVE_PORT:-44411}" >"$out/conf"
timeout 100 "$server" --world "$out/world" --config "$out/conf" --gameid cargobench --logfile '' >"$out/log" 2>&1 || {
  tail -75 "$out/log"; exit 1;
}
grep 'CARGO QUEUE PROFILE' "$out/log"
! grep -F 'ERROR[' "$out/log"
