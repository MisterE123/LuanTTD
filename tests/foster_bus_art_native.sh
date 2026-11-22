#!/usr/bin/env bash
# Native Foster Bus with actual stock right-hand road presentation poses.
# Inputs match tests/native.sh; isolated world and profile, no existing saves.
set -euo pipefail
cd "$(dirname "$0")/.."
repo=$PWD
if [[ -n ${BAYLINE_NATIVE_TOOLS:-} ]]; then
  tools=$(realpath "$BAYLINE_NATIVE_TOOLS")
  export PATH="$tools/run/bin:$tools/usr/bin:$PATH"
  export LD_LIBRARY_PATH="$tools/usr/lib/x86_64-linux-gnu${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
fi
out=$(mktemp -d "${TMPDIR:-/tmp}/luanttd-foster-art.XXXXXX")
echo "Native Foster Bus evidence: $out"
disp=${BAYLINE_NATIVE_DISPLAY:-196}
port=${BAYLINE_NATIVE_PORT:-39896}
pids=()
cleanup() {
  for pid in "${pids[@]}"; do kill -TERM "$pid" 2>/dev/null || true; done
  wait || true
}
trap cleanup EXIT
mod="$out/games/foster_art/mods/foster"
mkdir -p "$mod/"{models,textures} "$out/"{world,home,cache}
printf 'title = LuanTTD Foster Bus art fixture\n' > "$out/games/foster_art/game.conf"
printf 'name = foster\n' > "$mod/mod.conf"
cp tests/foster_bus_art_native.lua "$mod/init.lua"
mkdir -p "$mod/source/openttd"
cp tests/foster_bus_route.lua "$mod/"
cp mods/luanttd_core/{road_lanes.lua,road_motion_presentation.lua,road_motion_leg.lua,road_bridge_motion.lua} "$mod/source/"
cp mods/luanttd_core/openttd/{yapf_road_follow.lua,road_motion.lua,road_motion_data.lua} "$mod/source/openttd/"
cp mods/luanttd_core/models/{bl_foster_bus.obj,bl_leopard_bus.obj,bl_scenery_house_0.obj,bl_scenery_house_2.obj,bl_bus_shelter.obj} "$mod/models/"
cp mods/luanttd_core/textures/{bl_foster_bus_atlas,bl_road_fleet_palette,bl_scenery_palette,bl_road_architecture,bl_grass?,bl_grass_side}.png "$mod/textures/"
for mask in 3 5 6 9 10 12; do
  if [[ ${BAYLINE_FOSTER_TOWN_STREET:-0} == 1 ]]; then
    for q in 0 1 2 3; do
      cp "mods/luanttd_core/textures/bl_town_street_${mask}_${q}.png" "$mod/textures/bl_road_${mask}_plain_q${q}.png"
    done
  else
    cp mods/luanttd_core/textures/bl_road_${mask}_plain_q?.png "$mod/textures/"
  fi
done
printf 'gameid = foster_art\nbackend = sqlite3\nplayer_backend = sqlite3\nauth_backend = sqlite3\nmod_storage_backend = sqlite3\n' > "$out/world/world.mt"
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
luantiserver --world "$out/world" --config "$out/server.conf" --gameid foster_art --logfile "" > "$out/server.log" 2>&1 &
pids+=("$!")
for _ in {1..40}; do if grep -q 'listening' "$out/server.log"; then break; fi; sleep .25; done
grep -q 'listening' "$out/server.log" || { cat "$out/server.log"; exit 1; }
luanti --go --address 127.0.0.1 --port "$port" --config "$out/client.conf" --name FosterQA --logfile "" > "$out/client.log" 2>&1 &
client=$!
pids+=("$client")
for _ in {1..120}; do if grep -q FOSTER_MESH_FIXTURE_READY "$out/server.log"; then break; fi; sleep .25; done
grep -q FOSTER_MESH_FIXTURE_READY "$out/server.log" || { cat "$out/"{server,client}.log; exit 1; }
win=$(xdotool search --sync --onlyvisible --pid "$client"|tail -1)
xdotool windowfocus --sync "$win"
xdotool mousemove 650 430
sleep 3
xdotool key F2
sleep 2
for shot in street rear passing left right; do
  xdotool key t; sleep .2; xdotool type "/showfoster $shot"; xdotool key Return
  sleep 2.6
  import -window root "$out/foster-$shot.png"
done
! grep -Ei 'error|could not load' "$out/client.log"
python3 - "$out" <<'PYQA'
from PIL import Image
from pathlib import Path
import sys
for name in ("street","rear","passing","left","right"):
    i=Image.open(Path(sys.argv[1])/f"foster-{name}.png").convert("RGB").crop((240,155,1060,750))
    pp=list(i.get_flattened_data() if hasattr(i,"get_flattened_data") else i.getdata())
    coach=sum(29<r<104 and 61<g<143 and 84<b<193 and r+19<g and g+15<b for r,g,b in pp)
    dark=sum(20<r<81 and 27<g<99 and 36<b<123 and r+3<g<b for r,g,b in pp)
    assert coach>220 and dark>260,(name,coach,dark)
    print(f"{name}: {coach} blue body pixels and {dark} dark glazing/bumper pixels")
print("FOSTER_NATIVE_ART_PASS")
PYQA
