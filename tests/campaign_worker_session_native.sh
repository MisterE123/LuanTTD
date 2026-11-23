#!/usr/bin/env bash
# Start the actual server integration path in a disposable game. Connect
# a real graphical player, use WASD, and restart against its checkpoint.
set -euo pipefail
cd "$(dirname "$0")/.."
out=$(mktemp -d "${TMPDIR:-/tmp}/luanttd-owner-session.XXXXXX")
echo "$out"
game="$out/games/luanttd"
mkdir -p "$game" "$out/world" "$out/home" "$out/cache"
cp game.conf "$game/"
cp -al mods "$game/"
cp mods/luanttd_core/init.lua "$out/init.lua"
mv "$out/init.lua" "$game/mods/luanttd_core/init.lua"
cat tests/campaign_worker_session_probe.lua >> "$game/mods/luanttd_core/init.lua"
printf 'gameid = luanttd\nbackend = sqlite3\nplayer_backend = sqlite3\nauth_backend = sqlite3\nmod_storage_backend = sqlite3\n' >"$out/world/world.mt"
port=${BAYLINE_NATIVE_PORT:-40024}
display=${BAYLINE_NATIVE_DISPLAY:-199}
cat >"$out/server.conf" <<CONF
port = $port
bind_address = 127.0.0.1
server_announce = false
bayline_generated_map_width = 64
bayline_generated_map_depth = 64
bayline_generated_relief = 0
bayline_generated_coasts = 0
singleplayer_mode = false
CONF
cat >"$out/client.conf" <<'CONF'
screen_w = 1440
screen_h = 900
fullscreen = false
enable_sound = false
gui_scaling = 1.0
CONF
if [[ -n ${BAYLINE_NATIVE_TOOLS:-} ]]; then
  t=$(realpath "$BAYLINE_NATIVE_TOOLS")
  export PATH="$t/run/bin:$t/usr/bin:$PATH" LD_LIBRARY_PATH="$t/usr/lib/x86_64-linux-gnu${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
fi
export DISPLAY="127.0.0.1:$display" HOME="$out/home" LIBGL_ALWAYS_SOFTWARE=1 MESA_SHADER_CACHE_DISABLE=1
export XDG_CACHE_HOME="${LUANTTD_NATIVE_MEDIA_CACHE:-$out/cache}"
export LUANTI_GAME_PATH="$out/games" MINETEST_GAME_PATH="$out/games"
cc -shared -fPIC tests/native_loopback.c -ldl -o "$out/loopback.so"
env LD_PRELOAD="$out/loopback.so" Xvfb ":$display" -screen 0 1440x900x24 -listen tcp -nolisten local -nolisten unix -ac -noreset >"$out/xvfb.log" 2>&1 &
xv=$!; server="" client=""
trap 'if [[ -n "$client" ]]; then kill "$client" 2>/dev/null || true;fi; if [[ -n "$server" ]]; then kill "$server" 2>/dev/null || true;fi;kill "$xv" 2>/dev/null || true;wait 2>/dev/null || true' EXIT
for _ in {1..40}; do xdpyinfo >/dev/null 2>&1 && break; sleep .25; done
mark(){ for _ in {1..160}; do grep -q "$1" "$log" && return; kill -0 "$server" 2>/dev/null || break; sleep .25; done; tail -70 "$log"; return 1; }
for part in 1 2; do
  log="$out/server-$part.log"
  luantiserver --world "$out/world" --gameid luanttd --config "$out/server.conf" --logfile '' >"$log" 2>&1 &
  server=$!
  mark 'listening on'
  luanti --go --address 127.0.0.1 --port "$port" --name SessionWorker --password '' --config "$out/client.conf" --logfile '' >"$out/client-$part.log" 2>&1 &
  client=$!
  if [[ $part == 1 ]]; then
    mark 'NATIVE OWNER SESSION CLIENT READY'
    win=$(xdotool search --sync --limit 1 --onlyvisible --pid "$client" | tail -1)
    xdotool windowfocus --sync "$win"
    sleep 1.2
    import -window root -resize 960x600 -quality 88 "$out/admitted.jpg"
    xdotool keydown d; sleep 2.8; xdotool keyup d
    if ! grep -q 'NATIVE OWNER SESSION INPUT' "$log"; then
      xdotool windowfocus --sync "$win"; xdotool keydown w; sleep 2; xdotool keyup w
    fi
  fi
  mark 'PASS NATIVE OWNER SESSION'
  grep 'PASS NATIVE OWNER SESSION' "$log"
  ! grep -E 'ERROR\[' "$log"
  wait "$server"; server=""
  kill "$client" 2>/dev/null || true
  wait "$client" 2>/dev/null || true
  client=""
done
