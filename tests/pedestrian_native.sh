#!/usr/bin/env bash
# Exercise /walk and right-click on a real campaign with a disposable road and house.
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
cp -a game.conf settingtypes.txt "$game/"
mod="$game/mods/luanttd_core"
cp "$mod/init.lua" "$mod/init.native.lua"
mv -f "$mod/init.native.lua" "$mod/init.lua"
cp tests/pedestrian_live_native.lua "$mod/pedestrian_live_native.lua"
printf '\ndofile(mod.."/pedestrian_live_native.lua")(api)\n' >> "$mod/init.lua"
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
enable_sound = false
viewing_range = 80
fps_max = 30
enable_shaders = true
enable_dynamic_shadows = false
video_driver = opengl
shadow_map_max_distance = 100
shadow_map_texture_size = 1024
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
luantiserver --world "$out/world" --config "$out/server.conf" --gameid luanttd --logfile "" > "$out/server.log" 2>&1 &
pids+=("$!")
for _ in {1..40}; do if grep -q 'listening' "$out/server.log"; then break; fi; sleep .25; done
grep -q 'listening' "$out/server.log" || { cat "$out/server.log"; exit 1; }
luanti --go --address 127.0.0.1 --port "$port" --config "$out/client.conf" --name WalkQA --logfile "" > "$out/client.log" 2>&1 &
client=$!
pids+=("$client")
for _ in {1..120}; do if grep -q "WALK_QA ready" "$out/server.log"; then break; fi; sleep .25; done
grep -q "WALK_QA ready" "$out/server.log" || { cat "$out/"{server,client}.log; exit 1; }
win=$(xdotool search --sync --onlyvisible --pid "$client"|tail -1)
xdotool windowfocus --sync "$win"
xdotool mousemove 650 430
sleep 3

say() {
  xdotool key t; sleep .24; xdotool type "$1"; xdotool key Return; sleep .52
}
say "/walkprobe before"
import -window root "$out/builder-first.png"
xdotool key c
sleep .45
import -window root "$out/builder-rear.png"
xdotool key c
sleep .45
import -window root "$out/builder-front.png"
xdotool key c
sleep .4
say "/walk"
sleep 1.1
say "/walkprobe entered"
import -window root "$out/walk-entry.png"
xdotool key c
sleep .65
import -window root "$out/walk-thirdperson.png"
xdotool key c
sleep .5
import -window root "$out/walk-front-avatar.png"
xdotool key c
sleep .35
xdotool key c
sleep .35
# A held construction click must not build in cinematic mode. Then walk
# up the actual road slope until the visible house collision stops us.
xdotool mousedown 1
sleep .38
xdotool mouseup 1
xdotool keydown w
sleep 2.7
import -window root "$out/walk-gait-a.png"
sleep .28
import -window root "$out/walk-gait-b.png"
sleep .52
import -window root "$out/walk-on-street.png"
sleep 3.6
xdotool keyup w
sleep .8
say "/walkprobe blocked"
import -window root "$out/walk-house-stop.png"
say "/walkprobe doorway"
xdotool key c
sleep .40
xdotool key c
sleep .55
import -window root "$out/walk-door-eye.png"
xdotool key c
sleep .5
import -window root "$out/walk-door-scale.png"
xdotool click 3
sleep .7
say "/walkprobe returned"
import -window root "$out/walk-returned.png"
grep "WALK_QA" "$out/server.log"
grep "WALK_AVATAR" "$out/server.log"
grep "WALK_DOOR_EYE" "$out/server.log"
! grep -E 'ERROR\[' "$out/"{server,client}.log
python3 "$repo/tests/pedestrian_native_evidence.py" "$out/server.log"
