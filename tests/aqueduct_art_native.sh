#!/usr/bin/env bash
# Native graphical rendering of the actual aqueduct OBJ and atlas under Luanti.
# Inputs match tests/native.sh; isolated world and profile, no existing saves.
set -euo pipefail
cd "$(dirname "$0")/.."
repo=$PWD
if [[ -n ${BAYLINE_NATIVE_TOOLS:-} ]]; then
  tools=$(realpath "$BAYLINE_NATIVE_TOOLS")
  export PATH="$tools/run/bin:$tools/usr/bin:$PATH"
  export LD_LIBRARY_PATH="$tools/usr/lib/x86_64-linux-gnu${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
fi
out=$(mktemp -d "${TMPDIR:-/tmp}/luanttd-aqueduct-art.XXXXXX")
echo "Native aqueduct evidence: $out"
disp=${BAYLINE_NATIVE_DISPLAY:-129}
port=${BAYLINE_NATIVE_PORT:-39429}
pids=()
cleanup() {
  for pid in "${pids[@]}"; do kill -TERM "$pid" 2>/dev/null || true; done
  wait || true
}
trap cleanup EXIT
mod="$out/games/aqueduct_art/mods/waterwaypreview"
mkdir -p "$mod/"{models,textures} "$out/"{world,home,cache}
printf 'title = LuanTTD aqueduct fixture\n' > "$out/games/aqueduct_art/game.conf"
printf 'name = waterwaypreview\n' > "$mod/mod.conf"
cp tests/aqueduct_art_native.lua "$mod/init.lua"
cp mods/luanttd_core/models/{bl_aqueduct_*,bl_town_flyer.obj,bl_harbor_ferry.obj,bl_rail_track_2.obj,bl_steam.obj} "$mod/models/"
cp mods/luanttd_core/textures/{bl_aqueduct,bl_grass*,bl_road_5_plain_q*,bl_water0,bl_water_side,bl_vehicle_palette,bl_harbor_ferry_palette,bl_rail_atlas}.png "$mod/textures/"
printf 'gameid = aqueduct_art\nbackend = sqlite3\nplayer_backend = sqlite3\nauth_backend = sqlite3\nmod_storage_backend = sqlite3\n' > "$out/world/world.mt"
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
luantiserver --world "$out/world" --config "$out/server.conf" --gameid aqueduct_art --logfile "" > "$out/server.log" 2>&1 &
pids+=("$!")
for _ in {1..40}; do if grep -q 'listening' "$out/server.log"; then break; fi; sleep .25; done
grep -q 'listening' "$out/server.log" || { cat "$out/server.log"; exit 1; }
luanti --go --address 127.0.0.1 --port "$port" --config "$out/client.conf" --name AqueductQA --logfile "" > "$out/client.log" 2>&1 &
client=$!
pids+=("$client")
for _ in {1..120}; do if grep -q AQUEDUCT_ART_FIXTURE_READY "$out/server.log"; then break; fi; sleep .25; done
grep -q AQUEDUCT_ART_FIXTURE_READY "$out/server.log" || { cat "$out/"{server,client}.log; exit 1; }
win=$(xdotool search --sync --onlyvisible --pid "$client"|tail -1)
xdotool windowfocus --sync "$win"
xdotool mousemove 650 430
sleep 3
xdotool key t; sleep .2; xdotool type "/showaqueduct crest"; xdotool key Return
sleep 2
import -window root "$out/crest.png"
xdotool key t; sleep .2; xdotool type "/showaqueduct approach"; xdotool key Return
sleep 3
import -window root "$out/approach.png"
xdotool key t; sleep .2; xdotool type "/showaqueduct below"; xdotool key Return
sleep 3
import -window root "$out/below.png"
if grep -Ei 'ERROR\[|could not load' "$out/client.log"; then exit 1; fi
python3 - "$out" <<'PYQA'
from pathlib import Path
from PIL import Image
import sys

colors=[]
for name in ("crest","approach","below"):
    im=Image.open(Path(sys.argv[1])/(name+".png")).convert("RGB").crop((150,150,1150,790))
    stone=sum(90<=r<193 and 87<g<190 and 78<b<177 and 0<r-g<20 and 5<g-b<29
               for r,g,b in (im.get_flattened_data() if hasattr(im,"get_flattened_data") else im.getdata()))
    assert stone>250,(name,stone)
    colors.append(stone)
print(f"PASS: real aqueduct OBJ and atlas rendered in three Linux Luanti views, masonry pixels {colors}")
PYQA
