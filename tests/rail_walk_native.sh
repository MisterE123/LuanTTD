#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
out=$(mktemp -d "${TMPDIR:-/tmp}/luanttd-rail-walk.XXXXXX")
out=$(realpath "$out")
echo "Evidence: $out"
game="$out/games/luanttd"
mkdir -p "$game" "$out/world" "$out/home"
cp game.conf "$game/"
cp -al mods "$game/" 2>/dev/null || cp -a mods "$game/"
cp mods/luanttd_core/init.lua "$out/init.lua"
printf '\n' >>"$out/init.lua"
cat tests/rail_walk_native.lua >>"$out/init.lua"
mv "$out/init.lua" "$game/mods/luanttd_core/init.lua"
printf 'return function() return {local_replay=true} end\n' >"$game/mods/luanttd_core/qa_layout.lua"
printf 'gameid = luanttd\nbackend = sqlite3\nplayer_backend = sqlite3\nauth_backend = sqlite3\nmod_storage_backend = sqlite3\n' >"$out/world/world.mt"
port=${BAYLINE_NATIVE_PORT:-43953} display=${BAYLINE_NATIVE_DISPLAY:-401}
printf 'port = %s\nbind_address = 127.0.0.1\nserver_announce = false\nbayline_generated_map_width = 128\nbayline_generated_map_depth = 128\nbayline_seed = 1751\n' "$port" >"$out/server.conf"
printf 'screen_w = 1440\nscreen_h = 900\nenable_sound = false\nfps_max = 26\nviewing_range = 70\nenable_shaders = false\n' >"$out/client.conf"
if [[ -n ${BAYLINE_NATIVE_TOOLS:-} ]]; then
  t=$(realpath "$BAYLINE_NATIVE_TOOLS")
  export PATH="$t/run/bin:$t/usr/bin:$PATH" LD_LIBRARY_PATH="$t/usr/lib/x86_64-linux-gnu${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
fi
export DISPLAY="127.0.0.1:$display" HOME="$out/home" LIBGL_ALWAYS_SOFTWARE=1 LP_NUM_THREADS=2 MESA_SHADER_CACHE_DISABLE=1 ALSOFT_DRIVERS=null
export XDG_CACHE_HOME="${LUANTTD_NATIVE_MEDIA_CACHE:-$out/cache}" LUANTI_GAME_PATH="$out/games" MINETEST_GAME_PATH="$out/games"
cc -shared -fPIC tests/native_loopback.c -ldl -o "$out/loopback.so"
env LD_PRELOAD="$out/loopback.so" Xvfb ":$display" -screen 0 1440x900x24 -listen tcp -nolisten local -nolisten unix -ac -noreset >"$out/xvfb.log" 2>&1 &
xv=$!; server= client=
trap '[[ -z "$client" ]] || kill "$client" 2>/dev/null || true; [[ -z "$server" ]] || kill "$server" 2>/dev/null || true; kill "$xv" 2>/dev/null || true; wait 2>/dev/null || true' EXIT
for _ in {1..40}; do xdpyinfo >/dev/null 2>&1 && break; sleep .25; done
xdpyinfo >/dev/null 2>&1 || { cat "$out/xvfb.log"; exit 1; }
luantiserver --world "$out/world" --gameid luanttd --config "$out/server.conf" --logfile '' >"$out/server.log" 2>&1 &
server=$!
mark() { for _ in {1..600}; do grep -q "$1" "$out/server.log" && return; kill -0 "$server" 2>/dev/null || break; sleep .25; done; tail -70 "$out/"{server,client}.log; return 1; }
mark 'listening on'
luanti --go --address 127.0.0.1 --port "$port" --name WalkQA --password '' --config "$out/client.conf" --logfile '' >"$out/client.log" 2>&1 &
client=$!
mark RAIL_WALK_READY
win=$(timeout 10 xdotool search --sync --onlyvisible --pid "$client" | tail -1)
xdotool windowfocus --sync "$win"
xdotool mousemove 720 450
sleep 1
say() {
  xdotool key t; sleep .45; xdotool type --delay 30 "$1"; xdotool key Return; sleep .60
}
for pair in flat_along:2.1 flat_across:2.1 grade_along:3.7 grade_across:2.1 diagonal_along:2.25 diagonal_across:2.1 crossing:2.5; do
  case=${pair%:*}
  say "/railwalkqa $case"
  mark "RAIL_WALK_BEGIN $case"
  xdotool keydown e keydown w
  sleep "${pair#*:}"
  xdotool keyup w keyup e
  if [[ $case =~ grade|crossing ]] && command -v import >/dev/null; then
    import -window root -quality 93 "$out/$case.jpg"
  fi
  say "/railwalkqa stop"
  mark "RAIL_WALK_FINISH $case"
done
# Fences are real objects: the avatar should stop against one, then clear
# it with the normal jump instead of walking straight through the mesh.
say "/railwalkqa fence"
mark "RAIL_WALK_BEGIN fence"
xdotool keydown e keydown w
sleep .50
xdotool keyup w keyup e
say "/railwalkqa unchanged_fence"
mark RAIL_WALK_FENCE_STOPS_PLAYER
xdotool keydown e keydown w keydown space
sleep .85
xdotool keyup space keyup w keyup e
say "/railwalkqa stop"
mark "RAIL_WALK_FINISH fence"
! grep -E 'ERROR\[' "$out/server.log" "$out/client.log"
python3 tests/rail_walk_native_evidence.py "$out/server.log"
