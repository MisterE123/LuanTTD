#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
out=$(mktemp -d "${TMPDIR:-/tmp}/luanttd-stock-residential-native.XXXXXX")
echo "Native stock residential evidence: $out"
game="$out/games/luanttd"
mkdir -p "$game" "$out/world" "$out/home" "$out/cache"
src=$(realpath "${BAYLINE_NATIVE_EXACT_GAME:-.}")
cp "$src/game.conf" "$game/"
cp -al "$src/mods" "$game/" 2>/dev/null || cp -a "$src/mods" "$game/"
cp "$src/mods/luanttd_core/init.lua" "$out/init.lua"
mv "$out/init.lua" "$game/mods/luanttd_core/init.lua"
printf '\n' >>"$game/mods/luanttd_core/init.lua"
lift=${LUANTTD_QA_TOWN_LIFT:-0}
rebuild=${LUANTTD_QA_TOWN_REBUILD:-0}
rocky_ferry=${LUANTTD_QA_ROCKY_FERRY:-0}
joined_ferry=${LUANTTD_QA_JOINED_FERRY:-0}
joined_ui=${LUANTTD_QA_JOINED_DOCK_UI:-0}
joined_remove=${LUANTTD_QA_JOINED_ACTIVE_REMOVE:-0}
retired_dock=${LUANTTD_QA_RETIRED_DOCK:-0}
dock_grove=${LUANTTD_QA_DOCK_GROVE:-0}
airport_noise=${LUANTTD_QA_AIRPORT_NOISE:-0}
canal_dikes=${LUANTTD_QA_CANAL_DIKES:-0}
fixture=tests/campaign_worker_stock_residential_native.lua
if [[ $lift == 1 ]]; then fixture=tests/town_lift_native.lua; fi
if [[ $rebuild == 1 ]]; then fixture=tests/town_rebuild_native.lua; fi
if [[ $rocky_ferry == 1 ]]; then fixture=tests/stock_rocky_coast_ferry_native.lua; fi
if [[ $joined_ferry == 1 || $retired_dock == 1 ]]; then fixture=tests/stock_joined_docks_native.lua; fi
if [[ $dock_grove == 1 ]]; then fixture=tests/stock_dock_grove_native.lua; fi
if [[ $airport_noise == 1 ]]; then fixture=tests/airport_noise_native.lua; fi
if [[ $canal_dikes == 1 ]]; then fixture=tests/canal_dikes_native.lua; fi
cat "$fixture" >>"$game/mods/luanttd_core/init.lua"
if [[ $joined_remove == 1 ]]; then
  # Freeze the already-boarded visit at the first real nonzero load.
  # This QA-only copy gives the real client time to commit demolition.
  # It never adds cargo, a boat, facilities, or artificial paid events.
  file="$game/mods/luanttd_core/ship_paid_runtime.lua"
  awk '
    {print}
    /ship.stopped=not ship_ready/ {
      print "        local qa_dock=s.stock_ship_stations[p.last_dock]"
      print "        if p.vehicle.loading and p.last_dock==p.first and (ship.units or 0)>0"
      print "          and qa_dock and qa_dock.docks and #qa_dock.docks==2 then ship.stopped=true end"
    }
  ' "$file" >"$out/qa-ship-paid.lua"
  mv "$out/qa-ship-paid.lua" "$file"
fi

