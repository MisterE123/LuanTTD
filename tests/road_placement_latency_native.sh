#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
out=$(mktemp -d "${TMPDIR:-/tmp}/luanttd-road-placement.XXXXXX")
echo "Road placement native timing: $out"
game="$out/games/luanttd"
mkdir -p "$game" "$out/world" "$out/home"
cp game.conf "$game/"
cp -al mods "$game/"
mod="$game/mods/luanttd_core"
cp tests/road_placement_latency_native.lua "$out/init.lua"
mv "$out/init.lua" "$mod/init.lua"
if [[ -n ${LUANTTD_QA_BASELINE_REV:-} ]]; then
  for path in campaign_authority_endpoint campaign_authority_host campaign_authority_interest campaign_authority_worker campaign_build_proxy campaign_road_construction sim; do
    git show "$LUANTTD_QA_BASELINE_REV:mods/luanttd_core/$path.lua" > "$out/baseline-$path.lua"
    mv "$out/baseline-$path.lua" "$mod/$path.lua"
  done
fi
printf 'gameid = luanttd\nbackend = sqlite3\nplayer_backend = sqlite3\nauth_backend = sqlite3\nmod_storage_backend = sqlite3\n' > "$out/world/world.mt"
export HOME="$out/home" LUANTI_GAME_PATH="$out/games" MINETEST_GAME_PATH="$out/games"
port=${BAYLINE_NATIVE_PORT:-41190}
printf 'port = %s\nprometheus_listener_address = 127.0.0.1:%s\nbind_address = 127.0.0.1\nserver_announce = false\ndedicated_server_step = 0.02\n' "$port" "$port" > "$out/server.conf"
if [[ ${LUANTTD_NATIVE_BENCH_REMOVE:-0} == 1 ]]; then
  printf "luanttd_bench_remove = true\n" >> "$out/server.conf"
fi
timeout 100 luantiserver --world "$out/world" --config "$out/server.conf" --gameid luanttd --logfile '' > "$out/server.log" 2>&1 || {
  tail -80 "$out/server.log"
  exit 1
}
grep ROAD_PLACEMENT_NATIVE_PASS "$out/server.log"
