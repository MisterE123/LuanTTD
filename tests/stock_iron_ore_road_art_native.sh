#!/usr/bin/env bash
# Original farm lorries; actual street stock-pose frame and true cargo swap.
# Inputs match tests/native.sh; isolated world and profile, no existing saves.
set -euo pipefail
cd "$(dirname "$0")/.."
repo=${LUANTTD_BASE:-$PWD}
if [[ -n ${BAYLINE_NATIVE_TOOLS:-} ]]; then
  tools=$(realpath "$BAYLINE_NATIVE_TOOLS")
  export PATH="$tools/run/bin:$tools/usr/bin:$PATH"
  export LD_LIBRARY_PATH="$tools/usr/lib/x86_64-linux-gnu${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
fi
out=$(mktemp -d "${TMPDIR:-/tmp}/luanttd-iron-ore-art.XXXXXX")
echo "Native Iron Ore Trucks evidence: $out"
disp=${BAYLINE_NATIVE_DISPLAY:-228}
port=${BAYLINE_NATIVE_PORT:-39940}
pids=()
cleanup() {
  for pid in "${pids[@]}"; do kill -TERM "$pid" 2>/dev/null || true; done
  wait || true
}
trap cleanup EXIT
mod="$out/games/farm_truck_art/mods/farmtrucks"
mkdir -p "$mod/"{models,textures} "$out/"{world,home,cache}
printf 'title = LuanTTD Iron Ore Lorry art fixture\n' > "$out/games/farm_truck_art/game.conf"
printf 'name = farmtrucks\n' > "$mod/mod.conf"
cp tests/stock_iron_ore_road_art_native.lua "$mod/init.lua"
mkdir -p "$mod/source/openttd"
cp "$repo"/tests/foster_bus_route.lua "$mod/"
cp "$repo"/mods/luanttd_core/{road_lanes.lua,road_motion_presentation.lua,road_motion_leg.lua,road_bridge_motion.lua} "$mod/source/"
cp "$repo"/mods/luanttd_core/openttd/{yapf_road_follow.lua,road_motion.lua,road_motion_data.lua} "$mod/source/openttd/"
cp mods/luanttd_core/models/bl_stock_{mps,uhl,chippy}_iron_ore_truck*.obj "$mod/models/"
cp mods/luanttd_core/textures/bl_stock_{mps,uhl,chippy}_iron_ore_truck_atlas.png "$mod/textures/"
cp "$repo"/mods/luanttd_core/textures/{bl_grass?,bl_grass_side}.png "$mod/textures/"
for mask in 3 5 6 9 10 12; do cp "$repo"/mods/luanttd_core/textures/bl_road_${mask}_plain_q?.png "$mod/textures/"; done
printf 'gameid = farm_truck_art\nbackend = sqlite3\nplayer_backend = sqlite3\nauth_backend = sqlite3\nmod_storage_backend = sqlite3\n' > "$out/world/world.mt"
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
luantiserver --world "$out/world" --config "$out/server.conf" --gameid farm_truck_art --logfile "" > "$out/server.log" 2>&1 &
pids+=("$!")
for _ in {1..40}; do if grep -q 'listening' "$out/server.log"; then break; fi; sleep .25; done
grep -q 'listening' "$out/server.log" || { cat "$out/server.log"; exit 1; }
luanti --go --address 127.0.0.1 --port "$port" --config "$out/client.conf" --name FarmQA --logfile "" > "$out/client.log" 2>&1 &
client=$!
pids+=("$client")
for _ in {1..120}; do if grep -q IRON_ORE_TRUCK_MESH_FIXTURE_READY "$out/server.log"; then break; fi; sleep .25; done
grep -q IRON_ORE_TRUCK_MESH_FIXTURE_READY "$out/server.log" || { cat "$out/"{server,client}.log; exit 1; }
win=$(xdotool search --sync --onlyvisible --pid "$client"|tail -1)
xdotool windowfocus --sync "$win"
xdotool mousemove 650 430
sleep 3
xdotool key F2
sleep 2
for shot in empty loaded mps uhl; do
  xdotool key t; sleep .2; xdotool type "/showoretruck $shot"; xdotool key Return
  sleep 2.6
  import -window root "$out/oretruck-$shot.png"
done
! grep -Ei 'error|could not load' "$out/client.log"
python3 - "$out" <<'PYQA'
from PIL import Image, ImageChops
from pathlib import Path
import sys
p=Path(sys.argv[1])
def frame(name):
    return Image.open(p/f"oretruck-{name}.png").convert("RGB")
z=ImageChops.difference(frame("empty"),frame("loaded"))
x0,y0,x1,y1=z.getbbox()
assert 240<x0<880 and 220<y0<620 and 390<x1<1070 and 280<y1<750,(x0,y0,x1,y1)
counts={}
for name in ("empty","loaded","mps","uhl"):
    i=frame(name).crop((240,150,1060,740))
    q=i.get_flattened_data() if hasattr(i,"get_flattened_data") else list(i.getdata())
    blue=sum(38<r<112 and 62<g<160 and 85<b<204 and r+12<g and g+9<b for r,g,b in q)
    grain=sum(65<r<210 and 25<g<146 and 13<b<109 and r>g+22 and g>b+12 for r,g,b in q)
    assert blue>300,(name,blue,grain)
    counts[name]=grain
    print(f"{name}: {blue} blue vehicle pixels and {grain} weathered iron ore pixels")
assert counts["loaded"]>counts["empty"]+1200
print("STOCK_IRON_ORE_ROAD_NATIVE_ART_PASS",z.getbbox())
PYQA
