#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
out=$(mktemp -d "${TMPDIR:-/tmp}/luanttd-lighthouse-beam-native.XXXXXX")
echo "Native lighthouse beam evidence: $out"
game="$out/games/luanttd"
mkdir -p "$game" "$out/world" "$out/home" "$out/cache"
cp game.conf "$game/"
cp -al mods "$game/" 2>/dev/null || cp -a mods/. "$game/mods/"
cp mods/luanttd_core/init.lua "$out/init.lua"
mv "$out/init.lua" "$game/mods/luanttd_core/init.lua"
printf '\n' >>"$game/mods/luanttd_core/init.lua"
cat tests/campaign_worker_lighthouse_beam_native.lua >>"$game/mods/luanttd_core/init.lua"
printf 'gameid = luanttd\nbackend = sqlite3\nplayer_backend = sqlite3\nauth_backend = sqlite3\nmod_storage_backend = sqlite3\n' >"$out/world/world.mt"
port=${BAYLINE_NATIVE_PORT:-42658}
display=${BAYLINE_NATIVE_DISPLAY:-389}
cat >"$out/server.conf" <<CONF
port = $port
bind_address = 127.0.0.1
prometheus_listener_address = 127.0.0.1:$port
server_announce = false
bayline_generated_map_width = 128
bayline_generated_map_depth = 128
bayline_generated_relief = 0
bayline_generated_coasts = 15
bayline_generated_sea = 1
time_speed = 0
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
export DISPLAY="127.0.0.1:$display" HOME="$out/home" LIBGL_ALWAYS_SOFTWARE=1 MESA_SHADER_CACHE_DISABLE=1
export XDG_CACHE_HOME="${LUANTTD_NATIVE_MEDIA_CACHE:-$out/cache}" LUANTI_GAME_PATH="$out/games" MINETEST_GAME_PATH="$out/games"
cc -shared -fPIC tests/native_loopback.c -ldl -o "$out/loopback.so"
env LD_PRELOAD="$out/loopback.so" Xvfb ":$display" -screen 0 1440x900x24 -listen tcp -nolisten local -nolisten unix -ac -noreset >"$out/xvfb.log" 2>&1 &
xv=$!; server= client=
trap '[[ -z "$client" ]] || kill "$client" 2>/dev/null || true; [[ -z "$server" ]] || kill "$server" 2>/dev/null || true; kill "$xv" 2>/dev/null || true;wait 2>/dev/null || true' EXIT
for _ in {1..40}; do xdpyinfo >/dev/null 2>&1 && break; sleep .25; done
xdpyinfo > /dev/null || { cat "$out/xvfb.log"; exit 1; }
luantiserver --world "$out/world" --gameid luanttd --config "$out/server.conf" --logfile '' >"$out/server.log" 2>&1 &
server=$!
mark(){ for _ in {1..360}; do grep -q "$1" "$out/server.log" && return; kill -0 "$server" 2>/dev/null || break; sleep .25; done; tail -70 "$out/server.log"; return 1; }
mark 'listening on'
luanti --go --address 127.0.0.1 --port "$port" --name LighthouseBeamQA --password '' --config "$out/client.conf" --logfile '' >"$out/client.log" 2>&1 &
client=$!
shot() {
  if command -v import >/dev/null; then import -window root -resize 1200x750 -quality 94 "$out/$1.jpg"
  elif command -v magick-im7.q16 >/dev/null; then magick-im7.q16 import -window root -resize 1200x750 -quality 94 "$out/$1.jpg"
  fi
}
mark 'LIGHTHOUSE_BEAM_DAY'
sleep .55;shot lighthouse-day
mark 'LIGHTHOUSE_BEAM_NIGHT'
sleep .55;shot lighthouse-night-a
sleep 2.1;shot lighthouse-night-b
mark 'PASS NATIVE LIGHTHOUSE BEAM'
grep -E 'LIGHTHOUSE_BEAM_(DAY|NIGHT)|PASS NATIVE LIGHTHOUSE BEAM' "$out/server.log"
! grep -E 'ERROR\[' "$out/server.log" "$out/client.log"
