#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
out=$(mktemp -d "${TMPDIR:-/tmp}/luanttd-farm-building-native.XXXXXX")
echo "Native farm buildings evidence: $out"
game="$out/games/luanttd"
mkdir -p "$game" "$out/world" "$out/home" "$out/cache"
cp game.conf "$game/"
cp -al mods "$game/" 2>/dev/null || cp -a mods/. "$game/mods/"
# A/B snapshot: same generated seed and cameras with original farm geometry.
if [[ -n ${LUANTTD_QA_FARM_MODEL_BASE:-} ]]; then
  for file in "$game"/mods/luanttd_core/models/bl_industry_farm_*_*.obj; do
    stem=${file#"$game/"}
    git show "$LUANTTD_QA_FARM_MODEL_BASE:$stem" >"$out/baseline.obj"
    mv -f "$out/baseline.obj" "$file"
  done
fi
cp mods/luanttd_core/init.lua "$out/init.lua"
mv "$out/init.lua" "$game/mods/luanttd_core/init.lua"
printf '\n' >>"$game/mods/luanttd_core/init.lua"
cat tests/campaign_worker_farm_building_native.lua >>"$game/mods/luanttd_core/init.lua"
printf 'gameid = luanttd\nbackend = sqlite3\nplayer_backend = sqlite3\nauth_backend = sqlite3\nmod_storage_backend = sqlite3\n' >"$out/world/world.mt"
port=${BAYLINE_NATIVE_PORT:-42670}
display=${BAYLINE_NATIVE_DISPLAY:-402}
cat >"$out/server.conf" <<CONF
port = $port
bind_address = 127.0.0.1
prometheus_listener_address = 127.0.0.1:$port
server_announce = false
bayline_generated_map_width = 128
bayline_generated_map_depth = 128
bayline_generated_relief = 0
bayline_generated_coasts = 0
bayline_generated_towns = 3
bayline_generated_industries = 6
bayline_generated_industry_count = 48
bayline_generated_town_layout = grid2
bayline_seed = ${LUANTTD_QA_FARM_SEED:-11}
time_speed = 0
singleplayer_mode = false
CONF
printf 'screen_w = 1440\nscreen_h = 900\nenable_sound = false\n' >"$out/client.conf"
if [[ -n ${BAYLINE_NATIVE_TOOLS:-} ]]; then
  t=$(realpath "$BAYLINE_NATIVE_TOOLS")
  export PATH="$t/run/bin:$t/usr/bin:$PATH" LD_LIBRARY_PATH="$t/usr/lib/x86_64-linux-gnu${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
fi
export DISPLAY="127.0.0.1:$display" HOME="$out/home" LIBGL_ALWAYS_SOFTWARE=1 MESA_SHADER_CACHE_DISABLE=1
export XDG_CACHE_HOME="${LUANTTD_NATIVE_MEDIA_CACHE:-$out/cache}" LUANTI_GAME_PATH="$out/games" MINETEST_GAME_PATH="$out/games"
cc -shared -fPIC tests/native_loopback.c -ldl -o "$out/loopback.so"
env LD_PRELOAD="$out/loopback.so" Xvfb ":$display" -screen 0 1440x900x24 -listen tcp -nolisten local -nolisten unix -ac -noreset >"$out/xvfb.log" 2>&1 &
xv=$!; server= client=
source tests/native_processes.sh
trap 'native_stop_children "$client" "$server" "$xv"' EXIT
for _ in {1..40}; do xdpyinfo >/dev/null 2>&1 && break; sleep .25; done
xdpyinfo > /dev/null || { cat "$out/xvfb.log"; exit 1; }
luantiserver --world "$out/world" --gameid luanttd --config "$out/server.conf" --logfile '' >"$out/server.log" 2>&1 &
server=$!
mark(){ for _ in {1..360}; do grep -q "$1" "$out/server.log" && return; kill -0 "$server" 2>/dev/null || break; sleep .25; done; tail -70 "$out/server.log"; return 1; }
mark 'listening on'
luanti --go --address 127.0.0.1 --port "$port" --name FarmBuildingQA --password '' --config "$out/client.conf" --logfile '' >"$out/client.log" 2>&1 &
client=$!
shot() {
  if command -v import >/dev/null; then import -window root -quality 97 "$out/$1.jpg"
  elif command -v magick-im7.q16 >/dev/null; then magick-im7.q16 import -window root -quality 97 "$out/$1.jpg"
  fi
}
for view in survey barn silos farmhouse rear paddocks; do
  mark "FARM_BUILDING_QA $view"
  sleep 1.2
  shot "$view"
done
mark 'PASS NATIVE WORKER FARM BUILDINGS'
grep -E 'FARM_BUILDING_QA|PASS NATIVE (WORKER FARM BUILDINGS|FARM LIVESTOCK)' "$out/server.log"
! grep -E 'ERROR\[' "$out/server.log" "$out/client.log"
