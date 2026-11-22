#!/usr/bin/env bash
# Private visual test of the actual alternate mode, not the normal campaign.
set -euo pipefail
cd "$(dirname "$0")/.."
repo=$PWD
if [[ $# -ne 2 ]]; then
  echo "usage: $0 /private/ogfxi_logos.grf /private/new-evidence-directory" >&2
  exit 64
fi
grf=$(realpath "$1")
out=$(realpath -m "$2")
if [[ -n ${BAYLINE_NATIVE_TOOLS:-} ]]; then
  tools=$(realpath "$BAYLINE_NATIVE_TOOLS")
  export PATH="$tools/run/bin:$tools/usr/bin:$PATH"
  export LD_LIBRARY_PATH="$tools/usr/lib/x86_64-linux-gnu${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
fi
client=${BAYLINE_LUANTI_CLIENT:-luanti}
server=${BAYLINE_LUANTI_SERVER:-luantiserver}
for dep in "$client" "$server" Xvfb xdotool xauth xdpyinfo import; do
  command -v "$dep" >/dev/null || { echo "Missing dependency: $dep" >&2; exit 1; }
done
mkdir "$out"
mod="$out/games/luanttd/mods/luanttd_core"
mkdir -p "$mod/"{models,textures,openttd} "$out/"{world,home,cache}
cp game.conf "$out/games/luanttd/"
cp mods/luanttd_core/mod.conf "$mod/"
cp mods/luanttd_core/{original_terrain_explorer,original_terrain_stream,terrain_stream,terrain_word,world_storage}.lua "$mod/"
cp mods/luanttd_core/openttd/{original_terrain,slope}.lua "$mod/openttd/"
cp mods/luanttd_core/models/{bl_land_*,bl_original_coast_*}.obj "$mod/models/"
cp mods/luanttd_core/textures/{bl_grass*,bl_original_coast_*}.png "$mod/textures/"
cp tests/original_terrain_explorer_probe.lua "$mod/init.lua"
python3 tools/extract_original_terrain_masks.py "$grf" "$out/world/original-mapgen.bin"
printf 'gameid = luanttd\nbackend = sqlite3\nplayer_backend = sqlite3\nauth_backend = sqlite3\nmod_storage_backend = sqlite3\n' > "$out/world/world.mt"
port=${BAYLINE_NATIVE_PORT:-39652}
disp=${BAYLINE_NATIVE_DISPLAY:-165}
width=${BAYLINE_NATIVE_ORIGINAL_WIDTH:-64}
depth=${BAYLINE_NATIVE_ORIGINAL_DEPTH:-64}
seed=${BAYLINE_NATIVE_ORIGINAL_SEED:-1751}
if [[ $width == 64 && $depth == 64 && $seed == 1751 ]]; then seam1=17; seam2=25
else seam1=$((width/2+1)); seam2=$((width/2+9)); fi
cat > "$out/server.conf" <<EOF_SERVER
port = $port
bind_address = 127.0.0.1
prometheus_listener_address = 127.0.0.1:$port
server_announce = false
bayline_original_terrain_exploration = true
bayline_original_terrain_width = $width
bayline_original_terrain_depth = $depth
bayline_original_terrain_seed = $seed
max_block_send_distance = 16
max_block_generate_distance = 12
active_block_range = 1
EOF_SERVER
cat > "$out/client.conf" <<'EOF_CLIENT'
screen_w = 1440
screen_h = 900
fullscreen = false
enable_sound = false
viewing_range = 145
fog_start = 0.84
fps_max = 38
enable_fog = true
mip_map = true
keymap_toggle_chat = KEY_F2
EOF_CLIENT
export HOME="$out/home" XDG_CACHE_HOME="$out/cache" XDG_CONFIG_HOME="$out/home/.config" \
  LUANTI_GAME_PATH="$out/games" MINETEST_GAME_PATH="$out/games" \
  LIBGL_ALWAYS_SOFTWARE=1 ALSOFT_DRIVERS=null
export DISPLAY=":$disp" XAUTHORITY="$out/Xauthority"
pids=()
cleanup() {
  for pid in "${pids[@]}"; do kill -TERM "$pid" 2>/dev/null || true; done
  wait || true
}
trap cleanup EXIT
display_args=(-nolisten tcp)
prefix=()
if [[ ${BAYLINE_NATIVE_TCP:-0} == 1 ]]; then
  cc -shared -fPIC "$repo/tests/native_loopback.c" -ldl -o "$out/loopback.so"
  export DISPLAY="127.0.0.1:$disp"
  display_args=(-listen tcp -nolisten unix -nolisten local)
  prefix=(env "LD_PRELOAD=$out/loopback.so${LD_PRELOAD:+:$LD_PRELOAD}")
fi
touch "$XAUTHORITY"
cookie=$(python3 -c 'import secrets; print(secrets.token_hex(16))')
xauth -f "$XAUTHORITY" add "$DISPLAY" MIT-MAGIC-COOKIE-1 "$cookie"
"${prefix[@]}" Xvfb ":$disp" -screen 0 1440x900x24 "${display_args[@]}" -auth "$XAUTHORITY" -noreset >"$out/xvfb.log" 2>&1 &
pids+=("$!")
for _ in {1..60}; do if xdpyinfo >/dev/null 2>&1; then break; fi; sleep .2; done
xdpyinfo >/dev/null 2>&1 || { cat "$out/xvfb.log"; exit 1; }
wait_log() {
  for _ in {1..850}; do
    if grep -Fq "$1" "$out/server.log"; then return 0; fi
    if grep -E 'ERROR\[' "$out/server.log"; then break; fi
    sleep .12
  done
  cat "$out/server.log"; [[ ! -f "$out/client.log" ]] || tail -60 "$out/client.log"
  return 1
}
"$server" --world "$out/world" --config "$out/server.conf" --gameid luanttd --logfile '' >"$out/server.log" 2>&1 &
server_pid=$!
pids+=("$server_pid")
wait_log 'listening'
"$client" --go --address 127.0.0.1 --port "$port" --config "$out/client.conf" --name SurveyQA --logfile '' >"$out/client.log" 2>&1 &
pids+=("$!")
client_pid="$!"
wait_log 'ORIGINAL TERRAIN COAST READY'
win=$(xdotool search --sync --onlyvisible --pid "$client_pid" | tail -1)
xdotool windowfocus --sync "$win"
xdotool mousemove 720 450
# Hide chat; stock commands still enter through the real client.
xdotool key F2
sleep 3
import -window root "$out/coast.png"
say() {
  xdotool key t; sleep .22; xdotool type "$1"; xdotool key Return
}
say '/terrain transect'
sleep 2
import -window root "$out/transect-start.png"
say '/explorer_probe'
wait_log 'ORIGINAL TERRAIN FLIGHT ARMED'
xdotool keydown w
wait_log "ORIGINAL TERRAIN PLAYER CROSSED SEAM $seam1"
import -window root "$out/transect-seam$seam1.png"
wait_log "ORIGINAL TERRAIN PLAYER CROSSED SEAM $seam2"
xdotool keyup w
sleep .3
import -window root "$out/transect-seam$seam2.png"
say '/terrain summit'
sleep 2
import -window root "$out/summit.png"
grep -E 'ORIGINAL TERRAIN (GEOGRAPHY|PLAYER)' "$out/server.log"
if grep -E 'ERROR\[' "$out/"{server,client}.log; then exit 1; fi
kill -TERM "$client_pid" "$server_pid"
wait "$client_pid" || true
wait "$server_pid"
printf '\nbayline_explorer_probe_restart = true\n' >> "$out/server.conf"
timeout 110 "$server" --world "$out/world" --config "$out/server.conf" --gameid luanttd --logfile '' >"$out/restart.log" 2>&1 || {
  cat "$out/restart.log"; exit 1;
}
grep -E 'ORIGINAL TERRAIN SQLITE RESTART SAME [0-9]+ TILES' "$out/restart.log"
if grep -E 'ERROR\[' "$out/restart.log"; then exit 1; fi
echo "Private visual terrain evidence: $out"
