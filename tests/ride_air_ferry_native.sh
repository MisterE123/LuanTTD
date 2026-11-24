#!/usr/bin/env bash
# Minimal real Luanti client test: exact ride controller and game meshes.
set -euo pipefail
cd "$(dirname "$0")/.."
out=$(mktemp -d "${TMPDIR:-/tmp}/ride-air-ferry.XXXXXX")
echo "Native passenger-view evidence: $out"
game="$out/games/rideqa"; mod="$game/mods/luanttd_core"
mkdir -p "$mod"/{models,textures} "$out/"{world,home,cache}
printf 'title = Passenger flight and ferry\nallowed_mapgens = singlenode\n' > "$game/game.conf"
printf 'name = luanttd_core\n' > "$mod/mod.conf"
for f in vehicle_ui vehicle_ride pedestrian campaign_order_target initial_vehicle_route; do cp "mods/luanttd_core/$f.lua" "$mod/"; done
cp mods/luanttd_core/models/{bl_ride_airliner_interior.obj,bl_ride_ferry_interior.obj,bl_bayshore_trimotor.obj,bl_harbor_ferry.obj} "$mod/models/"
cp mods/luanttd_core/textures/{bl_sightseeing_hidden_player.png,bl_ride_airliner_interior.png,bl_ride_ferry_interior.png,bl_bayshore_trimotor_palette.png,bl_harbor_ferry_palette.png} "$mod/textures/"
cp tests/ride_air_ferry_native.lua "$mod/init.lua"
printf 'gameid = rideqa\nbackend = sqlite3\nplayer_backend = sqlite3\nauth_backend = sqlite3\nmod_storage_backend = sqlite3\n' > "$out/world/world.mt"
port=${BAYLINE_NATIVE_PORT:-42179}; display=${BAYLINE_NATIVE_DISPLAY:-364}
printf 'port = %s\nbind_address = 127.0.0.1\nserver_announce = false\nmg_name = singlenode\ntime_speed = 0\n' "$port" > "$out/server.conf"
printf 'screen_w = 1100\nscreen_h = 720\nkeymap_zoom = KEY_KEY_Z\nenable_sound = false\nviewing_range = 70\nfps_max = 25\n' > "$out/client.conf"
export HOME="$out/home" XDG_CACHE_HOME="$out/cache" LUANTI_GAME_PATH="$out/games" MINETEST_GAME_PATH="$out/games" LIBGL_ALWAYS_SOFTWARE=1 LP_NUM_THREADS=1 MESA_SHADER_CACHE_DISABLE=1 ALSOFT_DRIVERS=null
export DISPLAY="127.0.0.1:$display"
cc -shared -fPIC tests/native_loopback.c -ldl -o "$out/loopback.so"
env LD_PRELOAD="$out/loopback.so" Xvfb ":$display" -screen 0 1100x720x24 -listen tcp -nolisten local -nolisten unix -ac -noreset >"$out/xvfb.log" 2>&1 &
x=$!;s= c=
trap 'kill "$x" 2>/dev/null || true; [[ -z "$c" ]] || kill "$c" 2>/dev/null||true; [[ -z "$s" ]] || kill "$s" 2>/dev/null||true;wait 2>/dev/null||true' EXIT
for _ in {1..35}; do xdpyinfo >/dev/null 2>&1 && break;sleep .2; done
luantiserver --config "$out/server.conf" --world "$out/world" --gameid rideqa --logfile "" > "$out/server.log" 2>&1 &
s=$!
mark(){ for _ in {1..250}; do grep -q "$1" "$out/server.log" && return; kill -0 "$s" 2>/dev/null || break; sleep .12; done; tail -40 "$out/server.log"; return 1; }
mark listening
luanti --go --address 127.0.0.1 --port "$port" --config "$out/client.conf" --name RideQA --logfile "" > "$out/client.log" 2>&1 &
c=$!
mark RIDE_AIR_FERRY_NATIVE_READY
win=$(timeout 12 xdotool search --sync --onlyvisible --pid "$c"|tail -1)
xdotool windowfocus --sync "$win"
sleep 1.2
say(){ xdotool windowfocus "$win";xdotool key t;sleep .33;xdotool type "$1";xdotool key Return;sleep .60; }
snap(){ import -window root -quality 89 "$out/$1.jpg"; }
for kind in air ship; do
  say "/rideprobe $kind";mark "RIDE_AIR_FERRY_NATIVE_$kind";snap "$kind"
  xdotool keydown z;sleep .7;snap "$kind-zoom";xdotool keyup z;sleep .3
  xdotool key e;xdotool click 3
  say "/rideprobe active";mark "RIDE_AIR_FERRY_NATIVE_ACTIVE_$kind"
  xdotool key i;sleep .55;snap "$kind-inventory"
  xdotool mousemove 549 386 click 1;sleep .55
  say "/rideprobe left";mark "RIDE_AIR_FERRY_NATIVE_LEFT_$kind"
done
grep 'RIDE_AIR_FERRY_NATIVE_' "$out/server.log"
! grep 'ERROR\[' "$out/server.log" "$out/client.log"
