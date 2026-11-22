#!/usr/bin/env bash
# Native Coleman Count, actual stock Country Airport meshes and gear states.
# Inputs match tests/native.sh; isolated world and profile, no existing saves.
set -euo pipefail
cd "$(dirname "$0")/.."
repo=$PWD
if [[ -n ${BAYLINE_NATIVE_TOOLS:-} ]]; then
  tools=$(realpath "$BAYLINE_NATIVE_TOOLS")
  export PATH="$tools/run/bin:$tools/usr/bin:$PATH"
  export LD_LIBRARY_PATH="$tools/usr/lib/x86_64-linux-gnu${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
fi
out=$(mktemp -d "${TMPDIR:-/tmp}/luanttd-coleman-art.XXXXXX")
echo "Native Coleman Count evidence: $out"
disp=${BAYLINE_NATIVE_DISPLAY:-193}
port=${BAYLINE_NATIVE_PORT:-39893}
pids=()
cleanup() {
  for pid in "${pids[@]}"; do kill -TERM "$pid" 2>/dev/null || true; done
  wait || true
}
trap cleanup EXIT
mod="$out/games/coleman_art/mods/coleman"
mkdir -p "$mod/"{models,textures} "$out/"{world,home,cache}
printf 'title = LuanTTD Coleman Count art fixture\n' > "$out/games/coleman_art/game.conf"
printf 'name = coleman\n' > "$mod/mod.conf"
cp tests/coleman_count_art_native.lua "$mod/init.lua"
cp mods/luanttd_core/models/{bl_coleman_count.obj,bl_coleman_count_flight.obj,bl_bayshore_trimotor.obj,bl_small_airport_?_?.obj} "$mod/models/"
cp mods/luanttd_core/textures/{bl_coleman_count_atlas,bl_bayshore_trimotor_palette,bl_small_airport_atlas,bl_grass?,bl_grass_side}.png "$mod/textures/"
printf 'gameid = coleman_art\nbackend = sqlite3\nplayer_backend = sqlite3\nauth_backend = sqlite3\nmod_storage_backend = sqlite3\n' > "$out/world/world.mt"
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
luantiserver --world "$out/world" --config "$out/server.conf" --gameid coleman_art --logfile "" > "$out/server.log" 2>&1 &
pids+=("$!")
for _ in {1..40}; do if grep -q 'listening' "$out/server.log"; then break; fi; sleep .25; done
grep -q 'listening' "$out/server.log" || { cat "$out/server.log"; exit 1; }
luanti --go --address 127.0.0.1 --port "$port" --config "$out/client.conf" --name ColemanQA --logfile "" > "$out/client.log" 2>&1 &
client=$!
pids+=("$client")
for _ in {1..120}; do if grep -q COLEMAN_MESH_FIXTURE_READY "$out/server.log"; then break; fi; sleep .25; done
grep -q COLEMAN_MESH_FIXTURE_READY "$out/server.log" || { cat "$out/"{server,client}.log; exit 1; }
win=$(xdotool search --sync --onlyvisible --pid "$client"|tail -1)
xdotool windowfocus --sync "$win"
xdotool mousemove 650 430
sleep 3
xdotool key F2
sleep 2
for shot in apron_low apron_survey hangar gear_up; do
  xdotool key t; sleep .2; xdotool type "/showcoleman $shot"; xdotool key Return
  sleep 2.6
  import -window root "$out/coleman-$shot.png"
done
! grep -Ei 'error|could not load' "$out/client.log"
python3 - "$out" <<'PYQA'
from PIL import Image
from pathlib import Path
import sys
for name in ("apron_low","apron_survey","hangar","gear_up"):
    i=Image.open(Path(sys.argv[1])/f"coleman-{name}.png").convert("RGB").crop((240,155,1060,750))
    pp=list(i.get_flattened_data() if hasattr(i,"get_flattened_data") else i.getdata())
    livery=sum(29<r<112 and 72<g<144 and 102<b<178 and r+20<g and 23<b-r for r,g,b in pp)
    fin=sum(130<r<239 and abs(r-g)<=11 and abs(r-b)<=21 for r,g,b in pp)
    tip=sum(105<r<246 and 90<g<225 and 18<b<155 and r>g+15 and g>b+26 for r,g,b in pp)
    assert livery>110 and fin>130 and tip>25,(name,livery,fin,tip)
    print(f"{name}: {livery} Coleman blue, {fin} fuselage and {tip} brass/golden-tip pixels")
print("COLEMAN_NATIVE_ART_PASS")
PYQA
