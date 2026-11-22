#!/usr/bin/env bash
# Native Bakewell Cotswald LB-3, actual stock Country Airport meshes and gear states.
# Inputs match tests/native.sh; isolated world and profile, no existing saves.
set -euo pipefail
cd "$(dirname "$0")/.."
repo=$PWD
if [[ -n ${BAYLINE_NATIVE_TOOLS:-} ]]; then
  tools=$(realpath "$BAYLINE_NATIVE_TOOLS")
  export PATH="$tools/run/bin:$tools/usr/bin:$PATH"
  export LD_LIBRARY_PATH="$tools/usr/lib/x86_64-linux-gnu${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
fi
out=$(mktemp -d "${TMPDIR:-/tmp}/luanttd-bakewell-art.XXXXXX")
echo "Native Bakewell Cotswald LB-3 evidence: $out"
disp=${BAYLINE_NATIVE_DISPLAY:-193}
port=${BAYLINE_NATIVE_PORT:-39893}
pids=()
cleanup() {
  for pid in "${pids[@]}"; do kill -TERM "$pid" 2>/dev/null || true; done
  wait || true
}
trap cleanup EXIT
mod="$out/games/bakewell_art/mods/bakewell"
mkdir -p "$mod/"{models,textures} "$out/"{world,home,cache}
printf 'title = LuanTTD Bakewell Cotswald LB-3 art fixture\n' > "$out/games/bakewell_art/game.conf"
printf 'name = bakewell\n' > "$mod/mod.conf"
cp tests/bakewell_cotswald_art_native.lua "$mod/init.lua"
cp mods/luanttd_core/models/{bl_bakewell_cotswald.obj,bl_bakewell_cotswald_flight.obj,bl_bayshore_trimotor.obj,bl_small_airport_?_?.obj} "$mod/models/"
cp mods/luanttd_core/textures/{bl_bakewell_cotswald_atlas,bl_bayshore_trimotor_palette,bl_small_airport_atlas,bl_grass?,bl_grass_side}.png "$mod/textures/"
printf 'gameid = bakewell_art\nbackend = sqlite3\nplayer_backend = sqlite3\nauth_backend = sqlite3\nmod_storage_backend = sqlite3\n' > "$out/world/world.mt"
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
luantiserver --world "$out/world" --config "$out/server.conf" --gameid bakewell_art --logfile "" > "$out/server.log" 2>&1 &
pids+=("$!")
for _ in {1..40}; do if grep -q 'listening' "$out/server.log"; then break; fi; sleep .25; done
grep -q 'listening' "$out/server.log" || { cat "$out/server.log"; exit 1; }
luanti --go --address 127.0.0.1 --port "$port" --config "$out/client.conf" --name BakewellQA --logfile "" > "$out/client.log" 2>&1 &
client=$!
pids+=("$client")
for _ in {1..120}; do if grep -q BAKEWELL_MESH_FIXTURE_READY "$out/server.log"; then break; fi; sleep .25; done
grep -q BAKEWELL_MESH_FIXTURE_READY "$out/server.log" || { cat "$out/"{server,client}.log; exit 1; }
win=$(xdotool search --sync --onlyvisible --pid "$client"|tail -1)
xdotool windowfocus --sync "$win"
xdotool mousemove 650 430
sleep 3
xdotool key F2
sleep 2
for shot in apron_low apron_survey hangar gear_up; do
  xdotool key t; sleep .2; xdotool type "/showbakewell $shot"; xdotool key Return
  sleep 2.6
  import -window root "$out/bakewell-$shot.png"
done
! grep -Ei 'error|could not load' "$out/client.log"
python3 - "$out" <<'PYQA'
from PIL import Image
from pathlib import Path
import sys
for name in ("apron_low","apron_survey","hangar","gear_up"):
    i=Image.open(Path(sys.argv[1])/f"bakewell-{name}.png").convert("RGB").crop((240,155,1060,750))
    pp=list(i.get_flattened_data() if hasattr(i,"get_flattened_data") else i.getdata())
    livery=sum(55<r<176 and 21<g<112 and 15<b<97 and r>g+23 and g>b+5 for r,g,b in pp)
    fin=sum(130<r<239 and abs(r-g)<=11 and abs(r-b)<=21 for r,g,b in pp)
    tip=sum(105<r<246 and 90<g<225 and 18<b<155 and r>g+15 and g>b+26 for r,g,b in pp)
    assert livery>110 and fin>130 and tip>25,(name,livery,fin,tip)
    print(f"{name}: {livery} burgundy trim, {fin} fuselage and {tip} brass/golden-tip pixels")
print("BAKEWELL_NATIVE_ART_PASS")
PYQA
