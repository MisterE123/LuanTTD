#!/usr/bin/env bash
# Actual worker-generated stock steel layouts in the Linux Luanti client.
set -euo pipefail
cd "$(dirname "$0")/.."
case ${LUANTTD_QA_STEEL_LAYOUT:-1} in 0) seed=1751;; 1) seed=11;; *) exit 2;; esac
fixture=tests/stock_steel_mill_layout_native.lua
marker='PASS NATIVE STOCK STEEL MILL'
if [[ ${LUANTTD_QA_RAIL_GROUND:-0} =~ ^[12]$ ]]; then
  seed=1751
  fixture=tests/stock_rail_ground_native.lua
  marker='PASS NATIVE STOCK RAIL GROUND'
fi
if [[ ${LUANTTD_QA_STOCK_TREES:-0} == 1 ]]; then
  seed=1751
  fixture=tests/stock_tree_lifecycle_native.lua
  marker='PASS NATIVE STOCK TREE LIFE'
fi
if [[ ${LUANTTD_QA_PLANT_TREES:-0} == 1 ]]; then
  seed=1751
  fixture=tests/tree_plant_native.lua
  marker='PASS NATIVE TREE PLANT'
fi
if [[ ${LUANTTD_QA_SHORE_TREES:-0} == 2 ]]; then
  seed=1751
  fixture=tests/tree_shore_flood_native.lua
  marker='PASS NATIVE COAST ROAD TREES'
fi
if [[ ${LUANTTD_QA_SHORE_TREES:-0} == 1 ]]; then
  seed=1751
  fixture=tests/tree_shore_flood_native.lua
  marker='PASS NATIVE SHORE GROVE'
fi
if [[ ${LUANTTD_QA_SPLIT_RAIL:-0} == 1 ]]; then
  seed=1751
  fixture=tests/rail_split_native.lua
  marker='PASS NATIVE SPLIT RAIL'
fi
if [[ ${LUANTTD_QA_WET_RAIL:-0} == 1 ]]; then
  seed=1751
  fixture=tests/rail_wet_native.lua
  marker='PASS NATIVE WET RAIL'
fi
if [[ ${LUANTTD_QA_MULTICOAST_RAIL:-0} == 1 ]]; then
  seed=1751
  fixture=tests/rail_multicoast_native.lua
  marker='PASS NATIVE MULTICORNER RAIL'
fi
if [[ ${LUANTTD_QA_ROADSIDE:-0} == 1 ]]; then
  seed=1751
  fixture=tests/roadside_temperate_native.lua
  marker='PASS NATIVE ROADSIDE'
fi
if [[ ${LUANTTD_QA_OWNED_LAND:-0} == 1 ]]; then
  seed=1751
  fixture=tests/owned_land_native.lua
  marker='PASS NATIVE OWNED LAND'
fi
if [[ ${LUANTTD_QA_TOWN_STATUE:-0} == 1 ]]; then
  seed=1751
  fixture=tests/town_statue_native.lua
  marker='PASS NATIVE TOWN STATUE'
fi
if [[ ${LUANTTD_QA_COMPANY_HQ:-0} == 1 ]]; then
  seed=1751
  fixture=tests/company_hq_native.lua
  marker='PASS NATIVE HQ'
fi
if [[ ${LUANTTD_QA_SPLIT_FENCE:-0} == 1 ]]; then
  seed=1751
  fixture=tests/rail_split_fence_native.lua
  marker='PASS NATIVE SPLIT FENCE'
fi
out=$(mktemp -d "${TMPDIR:-/tmp}/luanttd-native-steel-variant.XXXXXX")
echo "Native mill evidence: $out"
src=$(realpath "${BAYLINE_NATIVE_EXACT_GAME:-.}")
game="$out/games/luanttd"
mkdir -p "$game" "$out/home" "$out/cache" "$out/world"
cp "$src/game.conf" "$game/"
cp -al "$src/mods" "$game/" 2>/dev/null || cp -a "$src/mods" "$game/"
if [[ ${LUANTTD_QA_SHORE_TREES:-0} =~ ^[12]$ || ${LUANTTD_QA_MULTICOAST_RAIL:-0} == 1 ]]; then
  printf 'return function() return {local_replay=true} end\n' >"$game/mods/luanttd_core/qa_layout.lua"
