#!/usr/bin/env bash
# Actual game + Luanti client. Native keyboard/command input is the only
# flight control path used; the QA mod places two stock airports and logs.
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ -n ${BAYLINE_NATIVE_TOOLS:-} ]]; then
  t=$(realpath "$BAYLINE_NATIVE_TOOLS")
  export PATH="$t/run/bin:$t/usr/bin:$PATH" LD_LIBRARY_PATH="$t/usr/lib/x86_64-linux-gnu${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
fi
out=$(mktemp -d "${TMPDIR:-/tmp}/luanttd-plane.XXXXXX")
echo "Native sightseeing cockpit evidence: $out"
game="$out/games/luanttd"
mkdir -p "$game" "$out/world" "$out/home" "$out/cache"
cp -al mods "$game/" 2>/dev/null || cp -a mods "$game/"
cp game.conf settingtypes.txt "$game/"
if [[ -n ${BAYLINE_NATIVE_CACHE_SEED:-} && -d "$BAYLINE_NATIVE_CACHE_SEED/minetest" ]]; then
  cp -al "$BAYLINE_NATIVE_CACHE_SEED/minetest" "$out/cache/" 2>/dev/null ||
    cp -a "$BAYLINE_NATIVE_CACHE_SEED/minetest" "$out/cache/"
fi
mod="$game/mods/luanttd_core"
cp "$mod/init.lua" "$out/init.lua"
mv -f "$out/init.lua" "$mod/init.lua"
printf 'return function() return {enabled=true,local_replay=true} end\n' > "$mod/qa_layout.lua"
cp tests/avatar_plane_live_native.lua "$mod/avatar_plane_live_native.lua"
printf '\ndofile(mod.."/avatar_plane_live_native.lua")(api)\n' >> "$mod/init.lua"
# Capture the live state only inside this disposable copy so the test
# can establish a stable short final rather than fake a landing outcome.
sed '/^return F$/i local start=F.start;function F.start(r) local f=start(r);core.luanttd_qa_flight(f);return f end' \
  "$mod/sightseeing_flight.lua" > "$out/flight.lua"
mv -f "$out/flight.lua" "$mod/sightseeing_flight.lua"
printf 'gameid = luanttd\nbackend = sqlite3\nplayer_backend = sqlite3\nauth_backend = sqlite3\nmod_storage_backend = sqlite3\n' > "$out/world/world.mt"
port=${BAYLINE_NATIVE_PORT:-39958}
cat > "$out/server.conf" <<CONF
port = $port
prometheus_listener_address = 127.0.0.1:$port
server_announce = false
bind_address = 127.0.0.1
bayline_stock_bus_start_year = 1965
CONF
cat > "$out/client.conf" <<'CONF'
screen_w = 1280
screen_h = 800
fullscreen = false
keymap_camera_mode = KEY_F7
enable_sound = true
viewing_range = 128
fps_max = 40
enable_dynamic_shadows = false
CONF
export HOME="$out/home" XDG_CACHE_HOME="${LUANTTD_NATIVE_MEDIA_CACHE:-$out/cache}" LUANTI_GAME_PATH="$out/games" MINETEST_GAME_PATH="$out/games"
export LIBGL_ALWAYS_SOFTWARE=1 ALSOFT_DRIVERS=null MESA_SHADER_CACHE_DISABLE=1
disp=${BAYLINE_NATIVE_DISPLAY:-224}
export DISPLAY="127.0.0.1:$disp"
cc -shared -fPIC tests/native_loopback.c -ldl -o "$out/loopback.so"
env LD_PRELOAD="$out/loopback.so" Xvfb ":$disp" -screen 0 1280x800x24 -listen tcp -nolisten local -nolisten unix -ac -noreset >"$out/xvfb.log" 2>&1 &
xv=$!; server= client=
trap '[[ -z "$client" ]] || kill "$client" 2>/dev/null || true; [[ -z "$server" ]] || kill "$server" 2>/dev/null || true; kill "$xv" 2>/dev/null || true; wait 2>/dev/null || true' EXIT
for _ in {1..40}; do xdpyinfo >/dev/null 2>&1 && break; sleep .25; done
xdpyinfo >/dev/null
luantiserver --world "$out/world" --gameid luanttd --config "$out/server.conf" --logfile '' >"$out/server.log" 2>&1 &
server=$!
mark(){ for _ in {1..140}; do grep -q "$1" "$out/server.log" && return; kill -0 "$server" 2>/dev/null || break; sleep .25; done; tail -65 "$out/server.log"; return 1; }
mark 'listening on'
luanti --go --address 127.0.0.1 --port "$port" --name PilotQA --password '' --config "$out/client.conf" --logfile '' >"$out/client.log" 2>&1 &
client=$!
window=$(timeout 20 xdotool search --onlyvisible --sync --pid "$client" | tail -n 1)
xdotool windowfocus --sync "$window"
mark 'PLANE_QA READY'
sleep 1
say(){ xdotool key t; sleep .20; xdotool type "$*"; xdotool key Return; sleep .38; }
say '/plane'
say '/planetrace returned'
mark 'PLANE_QA miss returned'
for layout in country city; do
  say "/planetrace $layout"
  mark "PLANE_QA $layout start"
  say '/plane'
  say '/planetrace board'
  mark "PLANE_QA $layout board"
  sleep 1
  import -window root "$out/$layout-cockpit.png"
  xdotool key F7; sleep .55
  import -window root "$out/$layout-third-back.png"
  xdotool key F7; sleep .55
  import -window root "$out/$layout-third-front.png"
  xdotool key F7; sleep .35
  xdotool keydown w keydown space
  sleep 2.8
  xdotool keyup w keyup space
  say '/planetrace takeoff'
  mark "PLANE_QA $layout takeoff"
  if [[ $layout == country ]]; then
    xdotool keydown d
    sleep .85
    xdotool keyup d
    mark "PLANE_QA $layout bank"
  fi
  import -window root "$out/$layout-flight.png"
  xdotool keydown e
  sleep .28
  xdotool keyup e
  sleep .42
  say '/planetrace reset'
  mark "PLANE_QA $layout reset"
  xdotool key t; sleep .20; xdotool type '/planetrace short_final'; xdotool key Return
  sleep .12
  xdotool keydown Shift_L
  sleep .64
  xdotool keyup Shift_L
  sleep 1.12
  say '/planetrace landed'
  mark "PLANE_QA $layout landed"
  if [[ $layout == country ]]; then xdotool key i; sleep .45; xdotool mousemove 640 420 click 1; sleep .65; else say '/plane'; fi
  say '/planetrace returned'
  mark "PLANE_QA $layout returned"
done
! grep -E 'ERROR\[' "$out/server.log" "$out/client.log"
echo 'PASS native Country and City cockpit, real flight controls, manual touchdown and audio, recovery and exact builder restoration'
