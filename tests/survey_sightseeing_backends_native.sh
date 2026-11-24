#!/usr/bin/env bash
# Actual Linux Survey hotbar Car and Plane gestures against a fresh native campaign.
set -euo pipefail
cd "$(dirname "$0")/.."
out=$(mktemp -d "${TMPDIR:-/tmp}/luanttd-survey-backends-native.XXXXXX")
echo "Native Survey evidence: $out"
game="$out/games/luanttd"
mkdir -p "$game" "$out/"{world,home,cache}
cp game.conf "$game/"
cp -al mods "$game/" 2>/dev/null || cp -a mods/. "$game/mods/"
cp "$game/mods/luanttd_core/init.lua" "$out/native-init"
mv "$out/native-init" "$game/mods/luanttd_core/init.lua"
printf '\n' >>"$game/mods/luanttd_core/init.lua"
cat tests/survey_sightseeing_backends_native.lua >>"$game/mods/luanttd_core/init.lua"
printf 'gameid = luanttd\nbackend = sqlite3\nplayer_backend = sqlite3\nauth_backend = sqlite3\nmod_storage_backend = sqlite3\n' >"$out/world/world.mt"
port=${BAYLINE_NATIVE_PORT:-40615}
display=${BAYLINE_NATIVE_DISPLAY:-195}
cat >"$out/server.conf" <<CONF
port = $port
bind_address = 127.0.0.1
server_announce = false
bayline_generated_map_width = 64
bayline_generated_map_depth = 64
bayline_generated_relief = 0
bayline_generated_coasts = 0
bayline_generated_tree_placer = 0
CONF
cat >"$out/client.conf" <<CONF
screen_w = 1280
screen_h = 800
enable_sound = false
enable_shaders = false
viewing_range = 44
fps_max = 30
CONF
if [[ -n ${BAYLINE_NATIVE_TOOLS:-} ]]; then
  t=$(realpath "$BAYLINE_NATIVE_TOOLS")
  export PATH="$t/run/bin:$t/usr/bin:$PATH" LD_LIBRARY_PATH="$t/usr/lib/x86_64-linux-gnu${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
fi
export DISPLAY="127.0.0.1:$display" HOME="$out/home" LIBGL_ALWAYS_SOFTWARE=1 LP_NUM_THREADS=2
export XDG_CACHE_HOME="${LUANTTD_NATIVE_MEDIA_CACHE:-$out/cache}" LUANTI_GAME_PATH="$out/games" MINETEST_GAME_PATH="$out/games"
cc -shared -fPIC tests/native_loopback.c -ldl -o "$out/loopback.so"
env LD_PRELOAD="$out/loopback.so" Xvfb ":$display" -screen 0 1280x800x24 -listen tcp -nolisten local -nolisten unix -ac -noreset >"$out/xvfb.log" 2>&1 &
xv=$!; server= client=
trap 'kill "$xv" 2>/dev/null || true; [[ -z "$client" ]] || kill "$client" 2>/dev/null || true; [[ -z "$server" ]] || kill "$server" 2>/dev/null || true; wait 2>/dev/null || true' EXIT
for _ in {1..40}; do xdpyinfo >/dev/null 2>&1 && break; sleep .25; done
luantiserver --world "$out/world" --gameid luanttd --config "$out/server.conf" --logfile '' >"$out/server.log" 2>&1 &
server=$!
mark(){
  for _ in {1..300}; do
    grep -q "$1" "$out/server.log" && return
    kill -0 "$server" 2>/dev/null || break
    sleep .20
  done
  tail -60 "$out/server.log"; return 1
}
mark 'listening on'
luanti --go --address 127.0.0.1 --port "$port" --name SurveyReview --password '' --config "$out/client.conf" --logfile '' >"$out/client.log" 2>&1 &
client=$!
mark SURVEY_BACKENDS_READY
win=$(xdotool search --sync --limit 1 --onlyvisible --pid "$client"|tail -1)
xdotool windowfocus --sync "$win"
sleep 1
press(){ xdotool mousedown "$1"; sleep .22; xdotool mouseup "$1"; }
press_until(){
  local button=$1 marker=$2
  for _ in {1..4}; do
    press "$button"
    for _ in {1..8}; do grep -q "$marker" "$out/server.log" && return; sleep .09; done
  done
  mark "$marker"
}
snap() {
  if command -v import >/dev/null; then import -window root "$out/$1.png"; fi
}
xdotool key 1; sleep .35
press_until 1 SURVEY_BACKENDS_OPEN
xdotool key 7; mark SURVEY_BACKENDS_CAR_SELECTED; sleep .35
snap survey-car-selected
press_until 1 SURVEY_BACKENDS_CAR_REJECT
press_until 1 SURVEY_BACKENDS_CAR_ENTER
snap survey-car-cockpit
xdotool keydown w
mark SURVEY_BACKENDS_CAR_MOVED
xdotool keyup w
exit_scenic() {
  xdotool key i; sleep .44
  snap survey-inventory
  xdotool mousemove 640 420 click 1
  sleep .42
}
press 3
sleep .25
exit_scenic
mark SURVEY_BACKENDS_CAR_RESTORE
xdotool key 6; sleep .34
press 1
mark SURVEY_BACKENDS_WALK_ENTER
mark SURVEY_BACKENDS_HANGAR_AIMED
snap survey-plane-hangar
press_until 1 SURVEY_BACKENDS_PLANE_ENTER
snap survey-plane-cockpit
xdotool keydown w keydown space
mark SURVEY_BACKENDS_PLANE_AIRBORNE
snap survey-plane-airborne
xdotool keyup space keyup w
exit_scenic
mark SURVEY_BACKENDS_WALK_RESTORED
exit_scenic
mark 'PASS NATIVE SURVEY BACKENDS'

grep -E 'SURVEY_BACKENDS_|PASS NATIVE SURVEY' "$out/server.log"
! grep 'ERROR\[' "$out/"{client,server}.log