fi
install -m 644 "$src/mods/luanttd_core/init.lua" "$out/init"
cat "$fixture" >>"$out/init"
mv "$out/init" "$game/mods/luanttd_core/init.lua"
port=${BAYLINE_NATIVE_PORT:-41063}
display=${BAYLINE_NATIVE_DISPLAY:-199}
printf 'gameid = luanttd\nbackend = sqlite3\nplayer_backend = sqlite3\nauth_backend = sqlite3\nmod_storage_backend = sqlite3\n' >"$out/world/world.mt"
printf 'port = %s\nbind_address = 127.0.0.1\nserver_announce = false\nbayline_seed = %s\nluanttd_qa_steel_layout = %s\n' \
  "$port" "$seed" "${LUANTTD_QA_STEEL_LAYOUT:-1}" >"$out/server.conf"
if [[ ${LUANTTD_QA_SHORE_TREES:-0} == 2 ]]; then
  printf 'luanttd_coastal_road_trees_qa = true\n' >>"$out/server.conf"
fi
if [[ ${LUANTTD_QA_COMPANY_HQ:-0} == 1 && ${LUANTTD_QA_OBJECT_AUTOSLOPE:-0} == 1 ]]; then
  printf 'luanttd_qa_object_autoslope = true\n' >>"$out/server.conf"
fi
printf 'luanttd_qa_rail_ground = %s\n' "${LUANTTD_QA_RAIL_GROUND:-0}" >>"$out/server.conf"
if [[ ${LUANTTD_QA_ROADSIDE:-0} == 1 ]]; then
  printf 'bayline_generated_map_width = 128\nbayline_generated_map_depth = 128\nbayline_generated_relief = 0\nbayline_generated_coasts = 0\nbayline_generated_towns = 3\n' >>"$out/server.conf"
fi
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
if [[ ${LUANTTD_QA_SHORE_TREES:-0} == 2 ]]; then
  for _ in {1..235}; do grep -q 'NATIVE COAST FOREST BEFORE' "$out/server.log" && break; sleep .25; done
  grep -q 'NATIVE COAST FOREST BEFORE' "$out/server.log"
  sleep 1
  import -window root -quality 91 "$out/coast-road-before.jpg"
  for _ in {1..100}; do grep -q "$marker" "$out/server.log" && break; sleep .25; done
  grep -q "$marker" "$out/server.log"
  sleep .8
  import -window root -quality 91 "$out/coast-road-after.jpg"
fi
if [[ ${LUANTTD_QA_OWNED_LAND:-0} == 1 ]]; then
  wait_land() {
    local pattern=$1
    for _ in {1..280}; do
      grep -q "$pattern" "$out/server.log" && return
      kill -0 "$server" 2>/dev/null || break
      sleep .25
    done
    tail -n 50 "$out/"{server,client}.log; exit 1
  }
  press_native_slot() {
    local slot
    slot=$(sed -n "s/.*$1 //p" "$out/server.log" | tail -1)
    [[ -n "$slot" ]]
    [[ "$slot" != 10 ]] || slot=0
    xdotool key --repeat 3 --delay 140 "$slot"
  }
  wait_land 'NATIVE LAND READY'
  win=$(timeout 10 xdotool search --sync --onlyvisible --pid "$client" | tail -1)
  xdotool windowraise "$win" windowfocus --sync "$win"
  sleep .8
  press_native_slot 'NATIVE LAND HOME'
  sleep .55; xdotool mousedown 1; sleep .30; xdotool mouseup 1
  wait_land 'NATIVE LAND BUY SLOT'
  press_native_slot 'NATIVE LAND BUY SLOT'
  wait_land 'NATIVE LAND SELECTED'
  if command -v import >/dev/null; then sleep .35; import -window root -quality 91 "$out/company-land-preview.jpg"; fi
  sleep .3; xdotool mousedown 1; sleep .4; xdotool mouseup 1
  wait_land 'NATIVE LAND BOUGHT'
  sleep .7
  if command -v import >/dev/null; then import -window root -quality 91 "$out/company-land.jpg"; fi
  press_native_slot 'NATIVE LAND SELL SLOT'
  wait_land 'NATIVE LAND SELL READY'
  sleep .55; xdotool mousedown 1; sleep .30; xdotool mouseup 1
  wait_land "PASS NATIVE OWNED LAND"
  if command -v import >/dev/null; then import -window root -quality 92 "$out/cleared-land.jpg"; fi
