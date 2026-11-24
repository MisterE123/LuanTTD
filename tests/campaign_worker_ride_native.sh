#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
out=$(mktemp -d "${TMPDIR:-/tmp}/luanttd-ride-native.XXXXXX")
echo "Native ride evidence: $out"
game="$out/games/luanttd"
mkdir -p "$game" "$out/world" "$out/home" "$out/cache"
cp game.conf "$game/"
cp -al mods "$game/" 2>/dev/null || cp -a mods/. "$game/mods/"
if [[ -n ${LUANTTD_TEST_RIDE_ART:-} ]]; then
  for folder in models textures; do
    cp "$LUANTTD_TEST_RIDE_ART/mods/luanttd_core/$folder"/bl_ride_* "$game/mods/luanttd_core/$folder/"
  done
fi
cp mods/luanttd_core/init.lua "$out/init.lua"
mv "$out/init.lua" "$game/mods/luanttd_core/init.lua"
printf '\n' >>"$game/mods/luanttd_core/init.lua"
cat tests/campaign_worker_ride_native.lua >>"$game/mods/luanttd_core/init.lua"
printf 'gameid = luanttd\nbackend = sqlite3\nplayer_backend = sqlite3\nauth_backend = sqlite3\nmod_storage_backend = sqlite3\n' >"$out/world/world.mt"
port=${BAYLINE_NATIVE_PORT:-42712}
display=${BAYLINE_NATIVE_DISPLAY:-445}
cat >"$out/server.conf" <<CONF
port = $port
bind_address = 127.0.0.1
prometheus_listener_address = 127.0.0.1:$port
server_announce = false
bayline_generated_map_width = 64
bayline_generated_map_depth = 64
bayline_generated_relief = 0
bayline_generated_coasts = 0
bayline_generated_towns = 3
bayline_generated_town_layout = grid2
bayline_seed = 1751
singleplayer_mode = false
CONF
printf 'screen_w = 1440\nscreen_h = 900\nfps_max = 24\nviewing_range = 48\nenable_sound = false\nenable_shaders = false\nenable_dynamic_shadows = false\nkeymap_camera_mode = KEY_F7\n' >"$out/client.conf"
if [[ -n ${BAYLINE_NATIVE_TOOLS:-} ]]; then
  t=$(realpath "$BAYLINE_NATIVE_TOOLS")
  export PATH="$t/run/bin:$t/usr/bin:$PATH" LD_LIBRARY_PATH="$t/usr/lib/x86_64-linux-gnu${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
fi
export DISPLAY="127.0.0.1:$display" HOME="$out/home" LIBGL_ALWAYS_SOFTWARE=1 MESA_SHADER_CACHE_DISABLE=1
export LP_NUM_THREADS="${LP_NUM_THREADS:-2}"
export XDG_CACHE_HOME="${LUANTTD_NATIVE_MEDIA_CACHE:-$out/cache}" LUANTI_GAME_PATH="$out/games" MINETEST_GAME_PATH="$out/games"
# Match an ordinary returning client. Test focus/rider behavior, not two
# cold media downloads competing for the same local server's quota.
if [[ -z ${LUANTTD_NATIVE_MEDIA_CACHE:-} ]]; then
  python3 tests/cache_luanti_game_media.py "$game" "$XDG_CACHE_HOME"
fi
cc -shared -fPIC tests/native_loopback.c -ldl -o "$out/loopback.so"
env LD_PRELOAD="$out/loopback.so" Xvfb ":$display" -screen 0 1440x900x24 -listen tcp -nolisten local -nolisten unix -ac -noreset >"$out/xvfb.log" 2>&1 &
xv=$!; server= client= observer=
trap 'for pid in "$client" "$observer" "$server" "$xv"; do [[ -z "$pid" ]] || kill "$pid" 2>/dev/null || true; done; wait 2>/dev/null || true' EXIT
for _ in {1..40}; do xdpyinfo >/dev/null 2>&1 && break; sleep .25; done
xdpyinfo > /dev/null || { cat "$out/xvfb.log"; exit 1; }
luantiserver --world "$out/world" --gameid luanttd --config "$out/server.conf" --logfile '' >"$out/server.log" 2>&1 &
server=$!
mark(){ for _ in {1..360}; do grep -q "$1" "$out/server.log" && return; kill -0 "$server" 2>/dev/null || break; sleep .25; done; tail -70 "$out/server.log"; return 1; }
mark 'listening on'
# The witness is a real independent client, but only the rider provides
# screenshots. Reduce the observer's viewport/graphics load.
cat > "$out/observer.conf" <<'CONF'
screen_w = 640
screen_h = 400
fps_max = 8
viewing_range = 32
enable_sound = false
enable_shaders = false
enable_dynamic_shadows = false
CONF
mkdir "$out/observer-home"
env HOME="$out/observer-home" luanti --go --address 127.0.0.1 --port "$port" --name RideWitness --password '' --config "$out/observer.conf" --logfile '' >"$out/observer.log" 2>&1 &
observer=$!
luanti --go --address 127.0.0.1 --port "$port" --name RideQA --password '' --config "$out/client.conf" --logfile '' >"$out/client.log" 2>&1 &
client=$!
win=$(xdotool search --sync --onlyvisible --pid "$client" | tail -n 1)
xdotool windowraise "$win" windowfocus --sync "$win"
capture_seat() {
  local phase=$1 view=$2 shot="$out/$1-$2.png"
  # RIDE_VISIBLE confirms server attachment, not client delivery/paint.
  # A bright builder view is not a cabin. Wait for both image predicates
  # without reducing either of the final assertions.
  for _ in {1..28}; do
    sleep .30
    import -window root "$shot"
    if python3 tests/private_ride_pixels.py "$shot" "$phase" "$view"; then return 0; fi
  done
  python3 tests/private_ride_pixels.py "$shot" "$phase" "$view" --explain || true
  tail -40 "$out/server.log"
  return 1
}
for phase in bus cab coach; do
  mark "RIDE_READY $phase"
  xdotool windowraise "$win" windowfocus --sync "$win"
  sleep .30
  import -window root -resize 960x600 -quality 91 "$out/$phase-builder.jpg"
  xdotool mousedown 1; sleep .18; xdotool mouseup 1
  if [[ "$phase" != bus ]]; then
    mark "RIDE_TRAIN_SEAT $phase"
    sleep .52
    if [[ "$phase" == cab ]]; then xdotool mousemove 810 473 click 1
    else xdotool mousemove 620 473 click 1
    fi
  fi
  mark "RIDE_VISIBLE $phase"
  capture_seat "$phase" forward
  xdotool key F7; sleep .50
  import -window root -resize 960x600 -quality 91 "$out/$phase-third-back.jpg"
  xdotool key F7; sleep .50
  import -window root -resize 960x600 -quality 91 "$out/$phase-third-front.jpg"
  xdotool key F7; sleep .35
  xdotool keydown w; xdotool mousemove_relative -- 250 15; sleep 1; xdotool keyup w
  mark "RIDE_SIDE_VIEW $phase"
  capture_seat "$phase" side
  xdotool key i; sleep .62
  import -window root -resize 960x600 -quality 91 "$out/$phase-inventory.jpg"
  xdotool mousemove 720 469 click 1
  mark "PASS NATIVE PRIVATE RIDE $phase"
done
mark 'PASS NATIVE ALL SEATED MODES'
python3 tests/private_ride_pixels.py "$out"
grep -E 'RIDE|PASS NATIVE' "$out/server.log"
! grep -E 'ERROR\[' "$out/server.log" "$out/client.log" "$out/observer.log"