printf 'gameid = luanttd\nbackend = sqlite3\nplayer_backend = sqlite3\nauth_backend = sqlite3\nmod_storage_backend = sqlite3\n' >"$out/world/world.mt"
port=${BAYLINE_NATIVE_PORT:-42683}
display=${BAYLINE_NATIVE_DISPLAY:-393}
cat >"$out/server.conf" <<CONF
port = $port
bind_address = 127.0.0.1
prometheus_listener_address = 127.0.0.1:$port
server_announce = false
bayline_generated_map_width = ${LUANTTD_QA_TOWN_WIDTH:-128}
bayline_generated_map_depth = ${LUANTTD_QA_TOWN_WIDTH:-128}
bayline_generated_relief = 0
bayline_generated_coasts = 0
bayline_generated_towns = 3
bayline_generated_town_layout = original
bayline_seed = ${LUANTTD_QA_TOWN_SEED:-1751}
bayline_stock_bus_start_year = ${LUANTTD_QA_TOWN_YEAR:-1950}
singleplayer_mode = false
luanttd_qa_retired_dock = $([[ $retired_dock == 1 ]] && echo true || echo false)
luanttd_qa_joined_docks_ui = $([[ $joined_ui == 1 ]] && echo true || echo false)
luanttd_qa_joined_active_remove = $([[ $joined_remove == 1 ]] && echo true || echo false)
luanttd_station_noise_level = $([[ $airport_noise == 1 ]] && echo true || echo false)
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
stop_process(){
  local pid=$1
  [[ -n "$pid" ]] || return 0
  kill -TERM "$pid" 2>/dev/null || true
  for _ in {1..50}; do
    if ! kill -0 "$pid" 2>/dev/null; then wait "$pid" 2>/dev/null || true; return; fi
    sleep .10
  done
  kill -KILL "$pid" 2>/dev/null || true
  for _ in {1..20}; do
    if ! kill -0 "$pid" 2>/dev/null; then wait "$pid" 2>/dev/null || true; return; fi
    sleep .10
  done
  return 1
}
cleanup(){ stop_process "$client" || true; stop_process "$server" || true; stop_process "$xv" || true; }
trap cleanup EXIT
trap 'tail -30 "$out/server.log" "$out/client.log" || true; exit 124' TERM INT
for _ in {1..40}; do xdpyinfo >/dev/null 2>&1 && break; sleep .25; done
xdpyinfo > /dev/null || { cat "$out/xvfb.log"; exit 1; }
luantiserver --world "$out/world" --gameid luanttd --config "$out/server.conf" --logfile '' >"$out/server.log" 2>&1 &
server=$!
mark(){ for _ in {1..920}; do grep -q "$1" "$out/server.log" && return; kill -0 "$server" 2>/dev/null || break; sleep .25; done; tail -70 "$out/server.log"; return 1; }
mark 'listening on'
luanti --go --address 127.0.0.1 --port "$port" --name StockResidentialQA --password '' --config "$out/client.conf" --logfile '' >"$out/client.log" 2>&1 &
client=$!
reopen(){
  local setting=$1 finished=$2
  stop_process "$client"; client=
  stop_process "$server"; server=
  mv "$out/server.log" "$out/initial-server.log"
  mv "$out/client.log" "$out/initial-client.log"
  printf '\n%s = true\n' "$setting" >>"$out/server.conf"
  luantiserver --world "$out/world" --gameid luanttd --config "$out/server.conf" --logfile '' >"$out/server.log" 2>&1 &
  server=$!
  mark 'listening on'
  luanti --go --address 127.0.0.1 --port "$port" --name StockResidentialQA --password '' --config "$out/client.conf" --logfile '' >"$out/client.log" 2>&1 &
  client=$!
  mark "$finished"
  grep "$finished" "$out/server.log"
  ! grep -E 'ERROR\[' "$out/server.log" "$out/client.log"
}
if [[ $lift == 1 ]]; then
  mark 'NATIVE TOWN LIFT FRAME'
  sleep .57
  if command -v import >/dev/null; then import -window root -resize 1200x750 -quality 91 "$out/town-lift.jpg"; fi
  mark 'PASS NATIVE TOWN LIFT'
  grep -E 'NATIVE TOWN LIFT FRAME|PASS NATIVE TOWN LIFT' "$out/server.log"
  ! grep -E 'ERROR\[' "$out/server.log" "$out/client.log"
  reopen luanttd_qa_town_lift_restart "PASS NATIVE TOWN LIFT REOPEN"
  exit 0
fi
if [[ $rebuild == 1 ]]; then
  mark 'NATIVE TOWN REBUILD FRAME'
  sleep .55
  if command -v import >/dev/null; then import -window root -resize 1200x750 -quality 91 "$out/town-rebuild.jpg"; fi
  mark 'PASS NATIVE TOWN REBUILD'
  grep -E 'NATIVE TOWN REBUILD (FRAME|RECEIPT)|PASS NATIVE TOWN REBUILD' "$out/server.log"
  ! grep -E 'ERROR\[' "$out/server.log" "$out/client.log"
  reopen luanttd_qa_town_rebuild_restart "PASS NATIVE TOWN REBUILD REOPEN"
  sleep .45
  if command -v import >/dev/null; then import -window root -resize 1200x750 -quality 91 "$out/town-renewed.jpg"; fi
  exit 0
fi
if [[ $dock_grove == 1 ]]; then
  mark 'NATIVE DOCK GROVE BEFORE'
  sleep .26
  if command -v import >/dev/null; then import -window root -resize 1200x750 -quality 93 "$out/dock-before.jpg"; fi
  mark 'PASS NATIVE DOCK GROVE'
  sleep .56
  if command -v import >/dev/null; then import -window root -resize 1200x750 -quality 93 "$out/dock-grove.jpg"; fi
  grep 'PASS NATIVE DOCK GROVE' "$out/server.log"
  ! grep -E 'ERROR\[' "$out/server.log" "$out/client.log"
  reopen luanttd_qa_dock_grove_reopen 'PASS NATIVE DOCK GROVE REOPEN'
  exit 0
fi
if [[ $retired_dock == 1 ]]; then
  mark 'PASS NATIVE RETIRED DOCK SAVE'
  grep 'PASS NATIVE RETIRED DOCK SAVE' "$out/server.log"
  ! grep -E 'ERROR\[' "$out/server.log" "$out/client.log"
  reopen luanttd_qa_retired_dock_reopen 'PASS NATIVE RETIRED DOCK REOPEN'
  exit 0
