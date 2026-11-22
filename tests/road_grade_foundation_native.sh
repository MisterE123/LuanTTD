#!/usr/bin/env bash
# Actual game registrations and paid grades, rendered by a real Luanti client.
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ -n ${BAYLINE_NATIVE_TOOLS:-} ]]; then
  tools=$(realpath "$BAYLINE_NATIVE_TOOLS")
  export PATH="$tools/run/bin:$tools/usr/bin:$PATH" LD_LIBRARY_PATH="$tools/usr/lib/x86_64-linux-gnu${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
fi
src=$(realpath "${BAYLINE_NATIVE_EXACT_GAME:-.}")
out=$(mktemp -d "${TMPDIR:-/tmp}/luanttd-road-grade.XXXXXX")
echo "Road-grade visual evidence: $out"
game="$out/games/luanttd"
mkdir -p "$game" "$out/home" "$out/cache" "$out/world"
cp "$src/game.conf" "$game/"
if [[ -n ${BAYLINE_NATIVE_CACHE_SEED:-} && -d $BAYLINE_NATIVE_CACHE_SEED/minetest ]]; then
  seed=$(realpath "$BAYLINE_NATIVE_CACHE_SEED/minetest")
  # Native media is immutable and content-addressed; only reuse that subfolder.
  if [[ -d $seed/media ]] && [[ "$(stat -c %d "$seed")" == "$(stat -c %d "$out")" ]]; then
    mkdir -p "$out/cache/minetest"
    cp -al "$seed/media" "$out/cache/minetest/"
  fi
fi
if [[ "$(stat -c %d "$src")" == "$(stat -c %d "$out")" ]]; then
  cp -al "$src/mods" "$game/"
else
  cp -R "$src/mods" "$game/"
fi
cp tests/road_grade_foundation_native.lua "$game/mods/luanttd_core/"
cat "$src/mods/luanttd_core/init.lua" >"$out/init.lua"
printf '\ndofile(mod.."/road_grade_foundation_native.lua")(api)\n' >>"$out/init.lua"
mv "$out/init.lua" "$game/mods/luanttd_core/init.lua"
export HOME="$out/home" XDG_CACHE_HOME="$out/cache" LUANTI_GAME_PATH="$out/games" MINETEST_GAME_PATH="$out/games"
export LIBGL_ALWAYS_SOFTWARE=1 ALSOFT_DRIVERS=null
port=${BAYLINE_NATIVE_PORT:-42818}
display=${BAYLINE_NATIVE_DISPLAY:-118}
export DISPLAY=":$display" XAUTHORITY="$out/Xauthority"
pids=()
cleanup() { for pid in "${pids[@]}"; do kill -TERM "$pid" 2>/dev/null || true; done; wait || true; }
trap cleanup EXIT
cp tests/qa_layout.lua "$game/mods/luanttd_core/qa_layout.lua"
cp tests/coastal_corridor_fixture.lua "$game/mods/luanttd_core/qa_coastal_corridor.lua"
printf 'gameid = luanttd\nbackend = sqlite3\nplayer_backend = sqlite3\nauth_backend = sqlite3\nmod_storage_backend = sqlite3\n' >"$out/world/world.mt"
cat >"$out/native.conf" <<GAME
port = $port
server_announce = false
bind_address = 127.0.0.1
bayline_stock_generated_world = false
bayline_stock_workbenches = false
bayline_preview_terrain = true
bayline_development_tools = true
luanttd_qa_plain_layout = true
GAME
cat >"$out/client.conf" <<'GAME'
screen_w = 1100
screen_h = 770
fullscreen = false
enable_sound = false
viewing_range = 50
fps_max = 30
GAME
opts=(-nolisten tcp)
lib=()
if [[ ${BAYLINE_NATIVE_TCP:-0} == 1 ]]; then
  cc -shared -fPIC tests/native_loopback.c -ldl -o "$out/loopback.so"
  export DISPLAY="127.0.0.1:$display"
  opts=(-listen tcp -nolisten unix -nolisten local)
  lib=(env "LD_PRELOAD=$out/loopback.so${LD_PRELOAD:+:$LD_PRELOAD}")
fi
touch "$XAUTHORITY"
xauth -f "$XAUTHORITY" add "$DISPLAY" MIT-MAGIC-COOKIE-1 "$(python3 -c 'import secrets; print(secrets.token_hex(16))')"
"${lib[@]}" Xvfb ":$display" -screen 0 1100x770x24 "${opts[@]}" -auth "$XAUTHORITY" -noreset >"$out/xvfb.log" 2>&1 &
pids+=("$!")
for _ in {1..60}; do xdpyinfo >/dev/null 2>&1 && break; sleep .2; done
xdpyinfo >/dev/null 2>&1 || { cat "$out/xvfb.log"; exit 1; }
luantiserver --world "$out/world" --config "$out/native.conf" --gameid luanttd --logfile "" >"$out/server.log" 2>&1 &
pids+=("$!")
for _ in {1..80}; do grep -q 'listening' "$out/server.log" && break; sleep .2; done
grep -q 'listening' "$out/server.log" || { cat "$out/server.log"; exit 1; }
luanti --go --address 127.0.0.1 --port "$port" --config "$out/client.conf" --name GradeQA --logfile "" >"$out/client.log" 2>&1 &
pids+=("$!")
for _ in {1..300}; do
  grep -q ROAD_GRADE_FOUNDATION_READY "$out/server.log" && break
  if ! kill -0 "${pids[1]}" 2>/dev/null; then cat "$out/server.log"; exit 1; fi
  sleep .25
done
grep ROAD_GRADE_FOUNDATION_READY "$out/server.log" || { cat "$out/"{server,client}.log; exit 1; }
sleep 5
import -window root "$out/stock-road-grade-foundations.png"
! grep -Ei 'error|could not load' "$out/client.log"
python3 - "$out/stock-road-grade-foundations.png" <<'PY'
from PIL import Image
import sys

# Sample the exposed ramp's lower triangular side only. This detects the
# reused asphalt strip in single-buffer OBJ even with correct server nodes.
with Image.open(sys.argv[1]) as image:
    im = image.convert("RGB")
    wall = list(im.crop((500, 452, 553, 468)).getdata())
    gray_stone = sum(52 < b <= g <= r < 155 and r - b <= 24 for r, g, b in wall)
    false_asphalt = sum(45 < r <= g and g + 6 <= b < 90 for r, g, b in wall)
    road = list(im.crop((420, 439, 445, 448)).getdata())
    dark_top = sum(45 < r <= g and g + 6 <= b < 90 for r, g, b in road)
    assert gray_stone > 400 and false_asphalt < 25 and dark_top > 30, (
        gray_stone, false_asphalt, dark_top)
print(f"PASS: native ramp wall has {gray_stone} stone pixels and no repeating asphalt strip")
PY
