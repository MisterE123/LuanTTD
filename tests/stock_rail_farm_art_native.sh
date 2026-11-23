#!/usr/bin/env bash
# Native graphical rendering of the actual shipped OBJ and atlas under Luanti.
# Inputs match tests/native.sh; isolated world and profile, no existing saves.
set -euo pipefail
cd "$(dirname "$0")/.."
repo=${LUANTTD_BASE:-$PWD}
if [[ -n ${BAYLINE_NATIVE_TOOLS:-} ]]; then
  tools=$(realpath "$BAYLINE_NATIVE_TOOLS")
  export PATH="$tools/run/bin:$tools/usr/bin:$PATH"
  export LD_LIBRARY_PATH="$tools/usr/lib/x86_64-linux-gnu${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
fi
out=$(mktemp -d "${TMPDIR:-/tmp}/luanttd-stock-rail-farm-art.XXXXXX")
echo "Native stock farm wagons art evidence: $out"
disp=${BAYLINE_NATIVE_DISPLAY:-243}
port=${BAYLINE_NATIVE_PORT:-39987}
pids=()
cleanup() {
  for pid in "${pids[@]}"; do kill -TERM "$pid" 2>/dev/null || true; done
  wait || true
}
trap cleanup EXIT
mod="$out/games/rail_art/mods/railpreview"
mkdir -p "$mod/"{models,textures} "$out/"{world,home,cache}
printf 'title = LuanTTD stock farm wagons art fixture\n' > "$out/games/rail_art/game.conf"
printf 'name = railpreview\n' > "$mod/mod.conf"
cp tests/stock_rail_farm_art_native.lua "$mod/init.lua"
cp "$repo"/mods/luanttd_core/models/{bl_rail_track_1.obj,bl_rail_track_2.obj,bl_rail_track_3.obj,bl_rail_track_32.obj,bl_rail_track_33.obj,bl_rail_depot_1.obj,bl_rail_platform_2.obj} "$mod/models/"
cp mods/luanttd_core/models/{bl_rail_livestock_van,bl_rail_grain_hopper_empty,bl_rail_grain_hopper_loaded}.obj "$mod/models/"
cp "$repo"/mods/luanttd_core/textures/{bl_rail_atlas,bl_rail_architecture_atlas,bl_grass*}.png "$mod/textures/"
cp mods/luanttd_core/textures/bl_rail_{livestock_van,grain_hopper}_atlas.png "$mod/textures/"
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
for _ in {1..120}; do if grep -q RAIL_FARM_MESH_FIXTURE_READY "$out/server.log"; then break; fi; sleep .25; done
grep -q RAIL_FARM_MESH_FIXTURE_READY "$out/server.log" || { cat "$out/"{server,client}.log; exit 1; }
win=$(xdotool search --sync --onlyvisible --pid "$client"|tail -1)
xdotool windowfocus --sync "$win"
xdotool mousemove 650 430
sleep 3
xdotool key F2
sleep 2
for shot in empty loaded survey curve; do
  xdotool key t; sleep .4; xdotool type --delay 35 "/showfarm $shot"; sleep .35; xdotool key Return
  sleep 2.7
  import -window root "$out/farm-$shot.png"
done
grep -q "RAIL_FARM_VISUAL_STAGE empty" "$out/server.log"
grep -q "RAIL_FARM_VISUAL_STAGE loaded" "$out/server.log"
! grep -Ei 'ERROR\[|could not load' "$out/client.log"
python3 - "$out" <<'PYQA'
from pathlib import Path
from PIL import Image,ImageChops
import sys
p=Path(sys.argv[1])
def frame(name):return Image.open(p/("farm-"+name+".png")).convert("RGB")
def pix(im):return im.get_flattened_data() if hasattr(im,"get_flattened_data") else im.getdata()
a,b=(frame(view).crop((120,120,1160,820)) for view in ("empty","loaded"))
diff=ImageChops.difference(a,b)
box=diff.getbbox()
assert box and box[3]-box[1]>30 and box[2]-box[0]>70,box
gold={}
for view in ("empty","loaded","survey","curve"):
    rgb=frame(view).crop((120,120,1160,820))
    gold[view]=sum(95<r<232 and 61<g<204 and 22<b<163 and r>g+14 and g>b+21 for r,g,b in pix(rgb))
    print(f"native {view}: {gold[view]} golden cargo pixels")
assert gold["loaded"]>gold["empty"]+400,gold
assert sum(23<r<145 and 43<g<183 and 65<b<205 and b>g+10 and g>r+12
           for r,g,b in pix(frame("loaded").crop((120,120,1160,820))))>1000
print(f"STOCK_RAIL_FARM_NATIVE_ART_PASS {box}")
PYQA
