#!/usr/bin/env bash
# Native graphical rendering of the actual bridge OBJ and atlas under Luanti.
# Inputs match tests/native.sh; isolated world and profile, no existing saves.
set -euo pipefail
cd "$(dirname "$0")/.."
repo=$PWD
src=$(realpath "${BAYLINE_NATIVE_EXACT_GAME:-.}")
if [[ -n ${BAYLINE_NATIVE_TOOLS:-} ]]; then
  tools=$(realpath "$BAYLINE_NATIVE_TOOLS")
  export PATH="$tools/run/bin:$tools/usr/bin:$PATH"
  export LD_LIBRARY_PATH="$tools/usr/lib/x86_64-linux-gnu${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
fi
out=$(mktemp -d "${TMPDIR:-/tmp}/luanttd-bridge-pier.XXXXXX")
echo "Native bridge pier evidence: $out"
disp=${BAYLINE_NATIVE_DISPLAY:-119}
port=${BAYLINE_NATIVE_PORT:-39419}
pids=()
cleanup() {
  for pid in "${pids[@]}"; do kill -TERM "$pid" 2>/dev/null || true; done
  wait || true
}
trap cleanup EXIT
game="$out/games/luanttd"
mkdir -p "$game" "$out/"{world,home,cache}
if [[ -n ${BAYLINE_NATIVE_CACHE_SEED:-} && -d $BAYLINE_NATIVE_CACHE_SEED/minetest/media ]]; then
  mkdir -p "$out/cache/minetest"
  cp -al "$BAYLINE_NATIVE_CACHE_SEED/minetest/media" "$out/cache/minetest/"
fi
cp "$src/game.conf" "$game/"
cp -al "$src/mods" "$game/"
# Replace the hard link before adding the disposable fixture.
cp "$src/mods/luanttd_core/init.lua" "$out/init.lua"
mv "$out/init.lua" "$game/mods/luanttd_core/init.lua"
printf '\n' >> "$game/mods/luanttd_core/init.lua"
fixture=bridge_pier_render_native
if [[ ${BAYLINE_NATIVE_BRIDGE_ROAD_CLEAR:-0} == 1 ]]; then fixture=bridge_road_clearance_native; fi
ready_mark=BRIDGE_PIER_RENDER_NATIVE_READY
view_mark=BRIDGE_PIER_VIEW
views=(wood rail water)
if [[ ${LUANTTD_NATIVE_BANK_HEADS:-0} == 1 ]]; then
  fixture=bridge_bank_render_native
  ready_mark=BRIDGE_BANK_NATIVE_READY
  view_mark=BRIDGE_BANK_NATIVE_VIEW
  views=(left_bank right_bank upper modern rail)
fi
if [[ ${LUANTTD_NATIVE_TRAM_GRADE:-0} == 1 ]]; then
  fixture=tram_grade_render_native
  ready_mark=TRAM_GRADE_NATIVE_READY
  view_mark=TRAM_GRADE_NATIVE_VIEW
  views=(tram depot platform overlay)
  if [[ ${LUANTTD_NATIVE_TRAM_FACILITY_REMOVE:-0} == 1 ]]; then
    views+=(tram_facility_modal tram_facility_removed)
  fi
fi
if [[ ${LUANTTD_NATIVE_TRAM_CROSSING:-0} == 1 ]]; then
  fixture=tram_crossing_render_native
  ready_mark=TRAM_CROSSING_NATIVE_READY
  view_mark=TRAM_CROSSING_NATIVE_VIEW
  views=(tram_barred tram_crossing tram_modal tram_remove_rail)
fi
if [[ ${LUANTTD_NATIVE_TRAM_SPAN:-0} == 1 ]]; then
  fixture=tram_span_render_native
  ready_mark=TRAM_SPAN_NATIVE_READY
  view_mark=TRAM_SPAN_NATIVE_VIEW
  views=(tram_bridge tram_tunnel)
fi
cat "tests/$fixture.lua" >> "$game/mods/luanttd_core/init.lua"
# The terrain and companies in this graphics fixture are deliberately
# seeded in the renderer's local world, not in the campaign worker.
printf 'return function() return {local_replay=true} end\n' > "$game/mods/luanttd_core/qa_layout.lua"

printf 'gameid = luanttd\nbackend = sqlite3\nplayer_backend = sqlite3\nauth_backend = sqlite3\nmod_storage_backend = sqlite3\n' > "$out/world/world.mt"
cat > "$out/server.conf" <<EOF
port = $port
prometheus_listener_address = 127.0.0.1:$port
server_announce = false
bind_address = 127.0.0.1
bayline_bridge_road_reference = $([[ ${BAYLINE_NATIVE_BRIDGE_ROAD_REFERENCE:-0} == 1 ]] && echo true || echo false)
luanttd_native_bridge_ground_stop = $([[ ${LUANTTD_NATIVE_BRIDGE_GROUND_STOP:-0} == 1 ]] && echo true || echo false)
EOF
cat > "$out/client.conf" <<'EOF'
screen_w = 1300
screen_h = 860
fullscreen = false
enable_sound = false
viewing_range = 80
fps_max = 30
enable_shaders = true
enable_waving_water = true
water_wave_height = 2.0
enable_dynamic_shadows = true
enable_water_reflections = true
EOF
if [[ ${LUANTTD_NATIVE_BANK_HEADS:-0} == 1 || ${LUANTTD_NATIVE_BRIDGE_GROUND_STOP:-0} == 1 || ${LUANTTD_NATIVE_TRAM_GRADE:-0} == 1 || ${LUANTTD_NATIVE_TRAM_CROSSING:-0} == 1 || ${LUANTTD_NATIVE_TRAM_SPAN:-0} == 1 ]]; then
  # Keep this geometry screenshot readable in software-rendered CI.
  sed -i -e 's/enable_dynamic_shadows = true/enable_dynamic_shadows = false/' \
    -e 's/enable_water_reflections = true/enable_water_reflections = false/' "$out/client.conf"
