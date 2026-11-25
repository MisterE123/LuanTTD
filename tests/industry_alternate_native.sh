#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
case ${LUANTTD_NATIVE_GROUND_FIXTURE:-industry} in
  industry)
    fixture=tests/industry_alternate_native.lua
    start_marker='NATIVE ALTERNATE GENERATED:'
    frame_prefix='NATIVE INDUSTRY FRAME'
    pass_marker='PASS NATIVE INDUSTRY LAYOUTS:'
    ;;
  crossings)
    fixture=tests/roadside_crossing_ground_native.lua
    start_marker='NATIVE ROADSIDE FRAME'
    frame_prefix='NATIVE ROADSIDE FRAME'
    pass_marker='PASS NATIVE ROADSIDE GROUNDS:'
    ;;
  road_autoslope)
    fixture=tests/road_autoslope_native.lua
    start_marker='NATIVE ROAD TERRAFORM FRAME'
    frame_prefix='NATIVE ROAD TERRAFORM FRAME'
    pass_marker='PASS NATIVE ROAD AUTOSLOPE:'
    ;;
  electric_crossing)
    fixture=tests/electric_crossing_native.lua
    start_marker='NATIVE ELRL CROSSING FRAME'
    frame_prefix='NATIVE ELRL CROSSING FRAME'
    pass_marker='PASS NATIVE ELECTRIC CROSSING:'
    ;;
  *) echo "Unknown graphical ground fixture" >&2; exit 2;;
esac
out=$(mktemp -d "${TMPDIR:-/tmp}/luanttd-industry-layout-native.XXXXXX")
echo "Native industry layout evidence: $out"
game="$out/games/luanttd"
mkdir -p "$game" "$out/world" "$out/home" "$out/cache"
cp game.conf "$game/"
cp -al mods "$game/" 2>/dev/null || cp -a mods/. "$game/mods/"
cp mods/luanttd_core/init.lua "$out/init.lua"
mv "$out/init.lua" "$game/mods/luanttd_core/init.lua"
printf '\n' >>"$game/mods/luanttd_core/init.lua"
cat "$fixture" >>"$game/mods/luanttd_core/init.lua"
printf 'gameid = luanttd\nbackend = sqlite3\nplayer_backend = sqlite3\nauth_backend = sqlite3\nmod_storage_backend = sqlite3\n' >"$out/world/world.mt"
port=${BAYLINE_NATIVE_PORT:-42662}
display=${BAYLINE_NATIVE_DISPLAY:-389}
cat >"$out/server.conf" <<CONF
port = $port
bind_address = 127.0.0.1
prometheus_listener_address = 127.0.0.1:$port
server_announce = false
bayline_generated_map_width = 256
bayline_generated_map_depth = 256
bayline_generated_relief = 0
bayline_generated_coasts = 0
bayline_generated_towns = 3
bayline_generated_industries = 6
bayline_generated_industry_count = ${LUANTTD_INDUSTRY_LAYOUT_COUNT:-110}
bayline_generated_town_layout = grid2
bayline_seed = ${LUANTTD_INDUSTRY_LAYOUT_SEED:-11}
bayline_stock_bus_start_year = ${LUANTTD_NATIVE_START_YEAR:-1950}
luanttd_qa_road_autoslope_waypoint = ${LUANTTD_NATIVE_AUTOSLOPE_WAYPOINT:-false}
luanttd_qa_rail_station_autoslope = ${LUANTTD_NATIVE_RAIL_STATION_AUTOSLOPE:-false}
luanttd_qa_industry_layouts = ${LUANTTD_INDUSTRY_LAYOUTS:-coal_mine_l1,coal_mine_l2,coal_mine_l3,factory_l1,farm_l1,farm_l2,forest_l1,oil_refinery_l1,oil_well_l1,power_station_l1,power_station_l2,sawmill_l1}
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
stop_process(){
  local pid=$1
  [[ -n "$pid" ]] || return 0
  kill -TERM "$pid" 2>/dev/null || true
  for _ in {1..24}; do
    if ! kill -0 "$pid" 2>/dev/null; then break; fi
    sleep .10
  done
  kill -KILL "$pid" 2>/dev/null || true
}
cleanup(){
  # Keep X alive until the game client has shut down its renderer.
  stop_process "$client"; stop_process "$server"; stop_process "$xv"
}
trap cleanup EXIT
for _ in {1..40}; do xdpyinfo >/dev/null 2>&1 && break; sleep .25; done
xdpyinfo > /dev/null || { cat "$out/xvfb.log"; exit 1; }
luantiserver --world "$out/world" --gameid luanttd --config "$out/server.conf" --logfile '' >"$out/server.log" 2>&1 &
server=$!
mark(){ for _ in {1..360}; do grep -q "$1" "$out/server.log" && return; kill -0 "$server" 2>/dev/null || break; sleep .25; done; tail -70 "$out/server.log"; return 1; }
mark 'listening on'
luanti --go --address 127.0.0.1 --port "$port" --name IndustryLayoutsQA --password '' --config "$out/client.conf" --logfile '' >"$out/client.log" 2>&1 &
client=$!

mark "$start_marker"
for k in {1..460}; do
  while read -r label; do
    f="$out/$label.jpg"
    if [[ ! -e "$f" ]]; then
      import -window root -quality 91 "$f"
    fi
  done < <(sed -n "s/.*$frame_prefix //p" "$out/server.log")
  if grep -Fq "$pass_marker" "$out/server.log"; then break; fi
  kill -0 "$server" 2>/dev/null || break
  sleep .20
done
grep -E "$start_marker|$frame_prefix|$pass_marker" "$out/server.log"
if ! grep -Fq "$pass_marker" "$out/server.log"; then
  tail -75 "$out/server.log" "$out/client.log"
  exit 1
fi
! grep -E 'ERROR\[' "$out/server.log" "$out/client.log"
if [[ ${LUANTTD_NATIVE_GROUND_FIXTURE:-industry} == electric_crossing ]]; then
  stop_process "$client"; client=
  stop_process "$server"; server=
  mv "$out/server.log" "$out/first-server.log"
  mv "$out/client.log" "$out/first-client.log"
  luantiserver --world "$out/world" --gameid luanttd --config "$out/server.conf" --logfile '' >"$out/server.log" 2>&1 &
  server=$!
  mark 'listening on'
  luanti --go --address 127.0.0.1 --port "$port" --name IndustryLayoutsQA --password '' --config "$out/client.conf" --logfile '' >"$out/client.log" 2>&1 &
  client=$!
  mark 'PASS NATIVE ELECTRIC REOPEN:'
  grep 'PASS NATIVE ELECTRIC REOPEN:' "$out/server.log"
  ! grep -E 'ERROR\[' "$out/server.log" "$out/client.log"
fi
