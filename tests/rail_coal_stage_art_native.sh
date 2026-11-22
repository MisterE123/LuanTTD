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
out=$(mktemp -d "${TMPDIR:-/tmp}/luanttd-rail-coal-art.XXXXXX")
echo "Native coal rail transfer evidence: $out"
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
printf 'title = LuanTTD coal rail transfer art fixture\n' > "$out/games/rail_art/game.conf"
printf 'name = railpreview\n' > "$mod/mod.conf"
cp tests/rail_coal_stage_art_native.lua "$mod/init.lua"
cp mods/luanttd_core/models/{bl_rail_track_1.obj,bl_rail_track_2.obj,bl_rail_kirby_paul_tank.obj,bl_rail_open_wagon.obj,bl_rail_coal_stage_*.obj,bl_coal_mine_0_*.obj,bl_power_station_*.obj} "$mod/models/"
cp mods/luanttd_core/textures/{bl_rail_atlas,bl_rail_wagon_atlas,bl_rail_kirby_paul_tank,bl_grass*,bl_rail_coal_stage_atlas,bl_coal_mine_atlas,bl_power_station_atlas}.png "$mod/textures/"
if [[ ${BAYLINE_STOCK_COAL_WAGON_NATIVE:-0} = 1 ]]; then
  cp mods/luanttd_core/models/bl_rail_coal_wagon_{empty,loaded}.obj "$mod/models/"
  cp mods/luanttd_core/textures/bl_rail_coal_wagon_atlas.png "$mod/textures/"
fi
printf 'gameid = rail_art\nbackend = sqlite3\nplayer_backend = sqlite3\nauth_backend = sqlite3\nmod_storage_backend = sqlite3\n' > "$out/world/world.mt"
cat > "$out/server.conf" <<EOF
port = $port
prometheus_listener_address = 127.0.0.1:$port
server_announce = false
bind_address = 127.0.0.1
EOF
if [[ ${BAYLINE_STOCK_COAL_WAGON_NATIVE:-0} = 1 ]]; then
  printf '\nnative_stock_coal_wagon = true\n' >> "$out/server.conf"
fi
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
for _ in {1..120}; do if grep -q COAL_RAIL_STAGE_MESH_FIXTURE_READY "$out/server.log"; then break; fi; sleep .25; done
grep -q COAL_RAIL_STAGE_MESH_FIXTURE_READY "$out/server.log" || { cat "$out/"{server,client}.log; exit 1; }
win=$(xdotool search --sync --onlyvisible --pid "$client"|tail -1)
xdotool windowfocus --sync "$win"
xdotool mousemove 650 430
sleep 3
xdotool key t; sleep .2; xdotool type "/showstage survey"; xdotool key Return
sleep 2
xdotool key F2
sleep .3
import -window root "$out/coal-industry-survey.png"
xdotool key t; sleep .2; xdotool type "/showstage loading"; xdotool key Return
sleep 3
import -window root "$out/cedar-loading.png"
xdotool key t; sleep .2; xdotool type "/showstage receiving"; xdotool key Return
sleep 3
import -window root "$out/riverbend-tipping.png"
if [[ ${BAYLINE_STOCK_COAL_WAGON_NATIVE:-0} = 1 ]]; then
  for state in empty loaded; do
    xdotool key t; sleep .2; xdotool type "/showstage cargo"; xdotool key Return
    sleep 3
    import -window root "$out/coal-wagon-$state.png"
  done
  grep -q COAL_WAGON_ART_EMPTY_SHAPE_MOUNTED "$out/server.log"
  grep -q COAL_WAGON_ART_LOADED_SHAPE_MOUNTED "$out/server.log"
  python3 - "$out" <<'WAGON_QA'
from pathlib import Path
from PIL import Image,ImageChops
import sys
d=Path(sys.argv[1])
a,b=(Image.open(d/("coal-wagon-"+s+".png")).convert("RGB") for s in ("empty","loaded"))
changed=ImageChops.difference(a,b).getbbox()
assert changed is not None and (changed[2]-changed[0])>40 and (changed[3]-changed[1])>28,changed
assert 550<changed[0]<635 and 660<changed[2]<760 and 360<changed[1]<450 and 470<changed[3]<555,changed
print("COAL_WAGON_NATIVE_SWAP_PASS",changed)
WAGON_QA
fi
! grep -Ei 'error|could not load' "$out/client.log"
python3 - "$out" <<'PYQA'
from pathlib import Path
from PIL import Image
import sys

for name in ("coal-industry-survey","cedar-loading","riverbend-tipping"):
    im=Image.open(Path(sys.argv[1])/(name+".png")).convert("RGB").crop((120,140,1160,820))
    rgb=list(im.get_flattened_data() if hasattr(im,"get_flattened_data") else im.getdata())
    steel=sum(88<r<211 and 99<g<225 and 99<b<211 and max(r,g,b)-min(r,g,b)<27 for r,g,b in rgb)
    masonry=sum(85<r<206 and 55<g<151 and 25<b<129 and r>1.18*g and g>1.15*b for r,g,b in rgb)
    print(f"{name}: {steel} steel and {masonry} masonry/rust pixels")
    assert steel>170 and masonry>260,(name,steel,masonry)
PYQA
echo "RAIL_COAL_STAGE_NATIVE_PASS $out"