fi
if [[ ${LUANTTD_QA_PLANT_TREES:-0} == 1 ]]; then
  for _ in {1..280}; do grep -q 'NATIVE TREE QA READY' "$out/server.log" && break; sleep .25; done
  grep -q 'NATIVE TREE QA READY' "$out/server.log" || { tail -n 50 "$out/"{server,client}.log; exit 1; }
  win=$(timeout 10 xdotool search --sync --onlyvisible --pid "$client" | tail -1)
  xdotool windowraise "$win" windowfocus --sync "$win"
  home=$(sed -n 's/.*NATIVE TREE QA HOME //p' "$out/server.log" | tail -1)
  [[ -n "$home" ]]
  sleep .8
  xdotool key --repeat 3 --delay 140 "$home"; sleep .55
  xdotool mousedown 1; sleep .30; xdotool mouseup 1
  for _ in {1..30}; do grep -q 'NATIVE TREE QA SLOT' "$out/server.log" && break; sleep .15; done
  slot=$(sed -n 's/.*NATIVE TREE QA SLOT //p' "$out/server.log" | tail -1)
  [[ -n "$slot" ]] || { tail -n 50 "$out/server.log"; exit 1; }
  [[ "$slot" != 10 ]] || slot=0
  xdotool key --repeat 3 --delay 140 "$slot"
  for _ in {1..30}; do grep -q 'NATIVE TREE QA SELECTED' "$out/server.log" && break; sleep .15; done
  grep -q 'NATIVE TREE QA SELECTED' "$out/server.log"
  xdotool click 3; sleep .35
  if command -v import >/dev/null; then import -window root -quality 90 "$out/tree-palette.jpg"; fi
  xdotool key Escape
  for _ in {1..32}; do grep -q 'NATIVE TREE QA PALETTE CLOSED' "$out/server.log" && break; sleep .15; done
  grep -q 'NATIVE TREE QA PALETTE CLOSED' "$out/server.log" || { tail -n 60 "$out/"{server,client}.log; exit 1; }
  sleep "${LUANTTD_QA_TREE_WAIT:-.4}"
  xdotool mousedown 1
  for _ in {1..40}; do grep -q 'NATIVE TREE QA DRAG END' "$out/server.log" && break; sleep .15; done
  grep -q 'NATIVE TREE QA DRAG END' "$out/server.log" || { tail -n 60 "$out/"{server,client}.log; exit 1; }
  sleep .40; xdotool mouseup 1
fi
if [[ ${LUANTTD_QA_SHORE_TREES:-0} == 1 ]]; then
  for _ in {1..180}; do grep -q 'NATIVE SHORE GROVE WET' "$out/server.log" && break; sleep .25; done
  grep -q 'NATIVE SHORE GROVE WET' "$out/server.log" || { tail -n 75 "$out/"{server,client}.log; exit 1; }
  sleep .6
  if command -v import >/dev/null; then import -window root -quality 91 "$out/shore-wet.jpg"; fi
fi
if [[ ${LUANTTD_QA_WET_RAIL:-0} == 1 ]]; then
  for _ in {1..240}; do grep -q 'NATIVE WET RAIL BUILT' "$out/server.log" && break; sleep .25; done
  grep -q 'NATIVE WET RAIL BUILT' "$out/server.log" || { tail -n 75 "$out/"{server,client}.log; exit 1; }
  sleep .7
  if command -v import >/dev/null; then import -window root -quality 91 "$out/wet-rail.jpg"; fi
  for _ in {1..240}; do grep -q 'NATIVE WET RAIL TERRAFORM' "$out/server.log" && break; sleep .25; done
  grep -q 'NATIVE WET RAIL TERRAFORM' "$out/server.log" || { tail -n 75 "$out/"{server,client}.log; exit 1; }
  sleep .55
  if command -v import >/dev/null; then import -window root -quality 91 "$out/dried-rail.jpg"; fi
fi
if [[ ${LUANTTD_QA_MULTICOAST_RAIL:-0} == 1 ]]; then
  for _ in {1..240}; do grep -q 'NATIVE MULTICORNER RAIL WET' "$out/server.log" && break; sleep .25; done
  grep -q 'NATIVE MULTICORNER RAIL WET' "$out/server.log" || { tail -n 75 "$out/"{server,client}.log; exit 1; }
  sleep .7
  if command -v import >/dev/null; then import -window root -quality 91 "$out/wet-multicorner.jpg"; fi
