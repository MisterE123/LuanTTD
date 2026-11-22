#!/usr/bin/env bash
# Native graphical rendering of the actual shipped OBJ and atlas under Luanti.
# Inputs match tests/native.sh; isolated world and profile, no existing saves.
set -euo pipefail
cd "$(dirname "$0")/.."
repo=$PWD
sprung=false
if [[ ${1:-} == --sprung ]]; then sprung=true; fi
if [[ -n ${BAYLINE_NATIVE_TOOLS:-} ]]; then
  tools=$(realpath "$BAYLINE_NATIVE_TOOLS")
  export PATH="$tools/run/bin:$tools/usr/bin:$PATH"
  export LD_LIBRARY_PATH="$tools/usr/lib/x86_64-linux-gnu${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
fi
out=$(mktemp -d "${TMPDIR:-/tmp}/luanttd-rail-bridge-catenary.XXXXXX")
echo "Native rail bridge catenary evidence: $out"
disp=${BAYLINE_NATIVE_DISPLAY:-244}
port=${BAYLINE_NATIVE_PORT:-39244}
pids=()
cleanup() {
  for pid in "${pids[@]}"; do kill -TERM "$pid" 2>/dev/null || true; done
  wait || true
}
trap cleanup EXIT
mod="$out/games/rail_art/mods/railpreview"
mkdir -p "$mod/"{models,textures} "$out/"{world,home,cache}
printf 'title = LuanTTD rail bridge catenary fixture\n' > "$out/games/rail_art/game.conf"
printf 'name = railpreview\n' > "$mod/mod.conf"
{ printf 'local fixture_sprung_collector = %s\n' "$sprung"; cat tests/rail_bridge_catenary_native.lua; } > "$mod/init.lua"
if $sprung; then
  cp mods/bayline/models/{bl_rail_sh_{30,40}_body.obj,bl_rail_sh_collector.obj} "$mod/models/"
fi
cp mods/bayline/models/{bl_rail_track_1.obj,bl_rail_track_2.obj,bl_land_3.obj,bl_land_6.obj,bl_land_9.obj,bl_land_12.obj,bl_rail_sh_{30,40}.obj,bl_rail_passenger_wagon.obj,bl_rail_bridge_wood_*,bl_rail_bridge_catenary_*,bl_rail_catenary_{1,2}_{0,1}.obj} "$mod/models/"
cp mods/bayline/textures/{bl_rail_atlas,bl_rail_wagon_atlas,bl_grass*,bl_water*,bl_rail_bridge_wood,bl_rail_catenary_atlas,bl_rail_sh_{30,40}}.png "$mod/textures/"
cp mods/bayline/rail{_bridge,}_catenary_art.lua "$mod/"
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
for _ in {1..120}; do if grep -q RAIL_BRIDGE_CATENARY_FIXTURE_READY "$out/server.log"; then break; fi; sleep .25; done
grep -q RAIL_BRIDGE_CATENARY_FIXTURE_READY "$out/server.log" || { cat "$out/"{server,client}.log; exit 1; }
win=$(xdotool search --sync --onlyvisible --pid "$client"|tail -1)
xdotool windowfocus --sync "$win"
xdotool mousemove 650 430
sleep 3
xdotool key F2
shots=(harbor stock_ramp bearing river contact cross_axis flat_head)
if $sprung; then shots+=(sprung_near sprung_far); fi
for shot in "${shots[@]}"; do
  xdotool key t; sleep .2; xdotool type "/showbridgewire $shot"; xdotool key Return
  sleep 2.5
  import -window root "$out/$shot.png"
done
! grep -Ei 'ERROR\[|could not load' "$out/client.log"
python3 - "$out" "${shots[@]}" <<'PYQA'
from pathlib import Path
from PIL import Image
import sys
for name in sys.argv[2:]:
    im=Image.open(Path(sys.argv[1])/(name+".png")).convert("RGB").crop((120,120,1170,810))
    rgb=list(im.get_flattened_data() if hasattr(im,"get_flattened_data") else im.getdata())
    metal=sum(55<r<174 and 68<g<180 and 68<b<180 and g>r+5 and abs(b-g)<18 for r,g,b in rgb)
    timber=sum(65<r<194 and 44<g<150 and 27<b<117 and 1.18<r/(g or 1)<1.75 and g>b for r,g,b in rgb)
    print(f"{name}: {metal} bracket/wire-like steel and {timber} timber/masonry pixels")
    assert metal>65 and timber>125,(name,metal,timber)
PYQA
echo "RAIL_BRIDGE_CATENARY_NATIVE_PASS $out"
