#!/usr/bin/env bash
# Exercise /car and inventory exit on a real campaign with a graded road.
set -euo pipefail
cd "$(dirname "$0")/.."
repo=$PWD
python3 "$repo/tests/avatar_car_interior_geometry.py"
if [[ -n ${BAYLINE_NATIVE_TOOLS:-} ]]; then
  tools=$(realpath "$BAYLINE_NATIVE_TOOLS")
  export PATH="$tools/run/bin:$tools/usr/bin:$PATH"
  export LD_LIBRARY_PATH="$tools/usr/lib/x86_64-linux-gnu${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
fi
out=$(mktemp -d "${TMPDIR:-/tmp}/luanttd-car.XXXXXX")
echo "Native sightseeing-car evidence: $out"
disp=${BAYLINE_NATIVE_DISPLAY:-193}
port=${BAYLINE_NATIVE_PORT:-39893}
pids=()
cleanup() {
  for pid in "${pids[@]}"; do kill -TERM "$pid" 2>/dev/null || true; done
  wait || true
}
trap cleanup EXIT
game="$out/games/luanttd"
mkdir -p "$game" "$out/"{world,home,cache}
# Reuse immutable game media without writing into the working checkout.
cp -al mods "$game/" 2>/dev/null || cp -R mods "$game/"
cp -a game.conf settingtypes.txt "$game/"
mod="$game/mods/luanttd_core"
cp "$mod/init.lua" "$mod/init.native.lua"
mv -f "$mod/init.native.lua" "$mod/init.lua"
printf 'return function() return {scenario="coastal",local_replay=true} end\n' > "$mod/qa_layout.lua"
cp tests/avatar_car_live_native.lua "$mod/avatar_car_live_native.lua"
printf '\ndofile(mod.."/avatar_car_live_native.lua")(api)\n' >> "$mod/init.lua"
if [[ -n ${BAYLINE_NATIVE_CACHE_SEED:-} && -d "$BAYLINE_NATIVE_CACHE_SEED/minetest" ]]; then
  # Hash-addressed Luanti media; keep mutable Mesa caches separate.
  cp -al "$BAYLINE_NATIVE_CACHE_SEED/minetest" "$out/cache/"
fi
printf 'gameid = luanttd\nbackend = sqlite3\nplayer_backend = sqlite3\nauth_backend = sqlite3\nmod_storage_backend = sqlite3\n' > "$out/world/world.mt"
cat > "$out/server.conf" <<EOF
port = $port
prometheus_listener_address = 127.0.0.1:$port
server_announce = false
bind_address = 127.0.0.1
time_speed = 0
world_start_time = 12000
bayline_world_setup = false
bayline_scenario = coastal
bayline_seed = 1751
EOF
cat > "$out/client.conf" <<'EOF'
screen_w = 1300
screen_h = 860
fullscreen = false
keymap_camera_mode = KEY_F7
enable_sound = false
viewing_range = 80
fps_max = 30
enable_shaders = true
enable_dynamic_shadows = false
video_driver = opengl
shadow_map_max_distance = 100
shadow_map_texture_size = 1024
EOF
export HOME="$out/home" XDG_CACHE_HOME="${LUANTTD_NATIVE_MEDIA_CACHE:-$out/cache}" XDG_CONFIG_HOME="$out/home/.config" \
  LUANTI_GAME_PATH="$out/games" MINETEST_GAME_PATH="$out/games" \
  LIBGL_ALWAYS_SOFTWARE=1 ALSOFT_DRIVERS=null LP_NUM_THREADS=2
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
luantiserver --world "$out/world" --config "$out/server.conf" --gameid luanttd --logfile "" > "$out/server.log" 2>&1 &
pids+=("$!")
for _ in {1..40}; do if grep -q 'listening' "$out/server.log"; then break; fi; sleep .25; done
grep -q 'listening' "$out/server.log" || { cat "$out/server.log"; exit 1; }
luanti --go --address 127.0.0.1 --port "$port" --config "$out/client.conf" --name CarQA --logfile "" > "$out/client.log" 2>&1 &
client=$!
pids+=("$client")
for _ in {1..360}; do if grep -q "CAR_QA ready" "$out/server.log"; then break; fi; sleep .25; done
grep -q "CAR_QA ready" "$out/server.log" || { cat "$out/"{server,client}.log; exit 1; }
win=$(xdotool search --sync --onlyvisible --pid "$client"|tail -1)
xdotool windowfocus --sync "$win"
xdotool mousemove 650 430
sleep 3

