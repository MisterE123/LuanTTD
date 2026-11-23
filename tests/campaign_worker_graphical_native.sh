#!/usr/bin/env bash
# Controlled Linux graphical client talks to the ordinary game with its
# disposable worker handoff probe. No external network, user save, or chat.
set -euo pipefail
cd "$(dirname "$0")/.."
root=$PWD
out=$(mktemp -d "${TMPDIR:-/tmp}/luanttd-worker-scene.XXXXXX")
echo "$out"
game="$out/games/luanttd"
mkdir -p "$game" "$out/world" "$out/home" "$out/cache"
cp game.conf "$game/"
cp -al mods "$game/"
cp mods/luanttd_core/init.lua "$out/init.lua"
mv "$out/init.lua" "$game/mods/luanttd_core/init.lua"
cat tests/campaign_ordinary_worker_native.lua >> "$game/mods/luanttd_core/init.lua"
printf 'gameid = luanttd\nbackend = sqlite3\nplayer_backend = sqlite3\nauth_backend = sqlite3\nmod_storage_backend = sqlite3\n' >"$out/world/world.mt"
port=${BAYLINE_NATIVE_PORT:-40024}
display=${BAYLINE_NATIVE_DISPLAY:-199}
cat >"$out/server.conf" <<CONF
port = $port
bind_address = 127.0.0.1
server_announce = false
bayline_generated_map_width = 64
bayline_generated_map_depth = 64
bayline_generated_relief = 0
bayline_generated_coasts = 0
luanttd_worker_graphical_qa = true
singleplayer_mode = false
CONF
cat >"$out/client.conf" <<'CONF'
screen_w = 1440
screen_h = 900
fullscreen = false
enable_sound = false
gui_scaling = 1.0
CONF
if [[ -n ${BAYLINE_NATIVE_TOOLS:-} ]]; then
  t=$(realpath "$BAYLINE_NATIVE_TOOLS")
  export PATH="$t/run/bin:$t/usr/bin:$PATH" LD_LIBRARY_PATH="$t/usr/lib/x86_64-linux-gnu${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
fi
export DISPLAY="127.0.0.1:$display" HOME="$out/home" LIBGL_ALWAYS_SOFTWARE=1 MESA_SHADER_CACHE_DISABLE=1
export XDG_CACHE_HOME="${LUANTTD_NATIVE_MEDIA_CACHE:-$out/cache}"
export LUANTI_GAME_PATH="$out/games" MINETEST_GAME_PATH="$out/games"
cc -shared -fPIC tests/native_loopback.c -ldl -o "$out/loopback.so"
env LD_PRELOAD="$out/loopback.so" Xvfb ":$display" -screen 0 1440x900x24 -listen tcp -nolisten local -nolisten unix -ac -noreset >"$out/xvfb.log" 2>&1 &
xv=$!; server="" client=""
trap 'if [[ -n "$client" ]]; then kill "$client" 2>/dev/null || true;fi; if [[ -n "$server" ]];then kill "$server" 2>/dev/null || true;fi;kill "$xv" 2>/dev/null || true;wait 2>/dev/null || true' EXIT
for _ in {1..40}; do xdpyinfo >/dev/null 2>&1 && break; sleep .25; done
luantiserver --world "$out/world" --gameid luanttd --config "$out/server.conf" --logfile '' >"$out/server.log" 2>&1 &
server=$!
mark(){ for _ in {1..360}; do grep -q "$1" "$out/server.log" && return; kill -0 "$server" 2>/dev/null || break; sleep .25; done; tail -70 "$out/server.log"; return 1; }
mark 'listening on'
luanti --go --address 127.0.0.1 --port "$port" --name OrdinaryWorker --password '' --config "$out/client.conf" --logfile '' >"$out/client.log" 2>&1 &
client=$!
mark NATIVE_PROJECTED_CLIENT_READY
win=$(xdotool search --sync --limit 1 --onlyvisible --pid "$client" | tail -1)
xdotool windowfocus --sync "$win"
mark 'PASS NATIVE PROJECTED PAINTER'
xdotool keydown d
sleep 1.5
xdotool keyup d
mark 'PASS NATIVE PROJECTED WALK'
import -window root -resize 960x600 -quality 88 "$out/worker-scene.jpg"
mark 'PASS NATIVE PROJECTED TRAIN FORM'
sleep .55
import -window root -resize 960x600 -quality 88 "$out/worker-orders.jpg"
xdotool mousemove 570 501 click 1
sleep .5
import -window root -resize 960x600 -quality 88 "$out/worker-edit.jpg"
mark 'PASS NATIVE PROJECTED TRAIN EDIT'
mark 'PASS NATIVE ORDINARY HANDOFF'
grep 'PASS NATIVE' "$out/server.log"
! grep -E 'ERROR\[' "$out/server.log"
