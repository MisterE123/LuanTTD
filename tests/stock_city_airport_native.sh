#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
out=$(mktemp -d "${TMPDIR:-/tmp}/luanttd-city-native.XXXXXX")
echo "Native City evidence: $out"
game="$out/games/luanttd"
mkdir -p "$game" "$out/world" "$out/home" "$out/cache"
cp game.conf "$game/"
cp -al mods "$game/" 2>/dev/null || cp -a mods/. "$game/mods/"
cp mods/luanttd_core/init.lua "$out/init.lua"
mv "$out/init.lua" "$game/mods/luanttd_core/init.lua"
# The expensive late supersonic type is tested as a mature company,
# not with an impossible new-company loan. Seed capital only in this
# disposable fixture; the actual purchase still debits normal cash.
if [[ ${LUANTTD_QA_AIRFRAME:-226} == 247 ]]; then
  python3 - "$game/mods/luanttd_core/init.lua" <<'PYFIX'
from pathlib import Path
from sys import argv
p=Path(argv[1])
s=p.read_text()
key="local api={Sim=Sim,s=S"
assert key in s
p.write_text(s.replace(key,'if not resumed_owner then Sim.company(S,"CityReview").cash=350000 end\n'+key,1))
PYFIX
fi
printf '\n' >>"$game/mods/luanttd_core/init.lua"
fixture=tests/stock_city_airport_native.lua
pass_mark='PASS NATIVE CITY:'
restart_mark='PASS NATIVE CITY RESTART'
pass_limit=360
restart_limit=220
if [[ ${LUANTTD_QA_AIR_LAYOUT:-city} == heliport || ${LUANTTD_QA_AIR_LAYOUT:-city} == ground_rotary ]]; then
  fixture=tests/stock_heliport_native.lua
  pass_mark='PASS NATIVE HELIPORT:'
  restart_mark='PASS NATIVE HELIPORT RESTART'
  if [[ ${LUANTTD_QA_AIR_LAYOUT:-city} == ground_rotary ]]; then
    pass_mark='PASS NATIVE GROUND ROTARY:'
    restart_mark='PASS NATIVE GROUND ROTARY RESTART'
    pass_limit=720
    restart_limit=600
  fi
fi
cat "$fixture" >>"$game/mods/luanttd_core/init.lua"
printf 'gameid = luanttd\nbackend = sqlite3\nplayer_backend = sqlite3\nauth_backend = sqlite3\nmod_storage_backend = sqlite3\n' >"$out/world/world.mt"
airframe=${LUANTTD_QA_AIRFRAME:-226}
port=${BAYLINE_NATIVE_PORT:-40024}
display=${BAYLINE_NATIVE_DISPLAY:-199}
cat >"$out/server.conf" <<CONF
port = $port
bind_address = 127.0.0.1
prometheus_listener_address = 127.0.0.1:$port
server_announce = false
bayline_stock_bus_start_year = ${LUANTTD_QA_AIR_YEAR:-1975}
luanttd_qa_airframe = $airframe
luanttd_qa_air_layout = ${LUANTTD_QA_AIR_LAYOUT:-city}
luanttd_qa_air_autoslope = ${LUANTTD_QA_AIR_AUTOSLOPE:-false}
bayline_generated_map_width = 128
bayline_generated_map_depth = 128
bayline_generated_relief = 0
bayline_generated_coasts = 0
bayline_generated_towns = 3
bayline_generated_town_layout = grid2
singleplayer_mode = false
CONF
cat >"$out/client.conf" <<CONF
screen_w = 1260
screen_h = 800
enable_sound = false
viewing_range = 52
fps_max = 28
enable_shaders = false
enable_dynamic_shadows = false
CONF
if [[ -n ${BAYLINE_NATIVE_TOOLS:-} ]]; then
  t=$(realpath "$BAYLINE_NATIVE_TOOLS")
  export PATH="$t/run/bin:$t/usr/bin:$PATH" LD_LIBRARY_PATH="$t/usr/lib/x86_64-linux-gnu${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
