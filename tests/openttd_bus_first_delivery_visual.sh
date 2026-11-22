#!/usr/bin/env bash
# Optional GUI capture; all writes go to a new private profile.
set -euo pipefail
cd "$(dirname "$0")/.."
repo=$PWD
if [[ $# -lt 2 || $# -gt 3 ]]; then echo "usage: $0 private.sav reference.json [new-output-dir]" >&2; exit 64; fi
source=$(realpath "$1")
reference=$(realpath "$2")
before=$(sha256sum "$source")
out=${3:-}
if [[ -z $out ]]; then out=$(mktemp -d /tmp/luanttd-stock-bus-visual.XXXXXX); rmdir "$out"; fi
out=$(realpath -m "$out")
if [[ -n ${BAYLINE_NATIVE_TOOLS:-} ]]; then
  tools=$(realpath "$BAYLINE_NATIVE_TOOLS")
  export PATH="$tools/run/bin:$tools/usr/bin:$PATH"
  export LD_LIBRARY_PATH="$tools/usr/lib/x86_64-linux-gnu${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
fi
python3 tests/openttd_bus_first_delivery.py --save "$source" --reference "$reference" --visual-dir "$out"
echo "Private stock bus visual evidence: $out"
pids=()
cleanup() { for pid in "${pids[@]}"; do kill -TERM "$pid" 2>/dev/null || true; done; wait || true; }
trap cleanup EXIT
port=${BAYLINE_NATIVE_PORT:-39567}
disp=${BAYLINE_NATIVE_DISPLAY:-151}
mkdir -p "$out/"{world,home,cache}
printf 'gameid = triptest\nbackend = sqlite3\nplayer_backend = sqlite3\nauth_backend = sqlite3\n' > "$out/world/world.mt"
printf 'port = %s\nbind_address = 127.0.0.1\nserver_announce = false\nbus_first_delivery_mode = visual\n' "$port" > "$out/server.conf"
cat > "$out/client.conf" <<'EOF_CLIENT'
screen_w = 1300
screen_h = 830
fullscreen = false
enable_sound = false
viewing_range = 24
fps_max = 32
keymap_toggle_chat = KEY_F2
EOF_CLIENT
export HOME="$out/home" XDG_CACHE_HOME="$out/cache" XDG_CONFIG_HOME="$out/home/.config" \
  LUANTI_GAME_PATH="$out/games" MINETEST_GAME_PATH="$out/games" LIBGL_ALWAYS_SOFTWARE=1 ALSOFT_DRIVERS=null
export DISPLAY=":$disp" XAUTHORITY="$out/Xauthority"
xargs=(-nolisten tcp)
prefix=()
if [[ ${BAYLINE_NATIVE_TCP:-0} == 1 ]]; then
  cc -shared -fPIC "$repo/tests/native_loopback.c" -ldl -o "$out/loopback.so"
  export DISPLAY="127.0.0.1:$disp"
  xargs=(-listen tcp -nolisten unix -nolisten local)
  prefix=(env "LD_PRELOAD=$out/loopback.so${LD_PRELOAD:+:$LD_PRELOAD}")
fi
touch "$XAUTHORITY"
cookie=$(python3 -c 'import secrets; print(secrets.token_hex(16))')
xauth -f "$XAUTHORITY" add "$DISPLAY" MIT-MAGIC-COOKIE-1 "$cookie"
"${prefix[@]}" Xvfb ":$disp" -screen 0 1300x830x24 "${xargs[@]}" -auth "$XAUTHORITY" -noreset > "$out/xvfb.log" 2>&1 &
pids+=("$!")
for _ in {1..50}; do if xdpyinfo >/dev/null 2>&1; then break; fi; sleep .2; done
xdpyinfo >/dev/null 2>&1
wait_log() {
  for _ in {1..140}; do
    if grep -q "$1" "$out/server.log"; then return 0; fi
    if grep -q "ERROR\[" "$out/server.log"; then break; fi
    sleep .2
  done
  cat "$out/server.log"; [[ ! -f "$out/client.log" ]] || tail -30 "$out/client.log"
  return 1
}
"${BAYLINE_LUANTI_SERVER:-luantiserver}" --world "$out/world" --config "$out/server.conf" --gameid triptest --logfile '' > "$out/server.log" 2>&1 &
pids+=("$!")
wait_log listening
"${BAYLINE_LUANTI_CLIENT:-luanti}" --go --address 127.0.0.1 --port "$port" --config "$out/client.conf" --name StockTripQA --logfile '' > "$out/client.log" 2>&1 &
client="$!"
pids+=("$client")
wait_log 'VISUAL READY'
win=$(xdotool search --sync --onlyvisible --pid "$client" | tail -1)
xdotool windowfocus --sync "$win"
xdotool mousemove 650 415
xdotool key F2
sleep 2
import -window root "$out/loaded.png"
cmd() { xdotool key t; sleep .2; xdotool type "/busprobe $1"; xdotool key Return; }
cmd play
sleep 2
import -window root "$out/driving.png"
wait_log 'VISUAL DELIVERED'
sleep 1
import -window root "$out/delivered.png"
cmd settle
wait_log 'VISUAL SETTLED'
sleep 1
import -window root "$out/settled.png"
[[ "$before" == "$(sha256sum "$source")" ]]
if grep -Ei 'ERROR\[|could not load' "$out/client.log" "$out/server.log"; then exit 1; fi
python3 - "$out" <<'PYTEST'
from PIL import Image, ImageChops
from pathlib import Path
import sys
folder=Path(sys.argv[1])
for n in ("loaded","driving","delivered","settled"):
    im=Image.open(folder/(n+".png")).convert("RGB")
    assert im.size==(1300,830)
    region=[im.getpixel((x,y)) for y in range(210,800,5) for x in range(50,1250,7)]
    assert len(set(region))>200
    assert sum(g>r*1.10 and g>b*1.10 for r,g,b in region)>1500,n
def scene(name):
    return Image.open(folder/(name+".png")).convert("RGB").crop((0,150,1300,830))
a,b=scene("loaded"),scene("driving")
assert ImageChops.difference(a,b).getbbox() is not None,"bus never moved in the native view"
assert ImageChops.difference(scene("delivered"),scene("settled")).getbbox() is None,"same parked bus must hold the rendered berth"
print("Native stock bus presentation screenshots passed.")
PYTEST
