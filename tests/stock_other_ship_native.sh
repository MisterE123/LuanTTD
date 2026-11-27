#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
out=$(mktemp -d "${TMPDIR:-/tmp}/luanttd-other-ship-native.XXXXXX")
echo "Native Temperate ship evidence: $out"
game="$out/games/luanttd"
mkdir -p "$game" "$out/world" "$out/home" "$out/cache"
cp game.conf "$game/"
cp -al mods "$game/" 2>/dev/null || cp -a mods/. "$game/mods/"
awk '/^local resumed_owner=/{print "dofile(mod..\"/qa_tanker_seed.lua\")(core,Sim,OwnerCheckpoint,mod)"} {print}' mods/luanttd_core/init.lua > "$out/init.lua"
cp tests/stock_other_ship_native_seed.lua "$game/mods/luanttd_core/qa_tanker_seed.lua"
printf 'return function() return {interval=.05} end\n' >"$game/mods/luanttd_core/qa_layout.lua"
mv "$out/init.lua" "$game/mods/luanttd_core/init.lua"
printf '\n' >>"$game/mods/luanttd_core/init.lua"
if [[ ${LUANTTD_QA_OTHER_SHIP_CARGO:-stock} != stock ]]; then
  cat tests/stock_goods_ship_native.lua >>"$game/mods/luanttd_core/init.lua"
else
  cat tests/stock_other_ship_native.lua >>"$game/mods/luanttd_core/init.lua"
fi
printf 'gameid = luanttd\nbackend = sqlite3\nplayer_backend = sqlite3\nauth_backend = sqlite3\nmod_storage_backend = sqlite3\n' >"$out/world/world.mt"
port=${BAYLINE_NATIVE_PORT:-40024}
display=${BAYLINE_NATIVE_DISPLAY:-199}
cat >"$out/server.conf" <<CONF
port = $port
bind_address = 127.0.0.1
prometheus_listener_address = 127.0.0.1:$port
server_announce = false
bayline_stock_bus_start_year = ${LUANTTD_QA_OTHER_SHIP_YEAR:-1985}
luanttd_qa_other_ship = ${LUANTTD_QA_OTHER_SHIP:-212}
luanttd_qa_other_ship_cargo = ${LUANTTD_QA_OTHER_SHIP_CARGO:-stock}
bayline_generated_map_width = 128
bayline_generated_map_depth = 128
bayline_generated_relief = 0
bayline_generated_coasts = 0
bayline_generated_towns = 3
bayline_generated_town_layout = grid2
singleplayer_mode = false
CONF
printf 'screen_w = 1440\nscreen_h = 900\nenable_sound = false\n' >"$out/client.conf"
if [[ -n ${BAYLINE_NATIVE_TOOLS:-} ]]; then
  t=$(realpath "$BAYLINE_NATIVE_TOOLS")
  export PATH="$t/run/bin:$t/usr/bin:$PATH" LD_LIBRARY_PATH="$t/usr/lib/x86_64-linux-gnu${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
fi
export DISPLAY="127.0.0.1:$display" HOME="$out/home" LIBGL_ALWAYS_SOFTWARE=1 MESA_SHADER_CACHE_DISABLE=1
export XDG_CACHE_HOME="${LUANTTD_NATIVE_MEDIA_CACHE:-$out/cache}" LUANTI_GAME_PATH="$out/games" MINETEST_GAME_PATH="$out/games"
# The game contains enough 3D media to saturate a cold client's packet
# quota before its scripted controls can run on GitHub's runner.
# Seed only stock, hash-addressed media; the native game and UI still run.
if [[ -z ${LUANTTD_NATIVE_MEDIA_CACHE:-} ]]; then
  python3 tests/cache_luanti_game_media.py "$game" "$XDG_CACHE_HOME" --hardlink
fi
cc -shared -fPIC tests/native_loopback.c -ldl -o "$out/loopback.so"
env LD_PRELOAD="$out/loopback.so" Xvfb ":$display" -screen 0 1440x900x24 -listen tcp -nolisten local -nolisten unix -ac -noreset >"$out/xvfb.log" 2>&1 &
xv=$!; server= client=
trap '[[ -z "$client" ]] || kill "$client" 2>/dev/null || true; [[ -z "$server" ]] || kill "$server" 2>/dev/null || true; kill "$xv" 2>/dev/null || true;wait 2>/dev/null || true' EXIT
for _ in {1..40}; do xdpyinfo >/dev/null 2>&1 && break; sleep .25; done
xdpyinfo > /dev/null || { cat "$out/xvfb.log"; exit 1; }
luantiserver --world "$out/world" --gameid luanttd --config "$out/server.conf" --logfile '' >"$out/server.log" 2>&1 &
server=$!
mark(){ for _ in {1..360}; do grep -q "$1" "$out/server.log" && return; kill -0 "$server" 2>/dev/null || break; sleep .25; done; tail -70 "$out/server.log"; return 1; }
mark 'listening on'
luanti --go --address 127.0.0.1 --port "$port" --name ShipReview --password '' --config "$out/client.conf" --logfile '' >"$out/client.log" 2>&1 &
client=$!
mark 'PASS NATIVE STOCK SHIP' || { tail -70 "$out/client.log"; exit 1; }
sleep .50
if command -v import >/dev/null; then import -window root -resize 1200x750 -quality 91 "$out/ship.jpg"
elif command -v magick-im7.q16 >/dev/null; then magick-im7.q16 import -window root -resize 1200x750 -quality 91 "$out/ship.jpg"
fi
grep 'PASS NATIVE STOCK SHIP' "$out/server.log"
! grep -E 'ERROR\[|LuanTTD viewport placement:' "$out/server.log" "$out/client.log"
if [[ ${LUANTTD_QA_OTHER_SHIP_CARGO:-stock} != stock ]]; then
  kill "$client" 2>/dev/null || true; wait "$client" 2>/dev/null || true; client=
  kill "$server"; wait "$server"; server=
  luantiserver --world "$out/world" --gameid luanttd --config "$out/server.conf" --logfile '' >"$out/reopen.log" 2>&1 &
  server=$!
  for _ in {1..360}; do
    grep -q 'listening on' "$out/reopen.log" && break
    kill -0 "$server" 2>/dev/null || break;sleep .25
  done
  grep -q 'listening on' "$out/reopen.log" || { tail -70 "$out/reopen.log"; exit 1; }
  luanti --go --address 127.0.0.1 --port "$port" --name ShipReview --password '' --config "$out/client.conf" --logfile '' >"$out/reopen-client.log" 2>&1 &
  client=$!
  for _ in {1..360}; do
    grep -q 'PASS NATIVE DRY SHIP REOPEN' "$out/reopen.log" && break
    kill -0 "$server" 2>/dev/null || break;sleep .25
  done
  grep 'PASS NATIVE DRY SHIP REOPEN' "$out/reopen.log" || { tail -70 "$out/reopen.log"; exit 1; }
  ! grep -E 'ERROR\[|LuanTTD viewport placement:' "$out/reopen.log" "$out/reopen-client.log"
fi
