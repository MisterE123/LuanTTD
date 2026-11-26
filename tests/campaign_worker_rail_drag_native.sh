#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
out=$(mktemp -d "${TMPDIR:-/tmp}/luanttd-rail-drag-native.XXXXXX")
echo "Native paid AutoRail evidence: $out"
game="$out/games/luanttd"
mkdir -p "$game" "$out/world" "$out/home" "$out/cache"
cp game.conf "$game/"
cp -al mods "$game/" 2>/dev/null || cp -a mods/. "$game/mods/"
cp mods/luanttd_core/init.lua "$out/init.lua"
mv "$out/init.lua" "$game/mods/luanttd_core/init.lua"
printf '\n' >>"$game/mods/luanttd_core/init.lua"
cat tests/campaign_worker_rail_drag_native.lua >>"$game/mods/luanttd_core/init.lua"
printf 'gameid = luanttd\nbackend = sqlite3\nplayer_backend = sqlite3\nauth_backend = sqlite3\nmod_storage_backend = sqlite3\n' >"$out/world/world.mt"
port=${BAYLINE_NATIVE_PORT:-42671}
display=${BAYLINE_NATIVE_DISPLAY:-429}
cat >"$out/server.conf" <<CONF
port = $port
bind_address = 127.0.0.1
prometheus_listener_address = 127.0.0.1:$port
server_announce = false
bayline_generated_map_width = 128
bayline_generated_map_depth = 128
bayline_generated_relief = 0
bayline_generated_coasts = 0
bayline_generated_towns = 3
bayline_generated_town_layout = grid2
bayline_seed = 1751
singleplayer_mode = false
CONF
printf 'screen_w = 1440\nscreen_h = 900\nenable_sound = false\n' >"$out/client.conf"
if [[ -n ${BAYLINE_NATIVE_TOOLS:-} ]]; then
  t=$(realpath "$BAYLINE_NATIVE_TOOLS")
  export PATH="$t/run/bin:$t/usr/bin:$PATH" LD_LIBRARY_PATH="$t/usr/lib/x86_64-linux-gnu${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
fi
export DISPLAY="127.0.0.1:$display" HOME="$out/home" LIBGL_ALWAYS_SOFTWARE=1 MESA_SHADER_CACHE_DISABLE=1 ALSOFT_DRIVERS=null
export XDG_CACHE_HOME="${LUANTTD_NATIVE_MEDIA_CACHE:-$out/cache}" LUANTI_GAME_PATH="$out/games" MINETEST_GAME_PATH="$out/games"
cc -shared -fPIC tests/native_loopback.c -ldl -o "$out/loopback.so"
env LD_PRELOAD="$out/loopback.so" Xvfb ":$display" -screen 0 1440x900x24 -listen tcp -nolisten local -nolisten unix -ac -noreset >"$out/xvfb.log" 2>&1 &
xv=$!; server= client=
trap '[[ -z "$client" ]] || kill "$client" 2>/dev/null || true; [[ -z "$server" ]] || kill "$server" 2>/dev/null || true; kill "$xv" 2>/dev/null || true;wait 2>/dev/null || true' EXIT
for _ in {1..40}; do xdpyinfo >/dev/null 2>&1 && break; sleep .25; done
xdpyinfo > /dev/null || { cat "$out/xvfb.log"; exit 1; }
mark() {
  for _ in {1..300}; do
    grep -q "$1" "$out/$phase-server.log" && return
    kill -0 "$server" 2>/dev/null || break
    sleep .25
  done
  tail -90 "$out/$phase-server.log"
  return 1
}
for phase in new reopen; do
  luantiserver --world "$out/world" --gameid luanttd --config "$out/server.conf" --logfile '' >"$out/$phase-server.log" 2>&1 &
  server=$!
  mark 'listening on'
  luanti --go --address 127.0.0.1 --port "$port" --name RailDragQA --password '' --config "$out/client.conf" --logfile '' >"$out/$phase-client.log" 2>&1 &
  client=$!
  if [[ $phase == new ]]; then
    mark 'NATIVE AUTORAIL READY'
    win=$(xdotool search --sync --onlyvisible --pid "$client" | tail -n 1)
    xdotool windowfocus --sync "$win"
    slot=$(sed -n 's/.*NATIVE AUTORAIL READY //p' "$out/$phase-server.log" | tail -n1)
    xdotool key --repeat 3 --delay 140 "$slot"
    sleep .65
    xdotool mousedown 1
    sleep .33
    xdotool keydown e; sleep .33; xdotool keyup e
    mark 'NATIVE AUTORAIL PAID PREVIEW'
    sleep .6
    import -window root "$out/autorail-authoritative-preview.jpg"
    xdotool mouseup 1
    mark 'PASS NATIVE AUTORAIL DRAG'
  else
    mark 'PASS NATIVE AUTORAIL REOPEN'
  fi
  grep 'PASS NATIVE AUTORAIL' "$out/$phase-server.log"
  ! grep -E 'ERROR\[' "$out/$phase-server.log" "$out/$phase-client.log"
  kill -TERM "$client" "$server" 2>/dev/null || true
  wait "$client" "$server" 2>/dev/null || true
  client= server=
done
