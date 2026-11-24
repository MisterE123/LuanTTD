#!/usr/bin/env bash
# Standalone native test using the production atmosphere; no full-game media copy.
set -euo pipefail
cd "$(dirname "$0")/.."
repo=$PWD
if [[ -n ${BAYLINE_NATIVE_TOOLS:-} ]]; then
  tools=$(realpath "$BAYLINE_NATIVE_TOOLS")
  export PATH="$tools/run/bin:$tools/usr/bin:$PATH"
  export LD_LIBRARY_PATH="$tools/usr/lib/x86_64-linux-gnu${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
fi
out=$(mktemp -d "${TMPDIR:-/tmp}/luanttd-atmosphere.XXXXXX")
echo "Native day/night evidence: $out"
disp=${BAYLINE_NATIVE_DISPLAY:-193}
port=${BAYLINE_NATIVE_PORT:-39893}
pids=()
cleanup() {
  for pid in "${pids[@]}"; do kill -TERM "$pid" 2>/dev/null || true; done
  wait || true
}
trap cleanup EXIT
mod="$out/games/atmosphere_test/mods/atmosphere"
mkdir -p "$mod/"{models,textures} "$out/"{world,home,cache}
printf 'title = LuanTTD day-night atmosphere fixture\n' > "$out/games/atmosphere_test/game.conf"
printf 'name = atmosphere\n' > "$mod/mod.conf"
cp tests/atmosphere_native.lua "$mod/init.lua"
cp mods/luanttd_core/atmosphere.lua "$mod/atmosphere.lua"
cp mods/luanttd_core/textures/{bl_coastal_moon,bl_grass2,bl_grass_side,bl_hill_side,bl_water_sea_anim}.png "$mod/textures/"
cp mods/luanttd_core/models/bl_land_3.obj "$mod/models/"
if [[ ${BAYLINE_ATMOSPHERE_TEST_FEATURE:-0} == 1 ]]; then
  cp mods/luanttd_core/models/bl_stock_forest_{0,1,2}_2.obj "$mod/models/"
  cp mods/luanttd_core/textures/bl_scenery_palette.png "$mod/textures/"
fi
python3 - "$mod/textures/calibration.png" <<'PYQA'
from PIL import Image, ImageDraw
from sys import argv
im=Image.new('RGB',(64,64))
d=ImageDraw.Draw(im)
d.rectangle((0,0,31,31),fill='#d22d12')
d.rectangle((32,0,63,31),fill='#20ef2f')
d.rectangle((0,32,31,63),fill='#224ddd')
d.rectangle((32,32,63,63),fill='#f8e842')
im.save(argv[1])
Image.new("RGB",(16,16),"#abb1a3").save(argv[1].replace("calibration.png","pad.png"))
PYQA
printf 'gameid = atmosphere_test\nbackend = sqlite3\nplayer_backend = sqlite3\nauth_backend = sqlite3\nmod_storage_backend = sqlite3\n' > "$out/world/world.mt"
cat > "$out/server.conf" <<EOF
port = $port
prometheus_listener_address = 127.0.0.1:$port
server_announce = false
bind_address = 127.0.0.1
time_speed = ${BAYLINE_ATMOSPHERE_TEST_SPEED:-0}
luanttd_daylight_feature_test = ${BAYLINE_ATMOSPHERE_TEST_FEATURE:-0}
bayline_coastal_haze = ${BAYLINE_ATMOSPHERE_TEST_HAZE:-true}
EOF
cat > "$out/client.conf" <<'EOF'
screen_w = 1300
screen_h = 860
fullscreen = false
enable_sound = false
viewing_range = 80
fps_max = 30
enable_shaders = true
enable_dynamic_shadows = true
video_driver = opengl
shadow_map_max_distance = 100
shadow_map_texture_size = 1024
EOF
if [[ ${BAYLINE_ATMOSPHERE_TEST_FEATURE:-0} == 1 ]]; then
  printf 'enable_post_processing = true
