#!/usr/bin/env bash
# Native graphical Yate Cargo Ship, actual harbour meshes, exact water level.
# Inputs match tests/native.sh; isolated world and profile, no existing saves.
set -euo pipefail
cd "$(dirname "$0")/.."
repo=$PWD
if [[ -n ${BAYLINE_NATIVE_TOOLS:-} ]]; then
  tools=$(realpath "$BAYLINE_NATIVE_TOOLS")
  export PATH="$tools/run/bin:$tools/usr/bin:$PATH"
  export LD_LIBRARY_PATH="$tools/usr/lib/x86_64-linux-gnu${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
fi
out=$(mktemp -d "${TMPDIR:-/tmp}/luanttd-yate-art.XXXXXX")
echo "Native Yate evidence: $out"
disp=${BAYLINE_NATIVE_DISPLAY:-183}
port=${BAYLINE_NATIVE_PORT:-39883}
pids=()
cleanup() {
  for pid in "${pids[@]}"; do kill -TERM "$pid" 2>/dev/null || true; done
  wait || true
}
trap cleanup EXIT
mod="$out/games/yate_art/mods/yate"
mkdir -p "$mod/"{models,textures} "$out/"{world,home,cache}
printf 'title = LuanTTD Yate Cargo Ship art fixture\n' > "$out/games/yate_art/game.conf"
printf 'name = yate\n' > "$mod/mod.conf"
cp tests/yate_cargo_ship_art_native.lua "$mod/init.lua"
cp mods/bayline/models/{bl_yate_cargo_ship.obj,bl_ship_dock_ramp_1.obj,bl_ship_dock_pier_1.obj,bl_ship_depot_1_?.obj,bl_ship_lock_*_1.obj,bl_ship_lock_chamber_water.obj,bl_ship_lock_gate_*_closed.obj} "$mod/models/"
cp mods/bayline/textures/{bl_yate_cargo_ship_atlas,bl_ship_facilities_atlas,bl_ship_lock_atlas,bl_grass?,bl_grass_side,bl_water?,bl_water_side}.png "$mod/textures/"
printf 'gameid = yate_art\nbackend = sqlite3\nplayer_backend = sqlite3\nauth_backend = sqlite3\nmod_storage_backend = sqlite3\n' > "$out/world/world.mt"
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
luantiserver --world "$out/world" --config "$out/server.conf" --gameid yate_art --logfile "" > "$out/server.log" 2>&1 &
pids+=("$!")
for _ in {1..40}; do if grep -q 'listening' "$out/server.log"; then break; fi; sleep .25; done
grep -q 'listening' "$out/server.log" || { cat "$out/server.log"; exit 1; }
luanti --go --address 127.0.0.1 --port "$port" --config "$out/client.conf" --name YateQA --logfile "" > "$out/client.log" 2>&1 &
client=$!
pids+=("$client")
for _ in {1..120}; do if grep -q YATE_MESH_FIXTURE_READY "$out/server.log"; then break; fi; sleep .25; done
grep -q YATE_MESH_FIXTURE_READY "$out/server.log" || { cat "$out/"{server,client}.log; exit 1; }
win=$(xdotool search --sync --onlyvisible --pid "$client"|tail -1)
xdotool windowfocus --sync "$win"
xdotool mousemove 650 430
sleep 3
xdotool key F2
sleep 2
for shot in waterline cabin harbour depot lock; do
  xdotool key t; sleep .2; xdotool type "/showyate $shot"; xdotool key Return
  sleep 2.6
  import -window root "$out/yate-$shot.png"
done
! grep -Ei 'error|could not load' "$out/client.log"
python3 - "$out" <<'PYQA'
from PIL import Image
from pathlib import Path
import sys
for name in ("waterline","cabin","harbour","depot","lock"):
    i=Image.open(Path(sys.argv[1])/f"yate-{name}.png").convert("RGB").crop((240,155,1060,750))
    pixels=list(i.get_flattened_data() if hasattr(i,"get_flattened_data") else i.getdata())
    derrick=sum(97<r<241 and 32<g<151 and 15<b<115 and r>g+38 and g>b+14 for r,g,b in pixels)
    afterhouse=sum(135<r<235 and 0<=r-g<=7 and -1<=b-r<=9 for r,g,b in pixels)
    shipblue=sum((25<r<35 and 56<g<76 and 84<b<113) or (49<r<59 and 85<g<99 and 114<b<131) for r,g,b in pixels)
    assert derrick>120 and afterhouse>480 and shipblue>170,(name,derrick,afterhouse,shipblue)
    print(f"{name}: {derrick} warm equipment, {afterhouse} ivory bridge, {shipblue} blue pixels")
print("YATE_NATIVE_ART_PASS")
PYQA
