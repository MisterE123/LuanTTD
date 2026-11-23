#!/usr/bin/env bash
# Native graphical rendering of the actual shipped OBJ and atlas under Luanti.
# Inputs match tests/native.sh; isolated world and profile, no existing saves.
set -euo pipefail
cd "$(dirname "$0")/.."
repo=$PWD
if [[ -n ${BAYLINE_NATIVE_TOOLS:-} ]]; then
  tools=$(realpath "$BAYLINE_NATIVE_TOOLS")
  export PATH="$tools/run/bin:$tools/usr/bin:$PATH"
  export LD_LIBRARY_PATH="$tools/usr/lib/x86_64-linux-gnu${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
fi
out=$(mktemp -d "${TMPDIR:-/tmp}/luanttd-rail-art.XXXXXX")
echo "Native diagonal rail evidence: $out"
disp=${BAYLINE_NATIVE_DISPLAY:-126}
port=${BAYLINE_NATIVE_PORT:-39428}
pids=()
cleanup() {
  for pid in "${pids[@]}"; do kill -TERM "$pid" 2>/dev/null || true; done
  wait || true
}
trap cleanup EXIT
preview=${BAYLINE_RAIL_PLACEMENT_PREVIEW:-0}
name=railpreview
if [[ $preview == 1 ]]; then name=luanttd_core; fi
mod="$out/games/rail_art/mods/$name"
mkdir -p "$mod/"{models,textures} "$out/"{world,home,cache}
printf 'title = LuanTTD track art fixture\n' > "$out/games/rail_art/game.conf"
printf 'name = %s\n' "$name" > "$mod/mod.conf"
if [[ $preview == 1 ]]; then
  cp tests/rail_preview_native.lua "$mod/init.lua"
  cp mods/luanttd_core/{rail_diagonal.lua,rail_preview.lua,rail_pose.lua,tile_selector.lua} "$mod/"
  mkdir "$mod/openttd"
  cp mods/luanttd_core/openttd/{rail_track.lua,autorail.lua,slope.lua} "$mod/openttd/"
  for file in "$repo"/mods/luanttd_core/models/{bl_selector_0.obj,bl_rail_track_{1,2,4,5,8}.obj,bl_rail_eased_{4,8}_*}; do ln -s "$file" "$mod/models/"; done
  for file in "$repo"/mods/luanttd_core/textures/bl_selector_*.png; do ln -s "$file" "$mod/textures/"; done
else
  cp tests/rail_diagonal_native.lua "$mod/init.lua"
  cp mods/luanttd_core/{rail_diagonal.lua,openttd/rail_track.lua} "$mod/"
  for file in "$repo"/mods/luanttd_core/models/{bl_rail_track_{1,4,8}.obj,bl_rail_eased_{4,8}_*}; do ln -s "$file" "$mod/models/"; done
fi
for file in "$repo"/mods/luanttd_core/textures/{bl_rail_atlas,bl_grass*}.png; do ln -s "$file" "$mod/textures/"; done
printf 'gameid = rail_art\nbackend = sqlite3\nplayer_backend = sqlite3\nauth_backend = sqlite3\nmod_storage_backend = sqlite3\n' > "$out/world/world.mt"
cat > "$out/server.conf" <<EOF
port = $port
prometheus_listener_address = 127.0.0.1:$port
server_announce = false
bind_address = 127.0.0.1
EOF
cat > "$out/client.conf" <<'EOF'
screen_w = 1300
screen_h = 860
fullscreen = false
enable_sound = false
viewing_range = 80
fps_max = 30
EOF
export HOME="$out/home" XDG_CACHE_HOME="$out/cache" XDG_CONFIG_HOME="$out/home/.config" \
  LUANTI_GAME_PATH="$out/games" MINETEST_GAME_PATH="$out/games" \
  LIBGL_ALWAYS_SOFTWARE=1 ALSOFT_DRIVERS=null MESA_SHADER_CACHE_DISABLE=1
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
luantiserver --world "$out/world" --config "$out/server.conf" --gameid rail_art --logfile "" > "$out/server.log" 2>&1 &
pids+=("$!")
for _ in {1..40}; do if grep -q 'listening' "$out/server.log"; then break; fi; sleep .25; done
grep -q 'listening' "$out/server.log" || { cat "$out/server.log"; exit 1; }
luanti --go --address 127.0.0.1 --port "$port" --config "$out/client.conf" --name RailQA --logfile "" > "$out/client.log" 2>&1 &
client=$!
pids+=("$client")
for _ in {1..120}; do if grep -q RAIL_DIAGONAL_FIXTURE_READY "$out/server.log"; then break; fi; sleep .25; done
grep -q RAIL_DIAGONAL_FIXTURE_READY "$out/server.log" || { cat "$out/"{server,client}.log; exit 1; }
win=$(xdotool search --sync --onlyvisible --pid "$client"|tail -1)
xdotool windowfocus --sync "$win"
sleep 4
xdotool key F2
sleep .5
import -window root "$out/diagonal-before-and-after.jpg"
! grep -Ei 'error|could not load' "$out/client.log"
