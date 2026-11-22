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
out=$(mktemp -d "${TMPDIR:-/tmp}/luanttd-sh8p-art.XXXXXX")
echo "Native SH 8P art evidence: $out"
disp=${BAYLINE_NATIVE_DISPLAY:-218}
port=${BAYLINE_NATIVE_PORT:-39918}
pids=()
cleanup() {
  for pid in "${pids[@]}"; do kill -TERM "$pid" 2>/dev/null || true; done
  wait || true
}
trap cleanup EXIT
mod="$out/games/rail_art/mods/railpreview"
mkdir -p "$mod/"{models,textures} "$out/"{world,home,cache}
printf 'title = LuanTTD SH 8P art fixture\n' > "$out/games/rail_art/game.conf"
printf 'name = railpreview\n' > "$mod/mod.conf"
cp tests/sh_8p_art_native.lua "$mod/init.lua"
cp mods/luanttd_core/models/{bl_rail_track_1.obj,bl_rail_track_2.obj,bl_rail_track_3.obj,bl_rail_track_32.obj,bl_rail_track_33.obj,bl_rail_depot_1.obj,bl_rail_sh_8p.obj,bl_rail_open_wagon.obj,bl_rail_passenger_wagon.obj} "$mod/models/"
cp mods/luanttd_core/textures/{bl_rail_atlas,bl_rail_architecture_atlas,bl_rail_wagon_atlas,bl_rail_sh_8p,bl_grass*}.png "$mod/textures/"
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
for _ in {1..120}; do if grep -q SH_8P_MESH_FIXTURE_READY "$out/server.log"; then break; fi; sleep .25; done
grep -q SH_8P_MESH_FIXTURE_READY "$out/server.log" || { cat "$out/"{server,client}.log; exit 1; }
win=$(xdotool search --sync --onlyvisible --pid "$client"|tail -1)
xdotool windowfocus --sync "$win"
xdotool mousemove 650 430
sleep 3
xdotool key F2
sleep 2
for shot in front side rear street survey curve; do
  xdotool key t; sleep .2; xdotool type "/showsh8p $shot"; xdotool key Return
  sleep 2.7
  import -window root "$out/sh8p-$shot.png"
done
! grep -Ei 'ERROR\[|could not load' "$out/client.log"
python3 - "$out" <<'PYQA'
from pathlib import Path
from PIL import Image
import sys

for name in ("sh8p-front","sh8p-side","sh8p-rear","sh8p-street","sh8p-survey","sh8p-curve"):
    im=Image.open(Path(sys.argv[1])/(name+".png")).convert("RGB").crop((120,140,1160,820))
    rgb=list(im.get_flattened_data() if hasattr(im,"get_flattened_data") else im.getdata())
    axle_green=sum(27<r<108 and 48<g<144 and 39<b<117 and r+14<g and g>b+7 and 0<=b-r<=24 for r,g,b in rgb)
    red=sum(70<r<194 and 32<g<107 and 27<b<104 and r>g+26 and r>b+29 for r,g,b in rgb)
    print(f"{name}: {axle_green} olive boiler swatch and {red} bright red beam pixels")
    assert axle_green>270 and red>80,(name,axle_green,red)
PYQA
echo "SH_8P_NATIVE_ART_PASS $out"
