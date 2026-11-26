#!/usr/bin/env bash
# Native radio tower beacon scene on a disposable campaign.
set -euo pipefail
cd "$(dirname "$0")/.."
repo=$PWD
if [[ -n ${BAYLINE_NATIVE_TOOLS:-} ]]; then
  tools=$(realpath "$BAYLINE_NATIVE_TOOLS")
  export PATH="$tools/run/bin:$tools/usr/bin:$PATH"
  export LD_LIBRARY_PATH="$tools/usr/lib/x86_64-linux-gnu${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
fi
out=$(mktemp -d "${TMPDIR:-/tmp}/luanttd-radio-beacon.XXXXXX")
echo "Native beacon evidence: $out"
disp=${BAYLINE_NATIVE_DISPLAY:-192}
port=${BAYLINE_NATIVE_PORT:-39892}
pids=()
cleanup() {
  for pid in "${pids[@]}"; do kill -TERM "$pid" 2>/dev/null || true; done
  wait || true
}
trap cleanup EXIT
game="$out/games/luanttd"
mkdir -p "$game" "$out/"{world,home,cache}
# Reuse immutable game media without writing into the working checkout.
cp -al mods "$game/" || cp -a mods "$game/"
cp -a game.conf "$game/"
printf 'return function() return {local_replay=true} end\n' >"$game/mods/luanttd_core/qa_layout.lua"
mod="$game/mods/luanttd_core"
cp "$mod/init.lua" "$mod/init.native.lua"
mv -f "$mod/init.native.lua" "$mod/init.lua"
cp tests/radio_beacon_native.lua "$mod/radio_beacon_native.lua"
printf '\ndofile(mod.."/radio_beacon_native.lua")(api)\n' >> "$mod/init.lua"
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
bayline_scenario = generated
bayline_generated_map_width = 64
bayline_generated_map_depth = 64
bayline_seed = 1751
EOF
cat > "$out/client.conf" <<'EOF'
screen_w = 1300
screen_h = 860
fullscreen = false
enable_sound = false
viewing_range = 43
client_mapblock_limit = 480
mesh_generation_threads = 2
enable_waving_water = false
fps_max = 30
enable_shaders = true
enable_dynamic_shadows = false
video_driver = opengl
shadow_map_max_distance = 100
shadow_map_texture_size = 1024
EOF
export HOME="$out/home" XDG_CACHE_HOME="${LUANTTD_NATIVE_MEDIA_CACHE:-$out/cache}" XDG_CONFIG_HOME="$out/home/.config" \
  LUANTI_GAME_PATH="$out/games" MINETEST_GAME_PATH="$out/games" \
  LP_NUM_THREADS=2 LIBGL_ALWAYS_SOFTWARE=1 ALSOFT_DRIVERS=null
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
luanti --go --address 127.0.0.1 --port "$port" --config "$out/client.conf" --name WalkQA --logfile "" > "$out/client.log" 2>&1 &
client=$!
pids+=("$client")
for _ in {1..220}; do if grep -q "RADIO_BEACON_NATIVE_READY" "$out/server.log"; then break; fi; sleep .25; done
grep -q "RADIO_BEACON_NATIVE_READY" "$out/server.log" || { cat "$out/"{server,client}.log; exit 1; }

sleep 1.0
for frame in {1..22}; do
  import -window root "$out/beacon-$frame.png"
  sleep .11
done
for _ in {1..55}; do grep -q RADIO_BEACON_NATIVE_PASS "$out/server.log" && break; sleep .15; done
grep RADIO_BEACON_NATIVE_PASS "$out/server.log" || { cat "$out/"{server,client}.log; exit 1; }
! grep -Ei 'ERROR|could not load' "$out/client.log"
python3 - "$out" <<'PYTEST'
from pathlib import Path
from PIL import Image
import shutil, sys
root=Path(sys.argv[1])
frames=[]
for f in root.glob("beacon-*.png"):
    im=Image.open(f).convert("RGB")
    pixels=sum(r>175 and r>g+85 and r>b+80 for r,g,b in
        im.crop((625,385,680,460)).getdata())
    frames.append((pixels,f))
frames.sort()
assert frames[-1][0]-frames[0][0]>30, frames
shutil.copyfile(frames[-1][1],root/"flash.png")
shutil.copyfile(frames[len(frames)//4][1],root/"rest.png")
print("PASS native client shows the red flash at the physical mast housing")
PYTEST
