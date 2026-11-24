#!/usr/bin/env bash
# Stock Lua worker, real client primary actions, independent disposable world.
set -euo pipefail
cd "$(dirname "$0")/.."
out=$(mktemp -d "${TMPDIR:-/tmp}/luanttd-hotbar-task.XXXXXX")
echo "HOTBAR_TASK evidence $out"
game="$out/games/luanttd"
mkdir -p "$game" "$out/home" "$out/cache" "$out/world"
cp game.conf "$game/"
cp -al mods "$game/"
cat mods/luanttd_core/init.lua tests/hotbar_task_native.lua >"$out/init.lua"
mv "$out/init.lua" "$game/mods/luanttd_core/init.lua"
port=${BAYLINE_NATIVE_PORT:-41363}; display=${BAYLINE_NATIVE_DISPLAY:-271}
export DISPLAY="127.0.0.1:$display" HOME="$out/home" LIBGL_ALWAYS_SOFTWARE=1 LP_NUM_THREADS=2
export XDG_CACHE_HOME="${LUANTTD_NATIVE_MEDIA_CACHE:-$out/cache}" LUANTI_GAME_PATH="$out/games" MINETEST_GAME_PATH="$out/games"
printf 'gameid = luanttd\nbackend = sqlite3\nplayer_backend = sqlite3\nauth_backend = sqlite3\nmod_storage_backend = sqlite3\n' >"$out/world/world.mt"
printf 'port = %s\nbind_address = 127.0.0.1\nserver_announce = false\nbayline_seed = 1751\ntime_speed = 0\n' "$port" >"$out/server.conf"
printf 'screen_w = 1200\nscreen_h = 760\nenable_sound = false\nfps_max = 26\nviewing_range = 60\nenable_shaders = false\n' >"$out/client.conf"
cc -shared -fPIC tests/native_loopback.c -ldl -o "$out/loopback.so"
env LD_PRELOAD="$out/loopback.so" Xvfb ":$display" -screen 0 1200x760x24 -listen tcp -nolisten local -nolisten unix -ac -noreset >"$out/xvfb.log" 2>&1 &
xv=$!; server= client=
trap '[[ -z "$client" ]] || kill "$client" 2>/dev/null || true; [[ -z "$server" ]] || kill "$server" 2>/dev/null || true; kill "$xv" 2>/dev/null || true; wait 2>/dev/null || true' EXIT
for _ in {1..45}; do xdpyinfo >/dev/null 2>&1 && break; sleep .2; done
xdpyinfo >/dev/null
luantiserver --world "$out/world" --gameid luanttd --config "$out/server.conf" --logfile '' >"$out/server.log" 2>&1 &
server=$!
for _ in {1..200}; do grep -q 'listening on' "$out/server.log" && break; sleep .2; done
grep -q 'listening on' "$out/server.log" || { cat "$out/server.log"; exit 1; }
if [[ -z ${LUANTTD_NATIVE_MEDIA_CACHE:-} ]]; then
  python3 tests/cache_luanti_game_media.py "$game" "$XDG_CACHE_HOME"
fi
luanti --go --address 127.0.0.1 --port "$port" --name ToolbarQA --password '' --config "$out/client.conf" --logfile '' >"$out/client.log" 2>&1 &
client=$!
mark() {
 local limit=${2:-100}
 for ((i=0;i<limit;i++)); do
   grep -q "HOTBAR_TASK $1" "$out/server.log" && return
   kill -0 "$server" "$client" 2>/dev/null || break
   sleep .2
 done
 tail -n 80 "$out/"{server,client}.log; return 1
}
select_slot() { xdotool keydown "$1"; sleep .21; xdotool keyup "$1"; sleep .36; }
choose() {
 mark "$1"
 local slot
 slot=$(sed -n "s/.*HOTBAR_TASK $1 //p" "$out/server.log" | tail -1)
 [[ -n "$slot" ]]
 [[ $slot != 10 ]] || slot=0
 select_slot "$slot"
 xdotool mousedown 1; sleep .30; xdotool mouseup 1
}
back(){ select_slot 1; xdotool mousedown 1; sleep .3; xdotool mouseup 1; sleep .48; }
shot(){ if command -v import >/dev/null; then sleep .44; import -window root -quality 91 "$out/$1.jpg"; fi; }
mark CLIENT_JOINED 350
mark WORKER_ADMITTED 250
mark AIM_SETTLED 180
mark HOME_ROAD
win=$(timeout 10 xdotool search --sync --onlyvisible --pid "$client" | tail -1)
xdotool windowraise "$win" windowfocus --sync "$win"
sleep .8
shot home
choose HOME_RAIL; mark RAIL_OPEN; shot rail
back
choose HOME_WATER; mark WATER_OPEN; shot water
back
choose HOME_AIR; mark AIR_OPEN
back
choose HOME_ROAD; mark ROAD_OPEN
road_open=$(sed -n 's/.*HOTBAR_TASK ROAD_OPEN //p' "$out/server.log" | tail -1)
select_slot "$road_open"; shot road
choose DEPOT_TOOL; mark DEPOT_BUILT
choose ROAD_OPEN; mark ROAD_SERVICE; shot depot
xdotool key Escape; sleep .3
back
choose HOME_FLEET; choose FLEET_LIST; mark FLEET_FILTERS
sleep .65; xdotool mousemove 395 233 click 1; mark FLEET_ROAD_READY; shot fleet
! grep -Ei 'ERROR\[|could not load' "$out/"{client,server}.log
echo "PASS HOTBAR_TASK: direct rail, water, air sections; road depot built and opened with primary actions; all-mode fleet filters"
