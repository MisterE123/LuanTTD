#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
out=$(mktemp -d "${TMPDIR:-/tmp}/luanttd-jump-map-detail-native.XXXXXX")
echo "Native worker jump map evidence: $out"
game="$out/games/luanttd"
mkdir -p "$game" "$out/world" "$out/home" "$out/cache"
cp game.conf "$game/"
cp -al mods "$game/" 2>/dev/null || cp -a mods/. "$game/mods/"
cp mods/luanttd_core/init.lua "$out/init.lua"
mv "$out/init.lua" "$game/mods/luanttd_core/init.lua"
printf '\n' >>"$game/mods/luanttd_core/init.lua"
cat tests/campaign_worker_jump_map_native.lua >>"$game/mods/luanttd_core/init.lua"
printf 'gameid = luanttd\nbackend = sqlite3\nplayer_backend = sqlite3\nauth_backend = sqlite3\nmod_storage_backend = sqlite3\n' >"$out/world/world.mt"
port=${BAYLINE_NATIVE_PORT:-42680}
display=${BAYLINE_NATIVE_DISPLAY:-419}
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
luanti --go --address 127.0.0.1 --port "$port" --name JumpMapQA --password '' --config "$out/client.conf" --logfile '' >"$out/client.log" 2>&1 &
client=$!
mark 'JUMP_NATIVE_HOTBAR'
win=$(timeout 12 xdotool search --sync --onlyvisible --pid "$client" | tail -1)
xdotool windowfocus --sync "$win"
xdotool mousemove 730 445
sleep 2.6
import -window root "$out/home.png"
select_slot(){
  local k=$1 wait_for=$2
  for _ in {1..8}; do
    if grep -q "$wait_for" "$out/server.log"; then return; fi
    xdotool keydown "$k"; sleep .14; xdotool keyup "$k"
    sleep .42
    xdotool mousedown 1; sleep .28; xdotool mouseup 1
    sleep .95
  done
  mark "$wait_for"
}
select_slot 5 'JUMP_NATIVE_NAV_SLOT'
mark 'JUMP_NATIVE_NAV_SLOT'
slot=$(awk '/JUMP_NATIVE_NAV_SLOT/{print $NF;exit}' "$out/server.log")
select_slot "$slot" 'JUMP_NATIVE_RENDER overview'
mark 'JUMP_NATIVE_RENDER overview'
shot(){ import -window root "$out/$1.png"; }
choose(){
  local page=$1 key=$2 x y
  read -r x y < <(python3 tests/campaign_worker_jump_map_click.py "$out/$page.png" "$out/server.log" "$key")
  xdotool mousemove "$x" "$y"; sleep .08; xdotool mousedown 1; sleep .16; xdotool mouseup 1
}
sleep .85; shot overview
choose overview map_inspect
mark 'JUMP_NATIVE_RENDER select'
sleep .80; shot select
choose select jump_184
mark 'JUMP_NATIVE_RENDER detail'
sleep .80; shot detail
choose detail map_zoom
mark 'JUMP_NATIVE_RENDER overview2'
sleep .80; shot overview2
choose overview2 jump_place
mark 'PASS NATIVE WORKER JUMP MAP'
sleep .55; shot landed
grep -E 'JUMP_NATIVE_RENDER|PASS NATIVE WORKER JUMP MAP' "$out/server.log"
! grep -E 'ERROR\[' "$out/server.log" "$out/client.log"