fi
export DISPLAY="127.0.0.1:$display" HOME="$out/home" LIBGL_ALWAYS_SOFTWARE=1 MESA_SHADER_CACHE_DISABLE=1
export LP_NUM_THREADS="${LP_NUM_THREADS:-2}"
export XDG_CACHE_HOME="${LUANTTD_NATIVE_MEDIA_CACHE:-$out/cache}" LUANTI_GAME_PATH="$out/games" MINETEST_GAME_PATH="$out/games"
cc -shared -fPIC tests/native_loopback.c -ldl -o "$out/loopback.so"
env LD_PRELOAD="$out/loopback.so" Xvfb ":$display" -screen 0 1440x900x24 -listen tcp -nolisten local -nolisten unix -ac -noreset >"$out/xvfb.log" 2>&1 &
xv=$!; server= client=
stop_process(){
  local pid=$1
  [[ -n "$pid" ]] || return 0
  kill -TERM "$pid" 2>/dev/null || true
  for _ in {1..50}; do
    if ! kill -0 "$pid" 2>/dev/null; then wait "$pid" 2>/dev/null || true; return 0; fi
    sleep .10
  done
  echo "Native airport process $pid did not stop after SIGTERM; forcing shutdown" >&2
  kill -KILL "$pid" 2>/dev/null || true
  for _ in {1..20}; do
    if ! kill -0 "$pid" 2>/dev/null; then wait "$pid" 2>/dev/null || true; return 0; fi
    sleep .10
  done
  return 1
}
cleanup(){
  stop_process "$client" || true
  stop_process "$server" || true
  stop_process "$xv" || true
}
trap cleanup EXIT
trap 'exit 124' TERM INT
for _ in {1..40}; do xdpyinfo >/dev/null 2>&1 && break; sleep .25; done
xdpyinfo > /dev/null || { cat "$out/xvfb.log"; exit 1; }
luantiserver --world "$out/world" --gameid luanttd --config "$out/server.conf" --logfile '' >"$out/server.log" 2>&1 &
server=$!
mark(){ for ((i=0; i<${2:-360}; i++)); do grep -q "$1" "$out/server.log" && return; kill -0 "$server" 2>/dev/null || break; sleep .25; done; tail -70 "$out/server.log"; return 1; }
mark 'listening on'
luanti --go --address 127.0.0.1 --port "$port" --name CityReview --password '' --config "$out/client.conf" --logfile '' >"$out/client.log" 2>&1 &
client=$!
capture(){
  local target=$1
  if command -v import >/dev/null; then import -window root -resize 1200x750 -quality 91 "$out/$target"
  elif command -v magick-im7.q16 >/dev/null; then magick-im7.q16 import -window root -resize 1200x750 -quality 91 "$out/$target"
  fi
}
case "$airframe" in
  218|221|222|223|224|227|229|230|231|232|233|234|235|236|237|238|239|240|241|242|243|244|245|246|247)
    mark 'NATIVE AIR TAXI'
    capture taxi.jpg
    mark 'NATIVE AIR AIRBORNE'
    ;;
esac
mark "$pass_mark" "$pass_limit"
sleep .15
capture city.jpg
grep "$pass_mark" "$out/server.log"
if grep -E 'ERROR\[|LuanTTD viewport placement:' "$out/server.log" "$out/client.log"; then exit 1; fi

if [[ ${LUANTTD_QA_AIR_RESTART:-0} == 1 ]]; then
  stop_process "$client"; client=
  stop_process "$server"; server=
  printf '\nluanttd_qa_air_restart = true\n' >> "$out/server.conf"
  luantiserver --world "$out/world" --gameid luanttd --config "$out/server.conf" --logfile '' >"$out/restart-server.log" 2>&1 &
  server=$!
  for _ in {1..160}; do grep -q 'listening on' "$out/restart-server.log" && break; sleep .25; done
  grep -q 'listening on' "$out/restart-server.log"
  luanti --go --address 127.0.0.1 --port "$port" --name CityReview --password '' --config "$out/client.conf" --logfile '' >"$out/restart-client.log" 2>&1 &
  client=$!
  for ((i=0; i<restart_limit; i++)); do grep -q "$restart_mark" "$out/restart-server.log" && break; sleep .25; done
  grep "$restart_mark" "$out/restart-server.log" || { tail -60 "$out/restart-server.log"; exit 1; }
  capture restart.jpg
  if grep -E 'ERROR\[' "$out/"restart-{server,client}.log; then exit 1; fi
fi
