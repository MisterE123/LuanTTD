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
out=$(mktemp -d "${TMPDIR:-/tmp}/luanttd-stock-landmarks-art.XXXXXX")
echo "Native stock landmarks art evidence: $out"
disp=${BAYLINE_NATIVE_DISPLAY:-229}
port=${BAYLINE_NATIVE_PORT:-39929}
pids=()
cleanup() {
  for pid in "${pids[@]}"; do kill -TERM "$pid" 2>/dev/null || true; done
  wait || true
}
trap cleanup EXIT
mod="$out/games/landmark_art/mods/landmarkart"
mkdir -p "$mod/"{models,textures} "$out/"{world,home,cache}
printf 'title = LuanTTD stock landmarks art fixture\n' > "$out/games/landmark_art/game.conf"
printf 'name = landmarkart\n' > "$mod/mod.conf"
cp tests/stock_landmarks_art_native.lua "$mod/init.lua"
cp mods/luanttd_core/models/bl_stock_{lighthouse,transmitter}.obj "$mod/models/"
cp mods/luanttd_core/textures/{bl_stock_landmarks_atlas,bl_grass0,bl_grass2,bl_grass_side}.png "$mod/textures/"
printf 'gameid = landmark_art\nbackend = sqlite3\nplayer_backend = sqlite3\nauth_backend = sqlite3\nmod_storage_backend = sqlite3\n' > "$out/world/world.mt"
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
luantiserver --world "$out/world" --config "$out/server.conf" --gameid landmark_art --logfile "" > "$out/server.log" 2>&1 &
pids+=("$!")
for _ in {1..40}; do if grep -q 'listening' "$out/server.log"; then break; fi; sleep .25; done
grep -q 'listening' "$out/server.log" || { cat "$out/server.log"; exit 1; }
luanti --go --address 127.0.0.1 --port "$port" --config "$out/client.conf" --name RailQA --logfile "" > "$out/client.log" 2>&1 &
client=$!
pids+=("$client")
for _ in {1..120}; do if grep -q STOCK_LANDMARKS_FIXTURE_READY "$out/server.log"; then break; fi; sleep .25; done
grep -q STOCK_LANDMARKS_FIXTURE_READY "$out/server.log" || { cat "$out/"{server,client}.log; exit 1; }
win=$(xdotool search --sync --onlyvisible --pid "$client"|tail -1)
xdotool windowfocus --sync "$win"
xdotool mousemove 650 430
sleep 3
xdotool key F2
sleep 2
for shot in pair light mast; do
  xdotool key t; sleep .2; xdotool type "/viewlandmark $shot"; xdotool key Return
  sleep 2.7
  import -window root "$out/landmark-$shot.png"
done
! grep -Ei 'ERROR\[|could not load' "$out/client.log"
python3 - "$out" <<'PYQA'
from pathlib import Path
from PIL import Image
import sys

for name in ("landmark-light","landmark-mast","landmark-pair"):
    im=Image.open(Path(sys.argv[1])/(name+".png")).convert("RGB").crop((210,120,1090,790))
    rgb=im.get_flattened_data() if hasattr(im,"get_flattened_data") else im.getdata()
    yellow=sum(135<r<248 and 105<g<235 and 37<b<142 and r>g+11 and g>b+34 for r,g,b in rgb)
    alloy=sum(75<r<220 and 86<g<233 and 95<b<240 and 3<=g-r<=22 and 3<=b-g<=25 for r,g,b in rgb)
    print(f"{name}: {yellow} warm lantern and {alloy} metal/stone pixels")
    assert alloy>650 and (name=="landmark-mast" or yellow>100),(name,yellow,alloy)
PYQA
echo "STOCK_LANDMARKS_NATIVE_ART_PASS $out"