fi
if [[ ${LUANTTD_QA_ROADSIDE:-0} == 1 ]]; then
  for _ in {1..240}; do grep -q 'NATIVE ROADSIDE trees READY' "$out/server.log" && break; sleep .25; done
  grep -q 'NATIVE ROADSIDE trees READY' "$out/server.log" || { tail -n 75 "$out/"{server,client}.log; exit 1; }
  sleep 1
  if command -v import >/dev/null; then import -window root -quality 91 "$out/roadside-trees.jpg"; fi
  for _ in {1..240}; do grep -q 'NATIVE ROADSIDE NIGHT READY' "$out/server.log" && break; sleep .25; done
  grep -q 'NATIVE ROADSIDE NIGHT READY' "$out/server.log" || { tail -n 75 "$out/"{server,client}.log; exit 1; }
  sleep 1.65
  if command -v import >/dev/null; then import -window root "$out/roadside-night.png"; fi
fi
if [[ ${LUANTTD_QA_TOWN_STATUE:-0} == 1 ]]; then
  wait_statue() {
    for _ in {1..240}; do
      grep -q "$1" "$out/server.log" && return
      kill -0 "$server" 2>/dev/null || break
      sleep .25
    done
    tail -n 55 "$out/"{server,client}.log; exit 1
  }
  wait_statue 'NATIVE STATUE READY'
  win=$(timeout 10 xdotool search --sync --onlyvisible --pid "$client" | tail -1)
  xdotool windowraise "$win" windowfocus --sync "$win"
  sleep .8
  xdotool mousedown 3; sleep .3; xdotool mouseup 3
  wait_statue 'NATIVE STATUE OFFER'
  sleep 1
  if command -v import >/dev/null; then import -window root -quality 91 "$out/statue-offer.jpg"; fi
  xdotool mousemove 600 519 click 1
fi
if [[ ${LUANTTD_QA_COMPANY_HQ:-0} == 1 ]]; then
  wait_hq() {
    for _ in {1..235}; do
      grep -q "$1" "$out/server.log" && return
      kill -0 "$server" 2>/dev/null || break
      sleep .25
    done
    tail -n 55 "$out/"{server,client}.log; exit 1
  }
  hq_slot() {
    local k
    k=$(sed -n "s/.*$1 //p" "$out/server.log" | tail -1)
    [[ -n "$k" ]]
    [[ "$k" != 10 ]] || k=0
    xdotool key --repeat 3 --delay 140 "$k"
  }
  wait_hq 'NATIVE HQ READY'
  win=$(timeout 10 xdotool search --sync --onlyvisible --pid "$client" | tail -1)
  xdotool windowraise "$win" windowfocus --sync "$win"
  sleep .75; hq_slot 'NATIVE HQ HOME'
  sleep .50; xdotool mousedown 1; sleep .30; xdotool mouseup 1
  wait_hq 'NATIVE HQ SLOT'
  hq_slot 'NATIVE HQ SLOT'
  wait_hq 'NATIVE HQ SELECTED'
  sleep .50; xdotool mousedown 1; sleep .30; xdotool mouseup 1
  wait_hq 'NATIVE HQ BUILT'
  sleep .7
  if command -v import >/dev/null; then import -window root -quality 91 "$out/headquarters-build.jpg"; fi
  if [[ ${LUANTTD_QA_OBJECT_AUTOSLOPE:-0} != 1 ]]; then
    wait_hq 'NATIVE HQ MOVE READY'
    sleep .50; xdotool mousedown 1; sleep .30; xdotool mouseup 1
  fi
fi
if [[ ${LUANTTD_QA_SPLIT_FENCE:-0} == 1 ]]; then
  for ptn in 'NATIVE SPLIT FENCE BARREN' 'NATIVE SPLIT FENCE BORDER'; do
    for _ in {1..255}; do
      grep -q "$ptn" "$out/server.log" && break
      kill -0 "$server" 2>/dev/null || break
      sleep .25
    done
    grep -q "$ptn" "$out/server.log" || { tail -n 60 "$out/"{server,client}.log; exit 1; }
    sleep .6
    if command -v import >/dev/null; then
      import -window root -quality 91 "$out/fence-${ptn##* }.jpg"
    fi
  done
fi
for _ in {1..360}; do grep -q "$marker" "$out/server.log" && break; kill -0 "$server" 2>/dev/null || break; sleep .25; done
grep "$marker" "$out/server.log" || { tail -n 75 "$out/"{server,client}.log; exit 1; }
sleep 4
if [[ ${LUANTTD_QA_COMPANY_HQ:-0} == 1 ]]; then xdotool key 1; sleep .45; fi
if command -v import >/dev/null; then import -window root -quality 91 "$out/steel.jpg"; fi
if grep -E 'ERROR\[|LuanTTD viewport placement:' "$out/"{server,client}.log; then exit 1; fi