fi
if [[ $joined_ferry == 1 ]]; then
  if [[ $joined_ui == 1 ]]; then
    mark 'JOINED DOCK HOME SLOT'
    win=$(timeout 10 xdotool search --sync --onlyvisible --pid "$client" | tail -1)
    xdotool windowraise "$win" windowfocus --sync "$win"
    select_dock_slot(){
      local slot
      slot=$(sed -n "s/.*JOINED DOCK $1 SLOT //p" "$out/server.log" | tail -1)
      [[ $slot != 10 ]] || slot=0
      xdotool key "$slot"; sleep .48
      xdotool mousedown 1; sleep .25; xdotool mouseup 1
    }
    select_dock_slot HOME
    mark 'JOINED DOCK TOOL SLOT'
    select_dock_slot TOOL
    mark 'JOINED DOCK PICKER VISIBLE'
    sleep .65
    if command -v import >/dev/null; then import -window root -quality 93 "$out/joined-dock-picker.jpg"; fi
    xdotool mousemove 580 393 click 1; sleep .3
    xdotool mousemove 890 594 click 1; sleep .3
  fi
  mark 'NATIVE JOINED DOCK FRAME'
  sleep .6
  if command -v import >/dev/null; then import -window root -resize 1200x750 -quality 93 "$out/joined-docks.jpg"; fi
  if [[ $joined_remove == 1 ]]; then
    mark 'PASS NATIVE JOINED DOCK ACTIVE REMOVAL'
    if command -v import >/dev/null; then import -window root -resize 1200x750 -quality 93 "$out/removed-pier.jpg"; fi
    ! grep -E 'ERROR\[' "$out/server.log" "$out/client.log"
    reopen luanttd_qa_joined_docks_reopen 'PASS NATIVE JOINED DOCK REOPEN'
    exit 0
  fi
  mark 'PASS NATIVE JOINED DOCK SERVICE'
  grep 'PASS NATIVE JOINED DOCK SERVICE' "$out/server.log"
  ! grep -E 'ERROR\[' "$out/server.log" "$out/client.log"
  reopen luanttd_qa_joined_docks_reopen "PASS NATIVE JOINED DOCK REOPEN"
  exit 0
fi
if [[ $rocky_ferry == 1 ]]; then
  mark 'NATIVE ROCKY FERRY FRAME'
  sleep .45
  if command -v import >/dev/null; then import -window root -resize 1200x750 -quality 91 "$out/rocky-ferry.jpg"; fi
  mark 'PASS NATIVE ROCKY FERRY SERVICE'
  grep 'PASS NATIVE ROCKY FERRY SERVICE' "$out/server.log"
  ! grep -E 'ERROR\[' "$out/server.log" "$out/client.log"
  reopen luanttd_qa_rocky_ferry_reopen "PASS NATIVE ROCKY FERRY REOPEN"
  exit 0
fi
if [[ $airport_noise == 1 ]]; then
  mark 'NATIVE AIRPORT NOISE FRAME'
  sleep .31
  if command -v import >/dev/null; then import -window root -resize 1200x750 -quality 91 "$out/airport-noise.jpg"; fi
  mark 'PASS NATIVE AIRPORT NOISE SERVICE'
  grep 'PASS NATIVE AIRPORT NOISE SERVICE' "$out/server.log"
  ! grep -E 'ERROR\[' "$out/server.log" "$out/client.log"
  reopen luanttd_qa_airport_noise_reopen "PASS NATIVE AIRPORT NOISE REOPEN"
  exit 0
fi
if [[ $canal_dikes == 1 ]]; then
  for view in joined corner bridge-and-buoy depot; do
    mark "NATIVE CANAL DIKES FRAME $view"
    sleep .65
    if command -v import >/dev/null; then import -window root -resize 1200x750 -quality 91 "$out/canal-dike-$view.jpg"; fi
  done
  mark 'PASS NATIVE CANAL DIKES'
  grep -E 'NATIVE CANAL DIKES (LAYERS|FRAME)|PASS NATIVE CANAL DIKES' "$out/server.log"
  ! grep -E 'ERROR\[' "$out/server.log" "$out/client.log"
  reopen luanttd_qa_canal_dikes_reopen "PASS NATIVE CANAL DIKES REOPEN"
  exit 0
fi
for i in {01..13}; do
  mark "STOCK_RESIDENTIAL_VISIBLE_${i}"
  sleep .53
  if command -v import >/dev/null; then import -window root -resize 1200x750 -quality 91 "$out/residential-${i}.jpg"
  elif command -v magick-im7.q16 >/dev/null; then magick-im7.q16 import -window root -resize 1200x750 -quality 91 "$out/residential-${i}.jpg"
  fi
done
mark 'PASS NATIVE WORKER STOCK RESIDENTIAL'
grep -E 'STOCK_RESIDENTIAL_VISIBLE_|PASS NATIVE WORKER STOCK RESIDENTIAL' "$out/server.log"
! grep -E 'ERROR\[' "$out/server.log" "$out/client.log"
