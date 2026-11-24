#!/usr/bin/env bash
# Real stock Luanti camera views for the same generated coastline.
# Set BAYLINE_NATIVE_COAST_REFERENCE=1 with the reference application for A/B.
# BAYLINE_NATIVE_ROCKY_WATER=1 checks rocky shore, sea rocks and a stock rapid.
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ -n ${BAYLINE_NATIVE_TOOLS:-} ]]; then
  tools=$(realpath "$BAYLINE_NATIVE_TOOLS")
  export PATH="$tools/run/bin:$tools/usr/bin:$PATH" LD_LIBRARY_PATH="$tools/usr/lib/x86_64-linux-gnu${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
fi
src=$(realpath "${BAYLINE_NATIVE_EXACT_GAME:-.}")
out=$(mktemp -d "${TMPDIR:-/tmp}/luanttd-coastal-sheet.XXXXXX")
echo "Coastal sheet evidence: $out"
game="$out/games/luanttd"
mkdir -p "$game" "$out/home" "$out/cache" "$out/world"
cp "$src/game.conf" "$game/"
cp -al "$src/mods" "$game/"
if [[ -n ${BAYLINE_NATIVE_CACHE_SEED:-} && -d $BAYLINE_NATIVE_CACHE_SEED/minetest/media ]]; then
  mkdir -p "$out/cache/minetest"
  cp -al "$BAYLINE_NATIVE_CACHE_SEED/minetest/media" "$out/cache/minetest/"
fi
probe=coastal_sheet_native
views=(overview near open)
if [[ ${BAYLINE_NATIVE_ROCKY_WATER:-0} == 1 ]]; then
  probe=rocky_water_native
  views=(rocky-shore open-rocks rapids)
  # Only this disposable fixture edits two local tile records.
  printf 'return function() return {local_replay=true} end\n' >"$game/mods/luanttd_core/qa_layout.lua"
fi
cp "tests/$probe.lua" "$game/mods/luanttd_core/"
cat "$src/mods/luanttd_core/init.lua" >"$out/init.lua"
printf '\ndofile(mod.."/%s.lua")(api)\n' "$probe" >>"$out/init.lua"
mv "$out/init.lua" "$game/mods/luanttd_core/init.lua"
export HOME="$out/home" XDG_CACHE_HOME="${LUANTTD_NATIVE_MEDIA_CACHE:-$out/cache}" LUANTI_GAME_PATH="$out/games" MINETEST_GAME_PATH="$out/games"
export LIBGL_ALWAYS_SOFTWARE=1 ALSOFT_DRIVERS=null
port=${BAYLINE_NATIVE_PORT:-42820}
display=${BAYLINE_NATIVE_DISPLAY:-120}
export DISPLAY=":$display" XAUTHORITY="$out/Xauthority"
pids=()
cleanup() { for i in "${pids[@]}"; do kill -TERM "$i" 2>/dev/null || true; done; wait || true; }
trap cleanup EXIT
printf 'gameid = luanttd\nbackend = sqlite3\nplayer_backend = sqlite3\nauth_backend = sqlite3\nmod_storage_backend = sqlite3\n' >"$out/world/world.mt"
cat >"$out/native.conf" <<GAME
port = $port
server_announce = false
bind_address = 127.0.0.1
time_speed = 0
bayline_coastal_sheet_reference = $([[ ${BAYLINE_NATIVE_COAST_REFERENCE:-0} == 1 ]] && echo true || echo false)
GAME
if [[ $probe == rocky_water_native ]]; then
  printf 'bayline_generated_rivers = 3\nbayline_generated_min_river_length = 2\n' >> "$out/native.conf"
fi
cat >"$out/client.conf" <<'GAME'
screen_w = 1100
screen_h = 740
fullscreen = false
enable_sound = false
viewing_range = 100
fps_max = 30
enable_shaders = true
enable_waving_water = true
water_wave_height = 1.0
water_wave_length = 20.0
enable_dynamic_shadows = true
shadow_map_quality = 1
enable_water_reflections = true
GAME
opts=(-nolisten tcp)
lib=()
if [[ ${BAYLINE_NATIVE_TCP:-0} == 1 ]]; then
  cc -shared -fPIC tests/native_loopback.c -ldl -o "$out/loopback.so"
  export DISPLAY="127.0.0.1:$display"
  opts=(-listen tcp -nolisten unix -nolisten local)
  lib=(env "LD_PRELOAD=$out/loopback.so${LD_PRELOAD:+:$LD_PRELOAD}")
fi
touch "$XAUTHORITY"
xauth -f "$XAUTHORITY" add "$DISPLAY" MIT-MAGIC-COOKIE-1 "$(python3 -c 'import secrets; print(secrets.token_hex(16))')"
"${lib[@]}" Xvfb ":$display" -screen 0 1100x740x24 "${opts[@]}" -auth "$XAUTHORITY" -noreset >"$out/xvfb.log" 2>&1 &
pids+=("$!")
for _ in {1..60}; do xdpyinfo >/dev/null 2>&1 && break; sleep .2; done
xdpyinfo >/dev/null 2>&1 || { cat "$out/xvfb.log"; exit 1; }
luantiserver --world "$out/world" --config "$out/native.conf" --gameid luanttd --logfile "" >"$out/server.log" 2>&1 &
pids+=("$!")
for _ in {1..80}; do grep -q 'listening' "$out/server.log" && break; sleep .2; done
grep -q 'listening' "$out/server.log" || { cat "$out/server.log"; exit 1; }
luanti --go --address 127.0.0.1 --port "$port" --config "$out/client.conf" --name ShoreQA --logfile "" >"$out/client.log" 2>&1 &
pids+=("$!")
for _ in {1..300}; do
  grep -q COAST_SHEET_READY "$out/server.log" && break
  if ! kill -0 "${pids[1]}" 2>/dev/null; then cat "$out/server.log"; exit 1; fi
  sleep .25
done
grep COAST_SHEET_READY "$out/server.log" || { cat "$out/"{server,client}.log; exit 1; }
win=$(xdotool search --sync --onlyvisible --pid "${pids[2]}" | tail -1)
xdotool windowfocus --sync "$win"
xdotool mousemove 550 370
for v in "${views[@]}"; do
  printf '%s\n' "$v" > "$out/world/coastal-view.txt"
  for _ in {1..30}; do grep -q "COAST_SHEET_VIEW $v" "$out/server.log" && break; sleep .2; done
  grep -q "COAST_SHEET_VIEW $v" "$out/server.log" || { cat "$out/server.log"; exit 1; }
  sleep 3
  import -window root "$out/$v.png"
  sleep 1.4
  import -window root "$out/$v-next.png"
done
! grep -Ei 'error|could not load' "$out/client.log"
