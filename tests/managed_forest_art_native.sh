#!/usr/bin/env bash
# Native graphical rendering of the actual stock forest OBJ and atlas under Luanti.
# Inputs match tests/native.sh; isolated world and profile, no existing saves.
set -euo pipefail
cd "$(dirname "$0")/.."
repo=$PWD
if [[ -n ${BAYLINE_NATIVE_TOOLS:-} ]]; then
  tools=$(realpath "$BAYLINE_NATIVE_TOOLS")
  export PATH="$tools/run/bin:$tools/usr/bin:$PATH"
  export LD_LIBRARY_PATH="$tools/usr/lib/x86_64-linux-gnu${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
fi
out=$(mktemp -d "${TMPDIR:-/tmp}/luanttd-forest-art.XXXXXX")
echo "Native forest visual evidence: $out"
disp=${BAYLINE_NATIVE_DISPLAY:-178}
port=${BAYLINE_NATIVE_PORT:-39878}
pids=()
cleanup() {
  for pid in "${pids[@]}"; do kill -TERM "$pid" 2>/dev/null || true; done
  wait || true
}
trap cleanup EXIT
mod="$out/games/goods_art/mods/goodsart"
mkdir -p "$mod/"{models,textures} "$out/"{world,home,cache}
printf 'title = LuanTTD Forest art fixture\n' > "$out/games/goods_art/game.conf"
printf 'name = goodsart\n' > "$mod/mod.conf"
cp tests/managed_forest_art_native.lua "$mod/init.lua"
cp mods/luanttd_core/models/bl_forest_*.obj "$mod/models/"
cp mods/luanttd_core/textures/{bl_forest_atlas,bl_grass*,bl_road_10_plain_q*}.png "$mod/textures/"
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
for _ in {1..120}; do if grep -q FOREST_MESH_FIXTURE_READY "$out/server.log"; then break; fi; sleep .25; done
grep -q FOREST_MESH_FIXTURE_READY "$out/server.log" || { cat "$out/"{server,client}.log; exit 1; }
win=$(xdotool search --sync --onlyvisible --pid "$client"|tail -1)
xdotool windowfocus --sync "$win"
xdotool mousemove 650 430
sleep 3
xdotool key F2
sleep 2
for shot in survey landing cut second; do
  xdotool key t; sleep .2; xdotool type "/showforest $shot"; xdotool key Return
  sleep 2.6
  import -window root "$out/forest-$shot.png"
done
grep -q FOREST_NATIVE_GFX17_MOUNTED "$out/server.log"
! grep -Ei 'error|could not load' "$out/client.log"
python3 - "$out" <<'PYQA'
from PIL import Image
from pathlib import Path
import sys
for name in ("survey","landing","cut","second"):
    i=Image.open(Path(sys.argv[1])/f"forest-{name}.png").convert("RGB").crop((160,120,1200,810))
    pixels=list(i.get_flattened_data() if hasattr(i,"get_flattened_data") else i.getdata())
    fir=sum(20<r<116 and 57<g<145 and 45<b<136 and g>r+16 and abs(g-b)<28 for r,g,b in pixels)
    bark=sum(80<r<212 and 55<g<178 and 26<b<144 and r>g+15 and g>b+13 for r,g,b in pixels)
    assert fir>6000 and bark>550,(name,fir,bark)
    print(f"{name}: {fir} forest green pixels, {bark} original timber pixels")
print("FOREST_NATIVE_ART_PASS")
PYQA