enable_bloom = true
enable_volumetric_lighting = true
fov = 104
' >>"$out/client.conf"
fi
export LP_NUM_THREADS=2
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
luantiserver --world "$out/world" --config "$out/server.conf" --gameid atmosphere_test --logfile "" > "$out/server.log" 2>&1 &
pids+=("$!")
for _ in {1..40}; do if grep -q 'listening' "$out/server.log"; then break; fi; sleep .25; done
grep -q 'listening' "$out/server.log" || { cat "$out/server.log"; exit 1; }
luanti --go --address 127.0.0.1 --port "$port" --config "$out/client.conf" --name AtmosphereQA --logfile "" > "$out/client.log" 2>&1 &
client=$!
pids+=("$client")
for _ in {1..120}; do if grep -q ATMOSPHERE_READY "$out/server.log"; then break; fi; sleep .25; done
grep -q ATMOSPHERE_READY "$out/server.log" || { cat "$out/"{server,client}.log; exit 1; }
win=$(xdotool search --sync --onlyvisible --pid "$client"|tail -1)
xdotool windowfocus --sync "$win"
xdotool mousemove 650 430
sleep 3
xdotool key F1
sleep 2
if [[ ${BAYLINE_ATMOSPHERE_TEST_FEATURE:-0} == 1 ]]; then
  for shot in rays-off rays-on hold cycle; do
    xdotool key t; sleep .2; xdotool type "/atmosfeature $shot"; xdotool key Return
    for _ in {1..40}; do
      if grep -q "ATMOSPHERE_FEATURE $shot" "$out/server.log"; then break; fi
      sleep .25
    done
    grep "ATMOSPHERE_FEATURE $shot" "$out/server.log"
    sleep 2
    import -window "$win" -quality 92 "$out/lighting-$shot.jpg"
  done
  python3 - "$out" <<'PYQA'
from pathlib import Path
from statistics import mean
from sys import argv
from PIL import Image

root = Path(argv[1])
def sample(shot, area):
    region = Image.open(root / f"lighting-{shot}.jpg").convert("L").crop(area)
    return mean(region.getdata())

halo = (450, 129, 760, 410)
baseline = sample("rays-off", halo)
scattering = sample("rays-on", halo)
assert scattering > baseline + 12, (baseline, scattering, "no native volumetric sun glow")
assert sample("hold", halo) > sample("cycle", halo) + 24, "held sunlight didn't show in the client"
print(f"Native rendered bloom/volume: same camera halo {baseline:.1f} → {scattering:.1f}; verified fixed day vs restored night")
PYQA
elif [[ ${BAYLINE_ATMOSPHERE_TEST_SPEED:-0} == 0 ]]; then
  for shot in noon dusk moonrise midnight slope shadow; do
    xdotool key t; sleep .2; xdotool type "/atmosqa $shot"; xdotool key Return
    sleep 2.25
    import -window root "$out/atmosphere-$shot.png"
  done
  python3 - "$out" <<'PYQA'
from pathlib import Path
from statistics import mean
from sys import argv
from PIL import Image

root=Path(argv[1])
shots={name:Image.open(root/f"atmosphere-{name}.png").convert("RGB")
       for name in ("noon","dusk","moonrise","midnight","slope","shadow")}
def pixels(im,box):
    cut=im.crop(box)
    return list(cut.get_flattened_data() if hasattr(cut,"get_flattened_data") else cut.getdata())
def lunar_pixels(im,box):
    return sum(r>150 and g>150 and b>144 and max(r,g,b)-min(r,g,b)<12
               for r,g,b in pixels(im,box))
# Follow the same fixed camera over the same meadow at noon, dusk and moonrise.
ground=(155,705,215,740)
levels=[mean((r*2+g*5+b)/8 for r,g,b in pixels(shots[name],ground))
        for name in ("noon","dusk","moonrise")]
assert levels[0]>levels[1]>levels[2]>27,levels
assert levels[2]>levels[0]*.42,levels
moon_box=(530,275,710,480)
assert lunar_pixels(shots["noon"],moon_box)<10
moon=shots["moonrise"]
square=[]
for y in range(moon_box[1],moon_box[3]):
    for x in range(moon_box[0],moon_box[2]):
        r,g,b=moon.getpixel((x,y))
        if r>150 and g>150 and b>144 and max(r,g,b)-min(r,g,b)<12:
            square.append((x,y))
assert len(square)>500,"no moon visible at moonrise"
xs,ys=zip(*square)
w,h=max(xs)-min(xs)+1,max(ys)-min(ys)+1
assert abs(w-h)<=3 and len(square)>.93*w*h,(w,h,len(square))
print(f"Square moon: {w}×{h} projected pixels, {len(square)} filled")
assert lunar_pixels(shots["midnight"],(250,30,650,220))>500,"no moon visible by midnight"
print("Readable lighting: noon, dusk, moonrise:",tuple(round(x,1) for x in levels))
def light_at(p):
    x,y=p
    return mean(sum(rgb)/3 for rgb in pixels(shots["shadow"],(x-3,y-3,x+4,y+4)))
diagonal=light_at((570,480))
assert diagonal+25<min(light_at((570,420)),light_at((650,485))),"no diagonal post shadow"
print("Diagonal shadow confirmed off both orthogonal axes")
PYQA
else
  grep -q "ATMOSPHERE_VIEW advance" "$out/server.log"
fi
if [[ ${BAYLINE_ATMOSPHERE_TEST_FEATURE:-0} != 1 ]]; then grep "ATMOSPHERE_VIEW" "$out/server.log"; fi
! grep -Ei 'error|could not load' "$out/"{server,client}.log
