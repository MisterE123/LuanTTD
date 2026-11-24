#!/usr/bin/env bash
# Actual worker-generated stock steel layouts in the Linux Luanti client.
set -euo pipefail
cd "$(dirname "$0")/.."
case ${LUANTTD_QA_STEEL_LAYOUT:-1} in 0) seed=11;; 1) seed=1751;; *) exit 2;; esac
fixture=tests/stock_steel_mill_layout_native.lua
marker='PASS NATIVE STOCK STEEL MILL'
if [[ ${LUANTTD_QA_RAIL_GROUND:-0} =~ ^[12]$ ]]; then
  fixture=tests/stock_rail_ground_native.lua
  marker='PASS NATIVE STOCK RAIL GROUND'
fi
out=$(mktemp -d "${TMPDIR:-/tmp}/luanttd-native-steel-variant.XXXXXX")
echo "Native mill evidence: $out"
src=$(realpath "${BAYLINE_NATIVE_EXACT_GAME:-.}")
game="$out/games/luanttd"
mkdir -p "$game" "$out/home" "$out/cache" "$out/world"
cp "$src/game.conf" "$game/"
cp -al "$src/mods" "$game/" 2>/dev/null || cp -a "$src/mods" "$game/"
install -m 644 "$src/mods/luanttd_core/init.lua" "$out/init"
cat "$fixture" >>"$out/init"
mv "$out/init" "$game/mods/luanttd_core/init.lua"
port=${BAYLINE_NATIVE_PORT:-41063}
display=${BAYLINE_NATIVE_DISPLAY:-199}
printf 'gameid = luanttd\nbackend = sqlite3\nplayer_backend = sqlite3\nauth_backend = sqlite3\nmod_storage_backend = sqlite3\n' >"$out/world/world.mt"
printf 'port = %s\nbind_address = 127.0.0.1\nserver_announce = false\nbayline_seed = %s\nluanttd_qa_steel_layout = %s\n' \
  "$port" "$seed" "${LUANTTD_QA_STEEL_LAYOUT:-1}" >"$out/server.conf"
printf 'luanttd_qa_rail_ground = %s\n' "${LUANTTD_QA_RAIL_GROUND:-0}" >>"$out/server.conf"
printf 'screen_w = 1200\nscreen_h = 760\nenable_sound = false\nfps_max = 26\nviewing_range = 63\nenable_shaders = false\n' >"$out/client.conf"
export DISPLAY="127.0.0.1:$display" HOME="$out/home" LIBGL_ALWAYS_SOFTWARE=1 LP_NUM_THREADS=2
export XDG_CACHE_HOME="${LUANTTD_NATIVE_MEDIA_CACHE:-$out/cache}" LUANTI_GAME_PATH="$out/games" MINETEST_GAME_PATH="$out/games"
cc -shared -fPIC tests/native_loopback.c -ldl -o "$out/loopback.so"
env LD_PRELOAD="$out/loopback.so" Xvfb ":$display" -screen 0 1200x760x24 -listen tcp -nolisten local -nolisten unix -ac -noreset >"$out/xvfb.log" 2>&1 &
xv=$!; server= client=
trap '[[ -z "$client" ]] || kill "$client" 2>/dev/null || true; [[ -z "$server" ]] || kill "$server" 2>/dev/null || true; kill "$xv" 2>/dev/null || true; wait 2>/dev/null || true' EXIT
for _ in {1..40}; do xdpyinfo >/dev/null 2>&1 && break; sleep .25; done
xdpyinfo >/dev/null 2>&1 || { cat "$out/xvfb.log"; exit 1; }
luantiserver --world "$out/world" --gameid luanttd --config "$out/server.conf" --logfile '' >"$out/server.log" 2>&1 &
server=$!
for _ in {1..180}; do grep -q 'listening on' "$out/server.log" && break; sleep .25; done
grep -q 'listening on' "$out/server.log" || { cat "$out/server.log"; exit 1; }
luanti --go --address 127.0.0.1 --port "$port" --name SteelReview --password '' --config "$out/client.conf" --logfile '' >"$out/client.log" 2>&1 &
client=$!
for _ in {1..360}; do grep -q "$marker" "$out/server.log" && break; kill -0 "$server" 2>/dev/null || break; sleep .25; done
grep "$marker" "$out/server.log" || { tail -75 "$out/"{server,client}.log; exit 1; }
sleep 4
if command -v import >/dev/null; then import -window root -quality 91 "$out/steel.jpg"; fi
if grep -E 'ERROR\[|LuanTTD viewport placement:' "$out/"{server,client}.log; then exit 1; fi
