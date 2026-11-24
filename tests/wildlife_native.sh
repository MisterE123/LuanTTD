#!/usr/bin/env bash
# Native render and observer regression in a small disposable map.
set -euo pipefail
cd "$(dirname "$0")/.."
out=$(mktemp -d "${TMPDIR:-/tmp}/luanttd-wildlife.XXXXXX")
echo "Wildlife native evidence: $out"
game="$out/games/wildqa"; mod="$game/mods/luanttd_core"
mkdir -p "$mod/"{models,textures} "$out/"{home,world,cache}
printf 'title = LuanTTD Wildlife QA\n' > "$game/game.conf"
printf 'name = luanttd_core\n' > "$mod/mod.conf"
cp tests/wildlife_native.lua "$mod/init.lua"
cp mods/luanttd_core/{ambient_wildlife,ambient_audience}.lua "$mod/"
cp -l mods/luanttd_core/models/bl_wildlife_*.obj "$mod/models/" 2>/dev/null ||
  cp mods/luanttd_core/models/bl_wildlife_*.obj "$mod/models/"
cp mods/luanttd_core/textures/{bl_wildlife_atlas,bl_grass1,bl_grass3,bl_water0,bl_fountain_droplet}.png "$mod/textures/"
printf 'gameid = wildqa\nbackend = sqlite3\nplayer_backend = sqlite3\nauth_backend = sqlite3\nmod_storage_backend = sqlite3\n' > "$out/world/world.mt"
display=${BAYLINE_NATIVE_DISPLAY:-246}
port=${BAYLINE_NATIVE_PORT:-40066}
printf 'port = %s\nprometheus_listener_address = 127.0.0.1:%s\nserver_announce = false\nbind_address = 127.0.0.1\n' "$port" "$port" > "$out/server.conf"
printf 'screen_w = 1100\nscreen_h = 740\nenable_sound = false\nviewing_range = 100\nfps_max = 28\n' > "$out/client.conf"
export HOME="$out/home" XDG_CACHE_HOME="$out/cache" LUANTI_GAME_PATH="$out/games" MINETEST_GAME_PATH="$out/games"
export DISPLAY="127.0.0.1:$display" LIBGL_ALWAYS_SOFTWARE=1 MESA_SHADER_CACHE_DISABLE=1 LP_NUM_THREADS=1
cc -shared -fPIC tests/native_loopback.c -ldl -o "$out/loopback.so"
env LD_PRELOAD="$out/loopback.so" Xvfb ":$display" -screen 0 1100x740x24 -listen tcp -nolisten local -nolisten unix -ac -noreset >"$out/xvfb.log" 2>&1 &
xv=$!; server=; client=
trap 'for pid in "$client" "$server" "$xv"; do [[ -z "$pid" ]] || kill "$pid" 2>/dev/null || true; done; wait 2>/dev/null || true' EXIT
for _ in {1..40}; do xdpyinfo >/dev/null 2>&1 && break; sleep .25; done
xdpyinfo >/dev/null
luantiserver --world "$out/world" --config "$out/server.conf" --gameid wildqa --logfile "" >"$out/server.log" 2>&1 &
server=$!
for _ in {1..50}; do grep -q 'listening' "$out/server.log" && break; sleep .20; done
grep -q 'listening' "$out/server.log"
luanti --go --address 127.0.0.1 --port "$port" --name WildlifeQA --password '' --config "$out/client.conf" --logfile "" >"$out/client.log" 2>&1 &
client=$!
for animal in whale porpoise seagull eagle fox; do
  for _ in {1..180}; do
    grep -q "WILDLIFE_NATIVE_FRAME $animal" "$out/server.log" && break
    kill -0 "$server" 2>/dev/null || break
    sleep .22
  done
  grep "WILDLIFE_NATIVE_FRAME $animal" "$out/server.log" || { cat "$out/server.log"; exit 1; }
  sleep 1.75
  import -window root "$out/$animal.png"
done
for _ in {1..40}; do grep -q WILDLIFE_NATIVE_PASS "$out/server.log" && break; sleep .22; done
grep WILDLIFE_NATIVE_PASS "$out/server.log"
grep WILDLIFE_NATIVE_VIEW_PASS "$out/server.log"
! grep -E 'ERROR\[' "$out/"{server,client}.log
if grep -Eq 'Model bl_wildlife_.* is missing [0-9]+ more texture' "$out/client.log"; then
  echo "Wildlife unexpectedly allocated extra material sections" >&2; exit 1
fi
