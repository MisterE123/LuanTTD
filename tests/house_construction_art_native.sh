#!/usr/bin/env bash
# Native graphical rendering of the actual house models by construction phase OBJ and atlas under Luanti.
# Inputs match tests/native.sh; isolated world and profile, no existing saves.
set -euo pipefail
cd "$(dirname "$0")/.."
repo=$PWD
if [[ -n ${BAYLINE_NATIVE_TOOLS:-} ]]; then
  tools=$(realpath "$BAYLINE_NATIVE_TOOLS")
  export PATH="$tools/run/bin:$tools/usr/bin:$PATH"
  export LD_LIBRARY_PATH="$tools/usr/lib/x86_64-linux-gnu${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
fi
out=$(mktemp -d "${TMPDIR:-/tmp}/luanttd-house-build.XXXXXX")
echo "Native construction stage evidence: $out"
disp=${BAYLINE_NATIVE_DISPLAY:-181}
port=${BAYLINE_NATIVE_PORT:-39881}
pids=()
cleanup() {
  for pid in "${pids[@]}"; do kill -TERM "$pid" 2>/dev/null || true; done
  wait || true
}
trap cleanup EXIT
mod="$out/games/goods_art/mods/goodsart"
mkdir -p "$mod/"{models,textures} "$out/"{world,home,cache}
printf 'title = LuanTTD House construction art fixture\n' > "$out/games/goods_art/game.conf"
printf 'name = goodsart\n' > "$mod/mod.conf"
cp tests/house_construction_art_native.lua "$mod/init.lua"
cp mods/luanttd_core/models/{bl_house_build_stage_*.obj,bl_scenery_house_0.obj} "$mod/models/"
cp mods/luanttd_core/textures/{bl_house_build_atlas,bl_scenery_palette,bl_grass*,bl_road_10_plain_q*}.png "$mod/textures/"
printf 'gameid = goods_art\nbackend = sqlite3\nplayer_backend = sqlite3\nauth_backend = sqlite3\nmod_storage_backend = sqlite3\n' > "$out/world/world.mt"
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
luantiserver --world "$out/world" --config "$out/server.conf" --gameid goods_art --logfile "" > "$out/server.log" 2>&1 &
pids+=("$!")
for _ in {1..40}; do if grep -q 'listening' "$out/server.log"; then break; fi; sleep .25; done
grep -q 'listening' "$out/server.log" || { cat "$out/server.log"; exit 1; }
luanti --go --address 127.0.0.1 --port "$port" --config "$out/client.conf" --name GoodsQA --logfile "" > "$out/client.log" 2>&1 &
client=$!
pids+=("$client")
for _ in {1..120}; do if grep -q HOUSE_BUILD_MESH_FIXTURE_READY "$out/server.log"; then break; fi; sleep .25; done
grep -q HOUSE_BUILD_MESH_FIXTURE_READY "$out/server.log" || { cat "$out/"{server,client}.log; exit 1; }
win=$(xdotool search --sync --onlyvisible --pid "$client"|tail -1)
xdotool windowfocus --sync "$win"
xdotool mousemove 650 430
sleep 3
xdotool key F2
sleep 2
for shot in stage0 stage1 stage2 sequence; do
  xdotool key t; sleep .2; xdotool type "/showhouse $shot"; xdotool key Return
  sleep 2.6
  import -window root "$out/house-$shot.png"
done
! grep -Ei 'error|could not load' "$out/client.log"
python3 - "$out" <<'PYQA'
from PIL import Image
from pathlib import Path
import sys
for name in ("stage0","stage1","stage2","sequence"):
    i=Image.open(Path(sys.argv[1])/f"house-{name}.png").convert("RGB").crop((130,120,1150,815))
    pixels=list(i.get_flattened_data() if hasattr(i,"get_flattened_data") else i.getdata())
    timber=sum(89<r<240 and 59<g<186 and 20<b<150 and r>g+12 and g>b+9 for r,g,b in pixels)
    roof=sum(140<r<233 and 67<g<133 and 53<b<127 and r>g+44 and g>b+4 for r,g,b in pixels)
    assert timber>1700,(name,timber)
    if name=="stage2":assert roof>250,(name,roof)
    print(f"{name}: {timber} wood/loam pixels and {roof} terracotta pixels")
print("HOUSE_BUILD_NATIVE_ART_PASS")
PYQA