say() {
  xdotool windowfocus --sync "$win"; xdotool key --clearmodifiers t; sleep .45; xdotool type --delay 32 "$1"; xdotool key --clearmodifiers Return; sleep .65
}
if [[ ${LUANTTD_NATIVE_SCENERY:-0} == 1 ]]; then
  say "/carprobe cine-before"
  say "/cine"
  import -window root "$out/cine-hidden.png"
  say "/carprobe cine-hidden"
  say "/cine"
  say "/carprobe cine-restored"
  say "/candy"
  say "/carprobe candy-off"
  say "/candy"
  say "/carprobe candy-on"
  grep "CINE_NATIVE_" "$out/server.log"
  grep "CANDY_NATIVE_" "$out/server.log"
fi
say "/carprobe before"
say "/car"
sleep .6
say "/carprobe entered"
import -window root -quality 92 "$out/car-entry.jpg"
# Free look must reveal side glass rather than an external chase camera.
xdotool mousemove_relative -- 145 18
sleep .42
import -window root -quality 92 "$out/car-side.jpg"
xdotool mousemove_relative -- -145 -18
sleep .42
if cmp -s "$out/car-entry.jpg" "$out/car-side.jpg"; then
  echo "Turning your head did not change the seated view." >&2
  exit 1
fi
say "/carprobe left"
import -window root -quality 90 "$out/car-left.jpg"
say "/carprobe right"
import -window root -quality 90 "$out/car-right.jpg"
for direction in full-left full-right roof floor; do
  say "/carprobe $direction"
  import -window root -quality 90 "$out/car-$direction.jpg"
done
say "/carprobe center"
xdotool key F7
sleep .55
import -window root -quality 92 "$out/car-third-back.jpg"
xdotool key F7
sleep .4
import -window root -quality 92 "$out/car-third-front-level.jpg"
xdotool mousemove_relative -- 0 -92
sleep .30
import -window root -quality 92 "$out/car-third-front.jpg"
xdotool mousemove_relative -- 0 92
xdotool key F7
sleep .55
say "/carprobe center"
import -window root -quality 92 "$out/car-first-again.jpg"
xdotool key F7
sleep .45
xdotool keydown w
sleep 1.22
xdotool mousemove_relative -- 0 73
sleep .18
import -window root -quality 92 "$out/car-third-slope.jpg"
xdotool mousemove_relative -- 0 -73
xdotool key F7; sleep .28; xdotool key F7
sleep .77
import -window root -quality 87 "$out/car-driving.jpg"
sleep 3.5
xdotool keyup w
say "/carprobe far"
xdotool keydown s
sleep 3.1
xdotool keyup s
say "/carprobe reverse"
xdotool key i; sleep .45; xdotool mousemove 650 451 click 1
sleep .8
say "/carprobe returned"
import -window root -quality 87 "$out/car-returned.jpg"
grep "CAR_QA" "$out/server.log"
! grep -E 'ERROR\[' "$out/"{server,client}.log
grep -q 'CAR_QA_GRADE' "$out/server.log"
python3 - "$out/server.log" <<'LOG'
import re, sys
lines=open(sys.argv[1]).read().splitlines()
points={}
for line in lines:
    m=re.search(r"CAR_QA (\w+) (\w+) ([^\n]+)$",line)
    if m and m[1]!="trace":
        mode=m[2]; x,y,z,yaw,pitch,ground,hotbar,menu,revision=m[3].split()
        points[m[1]]=(mode,*map(float,(x,y,z,yaw,pitch,ground)),hotbar,menu,revision)
