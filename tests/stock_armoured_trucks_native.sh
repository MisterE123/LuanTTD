#!/usr/bin/env bash
# Render stock production armoured entity meshes in a disposable native client/world.
set -euo pipefail
cd "$(dirname "$0")/.."
stage=$PWD
base=${LUANTTD_BASE:-$PWD}
tools=${BAYLINE_NATIVE_TOOLS:?Set BAYLINE_NATIVE_TOOLS to native tool root}
disp=${BAYLINE_NATIVE_DISPLAY:-184}
port=${BAYLINE_NATIVE_PORT:-39984}
out=$(mktemp -d "${TMPDIR:-/tmp}/luanttd-native-armoured.XXXXXX")
printf 'Armoured presentation evidence: %s\n' "$out"
root="$out/games/armoured_art"
mod="$root/mods/armours"
mkdir -p "$mod/"{models,textures} "$out/"{world,home,cache}
printf 'title = LuanTTD Armoured Trucks Native Art Fixture\n' >"$root/game.conf"
printf 'name = armours\n' >"$mod/mod.conf"
cp tests/stock_armoured_trucks_native.lua "$mod/init.lua"
cp mods/luanttd_core/models/bl_stock_*_armoured_truck.obj "$mod/models/"
cp mods/luanttd_core/textures/bl_stock_*_armoured_truck_atlas.png "$base"/mods/luanttd_core/textures/{bl_grass*,bl_road_10_plain_q*}.png "$mod/textures/"
printf 'gameid = armoured_art\nbackend = sqlite3\nplayer_backend = sqlite3\nauth_backend = sqlite3\nmod_storage_backend = sqlite3\n' > "$out/world/world.mt"
printf 'port = %s\nserver_announce = false\nbind_address = 127.0.0.1\nprometheus_listener_address = 127.0.0.1:%s\n' "$port" "$port" > "$out/server.conf"
printf 'screen_w = 1290\nscreen_h = 800\nenable_sound = false\nviewing_range = 80\n' >"$out/client.conf"
export PATH="$tools/run/bin:$tools/usr/bin:$PATH" LD_LIBRARY_PATH="$tools/usr/lib/x86_64-linux-gnu${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
export DISPLAY="127.0.0.1:$disp" HOME="$out/home" LIBGL_ALWAYS_SOFTWARE=1 MESA_SHADER_CACHE_DISABLE=1
export XDG_CACHE_HOME="$out/cache" LUANTI_GAME_PATH="$out/games" MINETEST_GAME_PATH="$out/games"
pids=()
cleanup(){ for id in "${pids[@]}"; do kill "$id" 2>/dev/null || true; done; wait || true; }
trap cleanup EXIT
cc -shared -fPIC "$base/tests/native_loopback.c" -ldl -o "$out/loopback.so"
env LD_PRELOAD="$out/loopback.so" Xvfb ":$disp" -screen 0 1290x800x24 -listen tcp -nolisten local -nolisten unix -ac -noreset >"$out/xvfb.log" 2>&1 &
pids+=($!)
for _ in {1..40}; do xdpyinfo >/dev/null 2>&1 && break; sleep .20; done
xdpyinfo >/dev/null || { cat "$out/xvfb.log"; exit 1; }
luantiserver --world "$out/world" --gameid armoured_art --config "$out/server.conf" --logfile '' >"$out/server.log" 2>&1 &
pids+=($!)
mark(){ for _ in {1..125}; do grep -q "$1" "$out/server.log" && return; sleep .2; done; tail -50 "$out/"{server,client}.log; return 1; }
mark 'listening on'
luanti --go --address 127.0.0.1 --port "$port" --name ArmouredReview --password '' --config "$out/client.conf" --logfile '' >"$out/client.log" 2>&1 &
client=$!;pids+=($client)
mark NATIVE_ARMOURED_ART_ALL_READY
win=$(xdotool search --sync --onlyvisible --pid "$client"|tail -1)
xdotool windowfocus --sync "$win"
xdotool mousemove 645 400
sleep 2.8
import -window root -quality 93 "$out/native_lineup.jpg"
xdotool key t; sleep .3; xdotool type "/rearproof"; xdotool key Return; sleep 2.6
import -window root -quality 93 "$out/native_rear.jpg"
grep 'ARMOURED VEHICLE VISUAL READY' "$out/server.log"
! grep -Ei 'ERROR\[|could not load' "$out/server.log" "$out/client.log"
python3 - "$out" <<'PY'
from pathlib import Path
import sys
from PIL import Image
root=Path(sys.argv[1])
for name in ("native_lineup","native_rear"):
    im=Image.open(root/(name+".jpg")).convert("RGB").crop((220,100,1070,730))
    count=sum(35<r<160 and 60<g<180 and 75<b<222 and g>r+10 and b>g+11 for r,g,b in im.getdata())
    assert count>5000,(name,count)
    print(name,count,"blue original mesh pixels")
print("NATIVE_ARMOURED_ART_PASS")
PY
