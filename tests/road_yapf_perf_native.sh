#!/usr/bin/env bash
# Opt-in comparison on a disposable copy of a 128-bus campaign fixture.
set -euo pipefail
cd "$(dirname "$0")/.."
[[ $# == 4 ]] || { echo "usage: $0 LUANTI_SERVER BASELINE_REV 128_BUS_CHECKPOINT NEW_OUTPUT_DIRECTORY" >&2; exit 64; }
server=$1; if [[ $server == */* ]]; then server=$(realpath "$server");fi
base=$2
fixture=$(realpath "$3")
mkdir "$4"; d=$(realpath "$4")
g="$d/games/pathbench";m="$g/mods/luanttd_core"
mkdir -p "$m" "$d/home" "$d/world"
cp mods/luanttd_core/*.lua "$m/"
cp -a mods/luanttd_core/openttd "$m/"
for name in yapf_road_follow yapf_road_cost; do
  git show "$base:mods/luanttd_core/openttd/$name.lua" >"$m/openttd/old_$name.lua"
done
git show "$base:mods/luanttd_core/sim.lua" |
  sed -e 's@openttd/yapf_road_follow.lua@openttd/old_yapf_road_follow.lua@g' \
      -e 's@openttd/yapf_road_cost.lua@openttd/old_yapf_road_cost.lua@g' >"$m/baseline_sim.lua"
cp tests/road_yapf_perf_native.lua "$m/init.lua"
cp "$fixture" "$d/world/luanttd-wide-campaign.chk"
printf 'gameid = pathbench\nbackend = sqlite3\nplayer_backend = sqlite3\nauth_backend = sqlite3\nmod_storage_backend = sqlite3\n' >"$d/world/world.mt"
printf 'name = luanttd_core\n' >"$m/mod.conf"; printf 'title = Stock road path benchmark\n' >"$g/game.conf"
printf 'port = %s\nbind_address = 127.0.0.1\nserver_announce = false\n' "${BAYLINE_NATIVE_PORT:-44411}" >"$d/conf"
export HOME="$d/home" LUANTI_GAME_PATH="$d/games" MINETEST_GAME_PATH="$d/games"
if ! timeout "${LUANTTD_BENCH_TIMEOUT:-90}" "$server" --world "$d/world" --gameid pathbench --config "$d/conf" --logfile '' >"$d/log" 2>&1; then
  tail -40 "$d/log";exit 1
fi
grep 'ROAD ROUTE NATIVE' "$d/log"
! grep -E 'ERROR\[' "$d/log"
