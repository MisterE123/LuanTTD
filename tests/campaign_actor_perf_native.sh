#!/usr/bin/env bash
# Compare the exact baseline and candidate actor paths in one Luanti worker.
set -euo pipefail
cd "$(dirname "$0")/.."
[[ $# == 3 ]] || { echo "usage: $0 LUANTI_SERVER BASELINE_GIT_REV NEW_OUTPUT_DIRECTORY" >&2; exit 64; }
server=$1
if [[ "$server" == */* ]]; then server=$(realpath "$server"); fi
baseline=$2
mkdir "$3"
out=$(realpath "$3")
game="$out/games/actorbench"
mod="$game/mods/luanttd_core"
mkdir -p "$mod" "$out/world" "$out/home"
printf 'title = Native campaign actor benchmark\n' > "$game/game.conf"
printf 'name = luanttd_core\n' > "$mod/mod.conf"
cp mods/luanttd_core/*.lua "$mod/"
cp -a mods/luanttd_core/openttd "$mod/"
cp tests/campaign_actor_perf_native.lua "$mod/init.lua"
cp tests/road_fleet_perf.lua "$mod/"
for source in campaign_actor_projection road_source_pose industry_machinery_world; do
  git show "$baseline:mods/luanttd_core/$source.lua" > "$mod/baseline_$source.lua"
done
git show "$baseline:mods/luanttd_core/campaign_authority_runtime.lua" |
  sed -e 's/"road_source_pose.lua"/"baseline_road_source_pose.lua"/' \
      -e 's/"campaign_actor_projection.lua"/"baseline_campaign_actor_projection.lua"/' > "$mod/baseline_runtime.lua"
printf 'gameid = actorbench\nbackend = sqlite3\nmod_storage_backend = sqlite3\n' > "$out/world/world.mt"
printf 'port = %s\nserver_announce = false\nbind_address = 127.0.0.1\n' "${BAYLINE_NATIVE_PORT:-43961}" > "$out/server.conf"
export HOME="$out/home" LUANTI_GAME_PATH="$out/games" MINETEST_GAME_PATH="$out/games"
if ! timeout 65 "$server" --config "$out/server.conf" --world "$out/world" --gameid actorbench --logfile '' >"$out/server.log" 2>&1; then
  cat "$out/server.log"; exit 1
fi
grep 'NATIVE ACTOR BENCH' "$out/server.log"
! grep -E 'ERROR\[' "$out/server.log"
