#!/usr/bin/env bash
# Native graphical rendering of the actual shipped OBJ and atlas under Luanti.
# Inputs match tests/native.sh; isolated world and profile, no existing saves.
set -euo pipefail
cd "$(dirname "$0")/.."
repo=${LUANTTD_BASE:-$PWD}
one=$(realpath "${1:?worker world path for coach-mail}")
two=$(realpath "${2:?worker world path for mail-coach-mail}")
if [[ -n ${BAYLINE_NATIVE_TOOLS:-} ]]; then
  tools=$(realpath "$BAYLINE_NATIVE_TOOLS")
  export PATH="$tools/run/bin:$tools/usr/bin:$PATH"
  export LD_LIBRARY_PATH="$tools/usr/lib/x86_64-linux-gnu${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
fi
out=$(mktemp -d "${TMPDIR:-/tmp}/luanttd-stock-mixed-town-art.XXXXXX")
echo "Native mixed town rail art evidence: $out"
disp=${BAYLINE_NATIVE_DISPLAY:-253}
port=${BAYLINE_NATIVE_PORT:-40037}
pids=()
cleanup() {
  for pid in "${pids[@]}"; do kill -TERM "$pid" 2>/dev/null || true; done
  wait || true
}
trap cleanup EXIT
mod="$out/games/rail_art/mods/railpreview"
mkdir -p "$mod/"{models,textures} "$out/"{world,home,cache}
printf 'title = LuanTTD mixed town rail art fixture\n' > "$out/games/rail_art/game.conf"
printf 'name = railpreview\n' > "$mod/mod.conf"
cp tests/stock_mixed_town_rail_render.lua "$mod/init.lua"
for stage in loading reversed; do
  [[ -f "$one/mixed-pose-$stage.json" && -f "$two/mixed-pose-$stage.json" ]]
done
cp "$one/mixed-pose-loading.json" "$mod/frame1.json"
cp "$one/mixed-pose-reversed.json" "$mod/frame2.json"
cp "$two/mixed-pose-loading.json" "$mod/frame3.json"
cp "$two/mixed-pose-reversed.json" "$mod/frame4.json"
cp "$repo"/mods/luanttd_core/models/bl_rail_{track_1,platform_1,passenger_wagon,mail_van,kirby_paul_tank}.obj "$mod/models/"
cp "$repo"/mods/luanttd_core/textures/{bl_rail_atlas,bl_rail_architecture_atlas,bl_grass0,bl_grass_side,bl_rail_mail_van,bl_rail_kirby_paul_tank,bl_rail_wagon_atlas}.png "$mod/textures/"
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
for _ in {1..120}; do if grep -q MIXED_TOWN_CLIENT_MESH_READY "$out/server.log"; then break; fi; sleep .25; done
grep -q MIXED_TOWN_CLIENT_MESH_READY "$out/server.log" || { cat "$out/"{server,client}.log; exit 1; }
win=$(xdotool search --sync --onlyvisible --pid "$client"|tail -1)
xdotool windowfocus --sync "$win"
xdotool mousemove 650 430
sleep 3
xdotool key F2
sleep 2
for shot in 1 2 3 4; do
  xdotool key t; sleep .2; xdotool type "/showmixed $shot"; xdotool key Return
  sleep 2.7
  import -window root "$out/mixed-$shot.png"
done
! grep -Ei 'ERROR\[|could not load' "$out/client.log"
for i in 1 2 3 4; do grep "MIXED_TOWN_CLIENT_CAPTURE $i " "$out/server.log"; done
python3 - "$out" <<'PYQA'
from pathlib import Path
from PIL import Image, ImageChops
import sys
p=Path(sys.argv[1])
def frame(i):return Image.open(p/f"mixed-{i}.png").convert("RGB").crop((120,125,1180,810))
for i in range(1,5):
    im=frame(i)
    q=im.get_flattened_data() if hasattr(im,"get_flattened_data") else im.getdata()
    red=sum(45<r<175 and r>g+21 and r>b+17 and 18<g<114 and 18<b<120 for r,g,b in q)
    assert red>1000,(i,red)
    print(i,red)
for one,two in ((1,2),(3,4)):
    assert ImageChops.difference(frame(one),frame(two)).getbbox()
print("PASS real authority body projections rendered on native rail in both mixed formations")
PYQA
