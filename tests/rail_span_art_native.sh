#!/usr/bin/env bash
# Native graphical rendering of the actual shipped OBJ and atlas under Luanti.
# Inputs match tests/native.sh; isolated world and profile, no existing saves.
set -euo pipefail
cd "$(dirname "$0")/.."
repo=$PWD
if [[ -n ${BAYLINE_NATIVE_TOOLS:-} ]]; then
  tools=$(realpath "$BAYLINE_NATIVE_TOOLS")
  export PATH="$tools/run/bin:$tools/usr/bin:$PATH"
  export LD_LIBRARY_PATH="$tools/usr/lib/x86_64-linux-gnu${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
fi
out=$(mktemp -d "${TMPDIR:-/tmp}/luanttd-rail-span-art.XXXXXX")
echo "Native rail span art evidence: $out"
disp=${BAYLINE_NATIVE_DISPLAY:-117}
port=${BAYLINE_NATIVE_PORT:-39417}
pids=()
cleanup() {
  for pid in "${pids[@]}"; do kill -TERM "$pid" 2>/dev/null || true; done
  wait || true
}
trap cleanup EXIT
mod="$out/games/rail_art/mods/railpreview"
mkdir -p "$mod/"{models,textures} "$out/"{world,home,cache}
printf 'title = LuanTTD rail span art fixture\n' > "$out/games/rail_art/game.conf"
printf 'name = railpreview\n' > "$mod/mod.conf"
cp tests/rail_span_art_native.lua "$mod/init.lua"
cp mods/luanttd_core/models/{bl_rail_track_1.obj,bl_rail_track_2.obj,bl_land_3.obj,bl_land_6.obj,bl_land_9.obj,bl_land_12.obj,bl_steam.obj,bl_electric.obj,bl_rail_passenger_wagon.obj,bl_rail_open_wagon.obj,bl_rail_bridge_wood_*,bl_rail_tunnel_portal_*} "$mod/models/"
cp mods/luanttd_core/textures/{bl_rail_atlas,bl_rail_wagon_atlas,bl_grass*,bl_water*,bl_rail_bridge_wood,bl_rail_tunnel_portal,bl_vehicle_palette}.png "$mod/textures/"
printf 'gameid = rail_art\nbackend = sqlite3\nplayer_backend = sqlite3\nauth_backend = sqlite3\nmod_storage_backend = sqlite3\n' > "$out/world/world.mt"
cat > "$out/server.conf" <<EOF
port = $port
prometheus_listener_address = 127.0.0.1:$port
server_announce = false
bind_address = 127.0.0.1
EOF
cat > "$out/client.conf" <<'EOF'
screen_w = 1300
screen_h = 860
fullscreen = false
enable_sound = false
viewing_range = 80
fps_max = 30
EOF
export HOME="$out/home" XDG_CACHE_HOME="$out/cache" XDG_CONFIG_HOME="$out/home/.config" \
  LUANTI_GAME_PATH="$out/games" MINETEST_GAME_PATH="$out/games" \
  LIBGL_ALWAYS_SOFTWARE=1 ALSOFT_DRIVERS=null
export DISPLAY=":$disp" XAUTHORITY="$out/Xauthority"
opts=(-nolisten tcp)
lib=()
if [[ ${BAYLINE_NATIVE_TCP:-0} == 1 ]]; then
  cc -shared -fPIC "$repo/tests/native_loopback.c" -ldl -o "$out/loopback.so"
  export DISPLAY="127.0.0.1:$disp"
  opts=(-listen tcp -nolisten unix -nolisten local)
  lib=(env "LD_PRELOAD=$out/loopback.so${LD_PRELOAD:+:$LD_PRELOAD}")
fi
touch "$XAUTHORITY"
cookie=$(python3 -c 'import secrets; print(secrets.token_hex(16))')
xauth -f "$XAUTHORITY" add "$DISPLAY" MIT-MAGIC-COOKIE-1 "$cookie"
"${lib[@]}" Xvfb ":$disp" -screen 0 1300x860x24 "${opts[@]}" -auth "$XAUTHORITY" -noreset >"$out/xvfb.log" 2>&1 &
pids+=("$!")
for _ in {1..40}; do if xdpyinfo >/dev/null 2>&1; then break; fi; sleep .25; done
if ! xdpyinfo >/dev/null 2>&1; then cat "$out/xvfb.log"; exit 1; fi
luantiserver --world "$out/world" --config "$out/server.conf" --gameid rail_art --logfile "" > "$out/server.log" 2>&1 &
pids+=("$!")
for _ in {1..40}; do if grep -q 'listening' "$out/server.log"; then break; fi; sleep .25; done
grep -q 'listening' "$out/server.log" || { cat "$out/server.log"; exit 1; }
luanti --go --address 127.0.0.1 --port "$port" --config "$out/client.conf" --name RailQA --logfile "" > "$out/client.log" 2>&1 &
client=$!
pids+=("$client")
for _ in {1..120}; do if grep -q RAIL_SPAN_MESH_FIXTURE_READY "$out/server.log"; then break; fi; sleep .25; done
grep -q RAIL_SPAN_MESH_FIXTURE_READY "$out/server.log" || { cat "$out/"{server,client}.log; exit 1; }
win=$(xdotool search --sync --onlyvisible --pid "$client"|tail -1)
xdotool windowfocus --sync "$win"
xdotool mousemove 650 430
sleep 3
xdotool key t; sleep .2; xdotool type "/showrailspan bridge"; xdotool key Return
sleep 2
xdotool key F2
sleep .3
import -window root "$out/timber-trestle.png"
xdotool key t; sleep .2; xdotool type "/showrailspan crown"; xdotool key Return
sleep 3
import -window root "$out/bridge-railhead.png"
xdotool key t; sleep .2; xdotool type "/showrailspan bore"; xdotool key Return
sleep 3
import -window root "$out/rail-tunnel-mouth.png"
! grep -Ei 'error|could not load' "$out/client.log"
python3 - "$out" <<'PYQA'
from pathlib import Path
from PIL import Image
import sys

for name in ("timber-trestle","bridge-railhead","rail-tunnel-mouth"):
    im=Image.open(Path(sys.argv[1])/(name+".png")).convert("RGB").crop((120,140,1160,820))
    rgb=list(im.getdata())
    steel=sum(125<r<220 and 124<g<230 and 130<b<231 and max(r,g,b)-min(r,g,b)<21 for r,g,b in rgb)
    timber=sum(65<r<194 and 44<g<150 and 27<b<117 and 1.18<r/(g or 1)<1.75 and g>b for r,g,b in rgb)
    print(f"{name}: {steel} polished pixels, {timber} timber/masonry pixels")
    assert steel>130 and timber>430,(name,steel,timber)
PYQA
echo "RAIL_SPAN_NATIVE_ART_PASS $out"
