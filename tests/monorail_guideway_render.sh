#!/usr/bin/env bash
# Native graphical rendering of the actual shipped OBJ and atlas under Luanti.
# Inputs match tests/native.sh; isolated world and profile, no existing saves.
set -euo pipefail
cd "$(dirname "$0")/.."
repo=${LUANTTD_BASE:-$PWD}
one=$(realpath "${1:?real guideway worker world output}")
family=${BAYLINE_GUIDEWAY_TYPE:-mono}
[[ "$family" == mono || "$family" == maglev ]]
if [[ "$family" == maglev ]]; then
  models=(lev1_body maglev_passenger_body maglev_mail_body maglev_suspension maglev_drawbar)
  textures=(lev1 maglev_passenger maglev_mail)
else
  models=(x2001_body mono_passenger_body mono_mail_body mono_bogie mono_drawbar)
  textures=(x2001 mono_passenger mono_mail)
fi
if [[ -n ${BAYLINE_NATIVE_TOOLS:-} ]]; then
  tools=$(realpath "$BAYLINE_NATIVE_TOOLS")
  export PATH="$tools/run/bin:$tools/usr/bin:$PATH"
  export LD_LIBRARY_PATH="$tools/usr/lib/x86_64-linux-gnu${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
fi
out=$(mktemp -d "${TMPDIR:-/tmp}/luanttd-monorail-graphics.XXXXXX")
echo "Native guideway art evidence: $out"
disp=${BAYLINE_NATIVE_DISPLAY:-253}
port=${BAYLINE_NATIVE_PORT:-40037}
pids=()
cleanup() {
  for pid in "${pids[@]}"; do kill -TERM "$pid" 2>/dev/null || true; done
  wait || true
}
trap cleanup EXIT
mod="$out/games/rail_art/mods/luanttd_core"
cargo=${BAYLINE_GUIDEWAY_CARGO:-town}
mkdir -p "$mod/"{models,textures} "$out/"{world,home,cache}
printf 'title = LuanTTD guideway art fixture\n' > "$out/games/rail_art/game.conf"
printf 'name = luanttd_core\n' > "$mod/mod.conf"
cp tests/monorail_guideway_render.lua "$mod/init.lua"
if [[ "$cargo" == oil ]]; then
  models+=("${family}_oil_tanker_body")
  textures+=("${family}_oil_tanker")
  cp "$one/guideway-oil-loaded-frame.json" "$mod/mixed-pose-loading.json"
  cp "$one/guideway-oil-loaded-frame.json" "$mod/mixed-pose-reversed.json"
elif [[ "$cargo" == z1 ]]; then
  models+=(millennium_z1_body)
  textures+=(millennium_z1)
  cp "$one/millennium-z1-frame.json" "$mod/mixed-pose-loading.json"
  cp "$one/millennium-z1-frame.json" "$mod/mixed-pose-reversed.json"
else
  cp "$one"/mixed-pose-{loading,reversed}.json "$mod/"
fi
cp "$repo"/mods/luanttd_core/{rail_diagonal,rail_guideway_bogies,rail_guideway_drawbar,rail_guideway_profiles,rail_pose,campaign_projected_actors,road_motion,road_stock_media,airport_rotor_view,road_fault_view}.lua "$mod/"
cp "$repo"/mods/luanttd_core/openttd/rail_track.lua "$mod/"
mkdir -p "$mod/openttd"
cp "$repo"/mods/luanttd_core/openttd/rail_roster.lua "$mod/openttd/"
cp "$repo"/mods/luanttd_core/openttd/{rail_types,advanced_rail_roster}.lua "$mod/openttd/"
cp "$repo"/mods/luanttd_core/{rail_dispatch_manifest,rail_freight_kinds}.lua "$mod/"
cp "$repo"/mods/luanttd_core/models/bl_guideway_"${family}"_{eased,flat,platform,depot}_*.obj "$mod/models/"
for m in "${models[@]}"; do cp "$repo/mods/luanttd_core/models/bl_rail_$m.obj" "$mod/models/"; done
for t in "${textures[@]}"; do cp "$repo/mods/luanttd_core/textures/bl_rail_$t.png" "$mod/textures/"; done
cp "$repo"/mods/luanttd_core/textures/{bl_grass1,"bl_guideway_${family}_atlas","bl_guideway_${family}_facility_atlas"}.png "$mod/textures/"
printf '%s\n%s\n' "$family" "$cargo" > "$mod/qa-variant.txt"
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
luantiserver --world "$out/world" --config "$out/server.conf" --gameid rail_art --logfile "" > "$out/server.log" 2>&1 &
pids+=("$!")
for _ in {1..40}; do if grep -q 'listening' "$out/server.log"; then break; fi; sleep .25; done
grep -q 'listening' "$out/server.log" || { cat "$out/server.log"; exit 1; }
luanti --go --address 127.0.0.1 --port "$port" --config "$out/client.conf" --name RailQA --logfile "" > "$out/client.log" 2>&1 &
client=$!
pids+=("$client")
window=$(xdotool search --sync --onlyvisible --pid "$client" | tail -1)
xdotool windowfocus --sync "$window"
for shot in 1 2 3; do
  for _ in {1..160}; do
    if grep -q "MONORAIL_GRAPHICS_FRAME $shot" "$out/server.log"; then break; fi
    sleep .18
  done
  grep "MONORAIL_GRAPHICS_FRAME $shot" "$out/server.log" || { cat "$out/"{server,client}.log; exit 1; }
  sleep 2.4
  import -window root "$out/mono-$shot.png"
done
! grep -Ei 'ERROR\[|could not load' "$out/client.log" "$out/server.log"
ls -l "$out"/mono-?.png
