#!/usr/bin/env bash
# Exercise /walk and inventory exit on a real campaign with a disposable road and house.
set -euo pipefail
cd "$(dirname "$0")/.."
repo=$PWD
if [[ -n ${BAYLINE_NATIVE_TOOLS:-} ]]; then
  tools=$(realpath "$BAYLINE_NATIVE_TOOLS")
  export PATH="$tools/run/bin:$tools/usr/bin:$PATH"
  export LD_LIBRARY_PATH="$tools/usr/lib/x86_64-linux-gnu${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
fi
out=$(mktemp -d "${TMPDIR:-/tmp}/luanttd-pedestrian.XXXXXX")
echo "Native pedestrian evidence: $out"
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
cp -al mods "$game/" || cp -a mods "$game/"
cp -a game.conf "$game/"
printf 'return function() return {local_replay=true} end\n' >"$game/mods/luanttd_core/qa_layout.lua"
mod="$game/mods/luanttd_core"
cp "$mod/init.lua" "$mod/init.native.lua"
mv -f "$mod/init.native.lua" "$mod/init.lua"
cp tests/coast_swim_native.lua "$mod/coast_swim_native.lua"
printf '\ndofile(mod.."/coast_swim_native.lua")(api)\n' >> "$mod/init.lua"
if [[ -z ${LUANTTD_NATIVE_MEDIA_CACHE:-} && -n ${BAYLINE_NATIVE_CACHE_SEED:-} && -d "$BAYLINE_NATIVE_CACHE_SEED/minetest" ]]; then
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
if [[ ${BAYLINE_SWIM_TRANSITION_ONLY:-0} == 1 ]]; then
  cat >> "$out/client.conf" <<'EOF'
screen_w = 960
screen_h = 640
viewing_range = 32
client_mapblock_limit = 180
mesh_generation_threads = 1
enable_shaders = false
EOF
fi
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
for _ in {1..220}; do if grep -q "WALK_QA ready" "$out/server.log"; then break; fi; sleep .25; done
grep -q "WALK_QA ready" "$out/server.log" || { cat "$out/"{server,client}.log; exit 1; }
win=$(timeout 15 xdotool search --sync --onlyvisible --pid "$client"|tail -1)
xdotool windowfocus --sync "$win"
if [[ ${BAYLINE_SWIM_TRANSITION_ONLY:-0} == 1 ]]; then
  xdotool mousemove --window "$win" 480 320
else
  xdotool mousemove 650 430
fi
sleep 3

say() {
  xdotool key t; sleep .24; xdotool type "$1"; xdotool key Return; sleep .52
}

capture() { import -window "$win" -quality 93 "$out/$1.jpg"; }
hold() { local seconds=$1; shift; xdotool keydown "$@"; sleep "$seconds"; xdotool keyup "$@"; }
if [[ ${BAYLINE_WALL_TEST_ONLY:-0} == 1 ]]; then
  say "/swimprobe fence"
  say "/walk"
  sleep .8
  hold 1.6 w
  hold .32 w space
  hold 2.3 w
  say "/swimprobe house"
  capture house
  xdotool key i; sleep .35; xdotool mousemove 650 451 click 1
  sleep .65
  say "/swimprobe silo"
  say "/walk"
  hold 1.65 w
  say "/swimprobe silo_blocked"
  capture silo
  grep -q "COAST_SWIM_PASS house" "$out/server.log"
  grep -q "COAST_SWIM_PASS silo_blocked" "$out/server.log"
  exit
fi
say "/walk"
capture coast
if [[ ${BAYLINE_SWIM_TRANSITION_ONLY:-0} == 1 ]]; then
  hold 4.7 w
  sleep .45
  say "/swimprobe float"
  capture swim
  say "/swimprobe under_bank"
  sleep .45
  grep -q "COAST_SWIM_PASS under_bank" "$out/server.log" || { cat "$out/server.log"; exit 1; }
  xdotool keydown s space
  for _ in {1..32}; do
    if grep -q "COAST_SWIM dry_edge" "$out/server.log"; then break; fi
    sleep .25
  done
  xdotool keyup space
  sleep 8
  xdotool keyup s
  sleep .25
  say "/swimprobe shore_on_foot"
  capture ashore
  for p in float under_bank shore_on_foot; do grep -q "COAST_SWIM_PASS $p" "$out/server.log" || { cat "$out/server.log"; exit 1; }; done
  ! grep -Ei 'error|could not load' "$out/client.log"
  exit
fi
hold 2.4 w
sleep .45
say "/swimprobe float"
capture swim
xdotool key c; sleep .4; capture swimming-avatar
xdotool key c; sleep .15; xdotool key c; sleep .25
hold 3.5 s space
sleep .25
say "/swimprobe climb"
capture ashore
xdotool key i; sleep .35; xdotool mousemove 650 451 click 1
sleep .65
say "/swimprobe bridge"
say "/walk"
hold 4.3 w
hold .55 d
say "/swimprobe guard"
capture bridge-guard
xdotool keydown a; sleep .19; xdotool keyup a
capture bridge
hold 6.3 w
say "/swimprobe span"
xdotool key i; sleep .35; xdotool mousemove 650 451 click 1
sleep .65
say "/swimprobe field"
say "/walk"
hold 1.1 w
capture plowed-slope
hold 2.3 w
say "/swimprobe crop"
xdotool key i; sleep .35; xdotool mousemove 650 451 click 1
sleep .65
say "/swimprobe returned"
say "/swimprobe fence"
say "/walk"
sleep .8
hold 1.6 w
say "/swimprobe barrier"
capture fence
hold .32 w space
hold .60 w
say "/swimprobe jumped"
hold 1.9 w
say "/swimprobe house"
capture house
xdotool key i; sleep .35; xdotool mousemove 650 451 click 1
sleep .65
say "/swimprobe parcel"
say "/walk"
hold 1.55 w
say "/swimprobe parcel_blocked"
capture parcel
hold .28 w space
hold .30 w
say "/swimprobe parcel_jumped"
xdotool key i; sleep .35; xdotool mousemove 650 451 click 1
sleep .65
say "/swimprobe silo"
say "/walk"
hold 1.65 w
say "/swimprobe silo_blocked"
capture silo
xdotool key i; sleep .35; xdotool mousemove 650 451 click 1
sleep .65
say "/swimprobe arena"
say "/walk"
hold 1.80 w
say "/swimprobe arena_crossed"
capture stadium
xdotool key i; sleep .35; xdotool mousemove 650 451 click 1
sleep .65
say "/swimprobe arena2"
say "/walk"
hold .94 w
say "/swimprobe arena2_crossed"
capture stadium-2
for p in arena_crossed arena2_crossed guard parcel_blocked parcel_jumped silo_blocked float climb span crop returned barrier jumped house; do grep -q "COAST_SWIM_PASS $p" "$out/server.log" || { cat "$out/server.log"; exit 1; }; done
! grep -Ei 'error|could not load' "$out/client.log"