fi
export HOME="$out/home" XDG_CACHE_HOME="${LUANTTD_NATIVE_MEDIA_CACHE:-$out/cache}" XDG_CONFIG_HOME="$out/home/.config" \
  LUANTI_GAME_PATH="$out/games" MINETEST_GAME_PATH="$out/games" \
  LIBGL_ALWAYS_SOFTWARE=1 ALSOFT_DRIVERS=null
export DISPLAY=":$disp" XAUTHORITY="$out/Xauthority"
opts=(-nolisten tcp)
lib=()
if [[ ${BAYLINE_NATIVE_TCP:-0} == 1 ]]; then
  cc -shared -fPIC "$repo/tests/native_loopback.c" -ldl -o "$out/loopback.so"
  export DISPLAY="127.0.0.1:$disp"
  opts=(-listen tcp -nolisten unix -nolisten local)
  lib=(env "LD_PRELOAD=$out/loopback.so${LD_PRELOAD:+:$LD_PRELOAD}")
fi
touch "$XAUTHORITY"
cookie=$(python3 -c 'import secrets; print(secrets.token_hex(16))')
xauth -f "$XAUTHORITY" add "$DISPLAY" MIT-MAGIC-COOKIE-1 "$cookie"
"${lib[@]}" Xvfb ":$disp" -screen 0 1300x860x24 "${opts[@]}" -auth "$XAUTHORITY" -noreset >"$out/xvfb.log" 2>&1 &
pids+=("$!")
for _ in {1..40}; do if xdpyinfo >/dev/null 2>&1; then break; fi; sleep .25; done
if ! xdpyinfo >/dev/null 2>&1; then cat "$out/xvfb.log"; exit 1; fi
luantiserver --world "$out/world" --config "$out/server.conf" --gameid luanttd --logfile "" > "$out/server.log" 2>&1 &
pids+=("$!")
for _ in {1..40}; do if grep -q 'listening' "$out/server.log"; then break; fi; sleep .25; done
grep -q 'listening' "$out/server.log" || { cat "$out/server.log"; exit 1; }
luanti --go --address 127.0.0.1 --port "$port" --config "$out/client.conf" --name PierQA --logfile "" > "$out/client.log" 2>&1 &
client=$!
pids+=("$client")
for _ in {1..360}; do
  if grep -q "$ready_mark" "$out/server.log" || ! kill -0 "${pids[1]}" 2>/dev/null; then break; fi
  sleep .25
done
grep -q "$ready_mark" "$out/server.log" || { cat "$out/"{server,client}.log; exit 1; }
win=$(xdotool search --sync --onlyvisible --pid "$client"|tail -1)
xdotool windowfocus --sync "$win"
xdotool mousemove 650 430
sleep 3
for view in "${views[@]}"; do
  printf '%s\n' "$view" > "$out/world/pier-view.txt"
  for _ in {1..25}; do grep -q "$view_mark $view" "$out/server.log" && break; sleep .2; done
  grep -q "$view_mark $view" "$out/server.log"
  sleep 2.5
  if [[ "$view" == tram_modal ]]; then
    slot=$(sed -n 's/.*TRAM_CROSSING_NATIVE_SLOT //p' "$out/server.log" | tail -1)
    xdotool key "$slot"; sleep .45; xdotool mousedown 1; sleep .45; xdotool mouseup 1
    for _ in {1..30}; do grep -q TRAM_CROSSING_NATIVE_MODAL "$out/server.log" && break; sleep .2; done
    grep -q TRAM_CROSSING_NATIVE_MODAL "$out/server.log"
    sleep .4
  fi
  if [[ "$view" == tram_facility_modal ]]; then
    slot=$(sed -n 's/.*TRAM_FACILITY_SLOT //p' "$out/server.log" | tail -1)
    xdotool key "$slot"; sleep .45; xdotool mousedown 1; sleep .45; xdotool mouseup 1
    for _ in {1..30}; do grep -q TRAM_FACILITY_MODAL "$out/server.log" && break; sleep .2; done
    grep -q TRAM_FACILITY_MODAL "$out/server.log"
    sleep .4
  fi
  import -window root "$out/$view.png"
  if [[ "$view" == tram_facility_modal ]]; then
    xdotool mousemove 650 421 click 1
    sleep .9
  fi
  if [[ "$view" == tram_modal ]]; then
    xdotool mousemove 650 451 click 1
    sleep .9
  fi
done
! grep -Ei 'ERROR\[|could not load' "$out/client.log" "$out/server.log"
if [[ ${LUANTTD_NATIVE_BANK_HEADS:-0} == 1 ]]; then
  echo "PASS: native timber, girder and rail abutments use the stock shore beneath unchanged decks: $out"
elif [[ ${LUANTTD_NATIVE_TRAM_SPAN:-0} == 1 ]]; then
  echo "PASS: native road bridge and tunnel retain their original mesh under electrified tramway: $out"
elif [[ ${LUANTTD_NATIVE_TRAM_CROSSING:-0} == 1 ]]; then
  echo "PASS: native tram stops at reserved rails and crosses only on release: $out"
elif [[ ${LUANTTD_NATIVE_TRAM_GRADE:-0} == 1 ]]; then
  echo "PASS: native graded terminal foundations, rails, wire and moving tram: $out"
else
  echo "PASS: native submerged timber road and rail footings, dry slopes and animated ocean preserved: $out"
fi
rm -rf -- "$out/games" "$out/cache"
