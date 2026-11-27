#!/usr/bin/env bash
# A/B sample of production viewport receipts; this is not an FPS benchmark.
set -euo pipefail
cd "$(dirname "$0")/.."
[[ $# == 3 ]] || { echo "usage: $0 LUANTI_SERVER BASELINE_GIT_REV NEW_OUTPUT_DIRECTORY" >&2; exit 64; }
server=$1
if [[ "$server" == */* ]]; then server=$(realpath "$server"); fi
base=$2
mkdir "$3"
out=$(realpath "$3")
game="$out/games/gapbench"
mod="$game/mods/luanttd_core"
mkdir -p "$mod" "$out/home" "$out/before" "$out/after" "$out/modules"
echo 'title = Transport pose gap benchmark' > "$game/game.conf"
echo 'name = luanttd_core' > "$mod/mod.conf"
cp mods/luanttd_core/*.lua "$mod/"
cp -a mods/luanttd_core/openttd "$mod/"
cp tests/campaign_pose_gap_native.lua "$mod/init.lua"
cp tests/road_fleet_perf.lua "$mod/"
for file in sim.lua road_speed_runtime.lua campaign_authority_worker.lua; do
  git show "$base:mods/luanttd_core/$file" > "$out/modules/before-$file"
  cp "$mod/$file" "$out/modules/after-$file"
done
export HOME="$out/home" LUANTI_GAME_PATH="$out/games" MINETEST_GAME_PATH="$out/games"
port=${BAYLINE_NATIVE_PORT:-43976}
printf 'port = %s\nbind_address = 127.0.0.1\ndedicated_server_step = 0.025\nserver_announce = false\n' "$port" > "$out/conf"
order=(before after)
if [[ ${BAYLINE_GAP_ABBA:-0} == 1 ]]; then order+=(after2 before2); fi
for side in "${order[@]}"; do
  mkdir -p "$out/$side"
  for file in sim.lua road_speed_runtime.lua campaign_authority_worker.lua; do cp "$out/modules/${side%2}-$file" "$mod/$file"; done
  world="$out/$side"
  printf 'gameid = gapbench\nbackend = sqlite3\nplayer_backend = sqlite3\nauth_backend = sqlite3\nmod_storage_backend = sqlite3\n' > "$world/world.mt"
  timeout 60 "$server" --world "$world" --config "$out/conf" --gameid gapbench --logfile '' > "$world/log" 2>&1 ||
    { tail -50 "$world/log"; exit 1; }
  echo "$side:"
  grep "LIVE GAP" "$world/log"
done
