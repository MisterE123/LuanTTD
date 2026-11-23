#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
out=$(mktemp -d "${TMPDIR:-/tmp}/luanttd-tunnel-bore-native.XXXXXX")
echo "Native tunnel bore evidence: $out"
game="$out/games/luanttd"
mkdir -p "$game" "$out/world" "$out/home" "$out/cache"
cp game.conf "$game/"
cp -al mods "$game/" 2>/dev/null || cp -a mods/. "$game/mods/"
cp mods/luanttd_core/init.lua "$out/init.lua"
mv "$out/init.lua" "$game/mods/luanttd_core/init.lua"
# Seed a disposable deterministic ridge before the real worker checkpoint.
sed -i '/^local authority_started/r tests/campaign_worker_tunnel_prep.lua' "$game/mods/luanttd_core/init.lua"
printf '\n' >>"$game/mods/luanttd_core/init.lua"
probe=tests/campaign_worker_tunnel_bore_native.lua
if [[ ${LUANTTD_QA_TUNNEL_CAB:-false} == true ]]; then
  probe=tests/campaign_worker_tunnel_cab_native.lua
fi
cat "$probe" >>"$game/mods/luanttd_core/init.lua"
printf 'gameid = luanttd\nbackend = sqlite3\nplayer_backend = sqlite3\nauth_backend = sqlite3\nmod_storage_backend = sqlite3\n' >"$out/world/world.mt"
if [[ -n ${LUANTTD_QA_TUNNEL_BASE:-} ]]; then
  git show "$LUANTTD_QA_TUNNEL_BASE:mods/luanttd_core/render.lua" >"$out/render.lua"
  mv "$out/render.lua" "$game/mods/luanttd_core/render.lua"
fi
port=${BAYLINE_NATIVE_PORT:-42690}
display=${BAYLINE_NATIVE_DISPLAY:-429}
cat >"$out/server.conf" <<CONF
port = $port
bind_address = 127.0.0.1
prometheus_listener_address = 127.0.0.1:$port
server_announce = false
bayline_generated_map_width = 128
bayline_generated_map_depth = 128
bayline_generated_relief = 0
bayline_generated_coasts = 15
bayline_generated_sea = 1
time_speed = 0
luanttd_qa_bore_baseline = ${LUANTTD_QA_BORE_BASELINE:-false}
luanttd_qa_tunnel_pause = ${LUANTTD_QA_TUNNEL_PAUSE:-false}
bayline_generated_towns = 3
bayline_generated_town_layout = grid2
bayline_seed = 1751
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
trap '[[ -z "$client" ]] || kill "$client" 2>/dev/null || true; [[ -z "$server" ]] || kill "$server" 2>/dev/null || true; kill "$xv" 2>/dev/null || true;wait 2>/dev/null || true' EXIT
for _ in {1..40}; do xdpyinfo >/dev/null 2>&1 && break; sleep .25; done
xdpyinfo > /dev/null || { cat "$out/xvfb.log"; exit 1; }
luantiserver --world "$out/world" --gameid luanttd --config "$out/server.conf" --logfile '' >"$out/server.log" 2>&1 &
server=$!
mark(){ for _ in {1..360}; do grep -q "$1" "$out/server.log" && return; kill -0 "$server" 2>/dev/null || break; sleep .25; done; tail -70 "$out/server.log"; return 1; }
mark 'listening on'
luanti --go --address 127.0.0.1 --port "$port" --name TunnelBoreQA --password '' --config "$out/client.conf" --logfile '' >"$out/client.log" 2>&1 &
client=$!
shot(){ import -window root -quality 96 "$out/$1.jpg"; }
if [[ ${LUANTTD_QA_TUNNEL_CAB:-false} == true ]]; then
  mark 'TUNNEL_BORE_QA_BOARD'
  win=$(timeout 12 xdotool search --sync --onlyvisible --pid "$client" | tail -1)
  xdotool windowraise "$win" windowfocus --sync "$win"
  mark 'TUNNEL_BORE_QA_APPROACH'
  sleep .43; shot cab-approach
  mark 'TUNNEL_BORE_QA_MOVING_CAB'
  sleep .34; shot cab-in-bore
  mark 'TUNNEL_BORE_QA_EXIT'
  sleep .48; shot cab-exit
  mark 'PASS NATIVE MOVING TRAIN CAB THROUGH BORES'
  grep -E 'TUNNEL_BORE_QA|PASS NATIVE MOVING' "$out/server.log"
  ! grep -E 'ERROR\[' "$out/server.log" "$out/client.log"
  exit
fi
mark 'TUNNEL_BORE_QA_OUTSIDE'
win=$(timeout 12 xdotool search --sync --onlyvisible --pid "$client" | tail -1)
xdotool windowfocus --sync "$win"
sleep .75; shot portals
mark 'TUNNEL_BORE_QA_CAR_READY'
xdotool keydown w
mark 'TUNNEL_BORE_QA_CAR_INSIDE'
sleep .55; shot road-interior
mark 'TUNNEL_BORE_QA_CAR_EXITED'
xdotool keyup w
mark 'TUNNEL_BORE_QA_RAIL_INSIDE'
sleep .7; shot rail-interior
mark 'TUNNEL_BORE_QA_SURFACE'
sleep .7; shot surface
mark 'PASS NATIVE TUNNEL BORES'
grep -E 'TUNNEL_BORE_QA|PASS NATIVE TUNNEL BORES' "$out/server.log"
! grep -E 'ERROR\[' "$out/server.log" "$out/client.log"