before,entered,far,reverse,returned=(points[k] for k in ("before","entered","far","reverse","returned"))
assert entered[0]==far[0]==reverse[0]=="car" and entered[7]=="false",points
assert far[1]>entered[1]+6 and far[2]>entered[2]+.75,points
assert reverse[1]<far[1]-2 and abs(far[3]-reverse[3])<.05,points
assert returned[0]=="builder" and returned[7:]==before[7:],points
assert all(abs(a-b)<.035 for a,b in zip(before[1:6],returned[1:6])),points
samples=[float(re.search(r"CAR_QA_SPEED (-?[0-9.]+)",line)[1])
         for line in lines if "CAR_QA_SPEED " in line]
assert sum(2.97<=v<=3.03 for v in samples)>=5, samples
assert sum(-1.23<=v<=-1.17 for v in samples)>=4, samples
assert max(samples)<=3.03 and min(samples)>=-1.23, samples
print(f"Native /car: {max(samples):.2f} nodes/s cruise, {-min(samples):.2f} nodes/s reverse. "
      "Hill road driving, Inventory restore, and unchanged route state passed.")
LOG

python3 - "$out" <<'CAMERAS'
from pathlib import Path
from PIL import Image
import sys
out=Path(sys.argv[1])
for phase in ("third-back","third-front","third-slope"):
    image=Image.open(out/f"car-{phase}.jpg").convert("RGB")
    width,height=image.size
    box=image.crop((width//5,height//4,width*4//5,height))
    body=sum(r>90 and r>1.8*g and r>1.75*b for r,g,b in box.getdata())
    assert body>190,(phase,body)
print("CAR_NATIVE_CHASE_PASS painted body in front, rear and moving grade views")

def ratio(phase, rect, pred):
    with Image.open(out/f"car-{phase}.jpg") as image:
        w,h=image.size
        a,b,c,d=rect
        crop=image.convert("RGB").crop((int(w*a),int(h*b),int(w*c),int(h*d)))
        return sum(pred(r,g,b) for r,g,b in crop.getdata()) / (crop.width*crop.height)

window=(.3,.26,.7,.56)
lower=(.3,.66,.7,.88)
landscape=lambda r,g,b: (g>=r+10 and g>=b+9) or (b>=r+20 and g>=r+14)
painted=lambda r,g,b: r>1.2*g and r>1.4*b
brown=lambda r,g,b: r>=g+3 and b<=g-4
assert ratio("entry",window,landscape)>.42,"forward view is blocked"
for phase in ("full-left","full-right"):
    assert ratio(phase,window,landscape)>.55 and ratio(phase,lower,painted)>.40,phase
assert ratio("floor",(.4,.57,.6,.82),brown)>.8,"floor exposes ground or road"
print("CAR_NATIVE_INTERIOR_PASS forward and both side windows are clear; looking down shows an intact floor")
CAMERAS

if [[ ${LUANTTD_NATIVE_REJOIN_CAR:-0} == 1 ]]; then
  say "/carprobe leave-spot"
  for _ in {1..24}; do grep -q RETURN_BOOKMARK_SET "$out/server.log" && break; sleep .25; done
  grep -q RETURN_BOOKMARK_SET "$out/server.log"
  kill "$client";wait "$client" || true
  sleep .55
  luanti --go --address 127.0.0.1 --port "$port" --config "$out/client.conf" --name CarQA --logfile "" > "$out/reconnected.log" 2>&1 &
  client=$!;pids+=("$client")
  win=$(timeout 25 xdotool search --sync --onlyvisible --pid "$client"|tail -1)
  for _ in {1..120}; do
    if [[ $(grep -c 'CarQA.*joins game' "$out/server.log") -ge 2 ]]; then break; fi
    sleep .25
  done
  xdotool windowfocus --sync "$win"
  sleep 1.8
  say "/carprobe rejoined-spot"
  grep RETURN_BOOKMARK_NATIVE_MULTIPLAYER_PASS "$out/server.log"
fi
