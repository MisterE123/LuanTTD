#!/usr/bin/env bash
# Original stock tanker at real lane snapshots; actual client via Xvfb.
# Inputs match tests/native.sh; isolated world and profile, no existing saves.
set -euo pipefail
cd "$(dirname "$0")/.."
repo=$PWD
if [[ -n ${BAYLINE_NATIVE_TOOLS:-} ]]; then
  tools=$(realpath "$BAYLINE_NATIVE_TOOLS")
  export PATH="$tools/run/bin:$tools/usr/bin:$PATH"
  export LD_LIBRARY_PATH="$tools/usr/lib/x86_64-linux-gnu${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
fi
out=$(mktemp -d "${TMPDIR:-/tmp}/luanttd-witcombe-oil-art.XXXXXX")
echo "Native Witcombe Oil Tanker evidence: $out"
disp=${BAYLINE_NATIVE_DISPLAY:-210}
port=${BAYLINE_NATIVE_PORT:-39910}
pids=()
cleanup() {
  for pid in "${pids[@]}"; do kill -TERM "$pid" 2>/dev/null || true; done
  wait || true
}
trap cleanup EXIT
mod="$out/games/witcombe_oil_art/mods/oiltanker"
mkdir -p "$mod/"{models,textures} "$out/"{world,home,cache}
printf 'title = LuanTTD Oil Tanker art fixture\n' > "$out/games/witcombe_oil_art/game.conf"
printf 'name = oiltanker\n' > "$mod/mod.conf"
cp tests/witcombe_oil_tanker_art_native.lua "$mod/init.lua"
mkdir -p "$mod/source/openttd"
cp tests/foster_bus_route.lua "$mod/"
cp mods/luanttd_core/{road_lanes.lua,road_motion_presentation.lua,road_motion_leg.lua,road_bridge_motion.lua} "$mod/source/"
cp mods/luanttd_core/openttd/{yapf_road_follow.lua,road_motion.lua,road_motion_data.lua} "$mod/source/openttd/"
cp mods/luanttd_core/models/bl_witcombe_oil_tanker.obj "$mod/models/"
cp mods/luanttd_core/textures/{bl_witcombe_oil_tanker_atlas,bl_grass?,bl_grass_side}.png "$mod/textures/"
for mask in 3 5 6 9 10 12; do cp mods/luanttd_core/textures/bl_road_${mask}_plain_q?.png "$mod/textures/"; done
printf 'gameid = witcombe_oil_art\nbackend = sqlite3\nplayer_backend = sqlite3\nauth_backend = sqlite3\nmod_storage_backend = sqlite3\n' > "$out/world/world.mt"
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
luantiserver --world "$out/world" --config "$out/server.conf" --gameid witcombe_oil_art --logfile "" > "$out/server.log" 2>&1 &
pids+=("$!")
for _ in {1..40}; do if grep -q 'listening' "$out/server.log"; then break; fi; sleep .25; done
grep -q 'listening' "$out/server.log" || { cat "$out/server.log"; exit 1; }
luanti --go --address 127.0.0.1 --port "$port" --config "$out/client.conf" --name OilQA --logfile "" > "$out/client.log" 2>&1 &
client=$!
pids+=("$client")
for _ in {1..120}; do if grep -q WITCOMBE_OIL_MESH_FIXTURE_READY "$out/server.log"; then break; fi; sleep .25; done
grep -q WITCOMBE_OIL_MESH_FIXTURE_READY "$out/server.log" || { cat "$out/"{server,client}.log; exit 1; }
win=$(xdotool search --sync --onlyvisible --pid "$client"|tail -1)
xdotool windowfocus --sync "$win"
xdotool mousemove 650 430
sleep 3
xdotool key F2
sleep 2
for shot in front side rear curve survey; do
  xdotool key t; sleep .2; xdotool type "/showoiltanker $shot"; xdotool key Return
  sleep 2.6
  import -window root "$out/oiltanker-$shot.png"
done
! grep -Ei 'error|could not load' "$out/client.log"
python3 - "$out" <<'PYQA'
from PIL import Image
from pathlib import Path
import sys
p=Path(sys.argv[1])
for name in ("front","side","rear","curve","survey"):
    i=Image.open(p/f"oiltanker-{name}.png").convert("RGB").crop((230,180,1070,750))
    colors=i.get_flattened_data() if hasattr(i,"get_flattened_data") else i.getdata()
    blue=sum(30<r<98 and 59<g<146 and 76<b<171 and r+20<g and g+12<b for r,g,b in colors)
    cream=sum(126<r<242 and 101<g<214 and 60<b<183 and r>g+10 and g>b+20 for r,g,b in colors)
    assert blue>1200 and cream>(350 if name=="front" else 1500),(name,blue,cream)
    print(f"{name}: {blue} coach-blue and {cream} tank-cream pixels")
print("WITCOMBE_OIL_NATIVE_ART_PASS",p)
PYQA
