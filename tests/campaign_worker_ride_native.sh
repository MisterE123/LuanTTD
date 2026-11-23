#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
out=$(mktemp -d "${TMPDIR:-/tmp}/luanttd-ride-native.XXXXXX")
echo "Native ride evidence: $out"
game="$out/games/luanttd"
mkdir -p "$game" "$out/world" "$out/home" "$out/cache"
cp game.conf "$game/"
cp -al mods "$game/" 2>/dev/null || cp -a mods/. "$game/mods/"
if [[ -n ${LUANTTD_TEST_RIDE_ART:-} ]]; then
  for folder in models textures; do
    cp "$LUANTTD_TEST_RIDE_ART/mods/luanttd_core/$folder"/bl_ride_* "$game/mods/luanttd_core/$folder/"
  done
fi
cp mods/luanttd_core/init.lua "$out/init.lua"
mv "$out/init.lua" "$game/mods/luanttd_core/init.lua"
printf '\n' >>"$game/mods/luanttd_core/init.lua"
cat tests/campaign_worker_ride_native.lua >>"$game/mods/luanttd_core/init.lua"
printf 'gameid = luanttd\nbackend = sqlite3\nplayer_backend = sqlite3\nauth_backend = sqlite3\nmod_storage_backend = sqlite3\n' >"$out/world/world.mt"
port=${BAYLINE_NATIVE_PORT:-42712}
display=${BAYLINE_NATIVE_DISPLAY:-445}
cat >"$out/server.conf" <<CONF
port = $port
bind_address = 127.0.0.1
prometheus_listener_address = 127.0.0.1:$port
server_announce = false
bayline_generated_map_width = 64
bayline_generated_map_depth = 64
bayline_generated_relief = 0
bayline_generated_coasts = 0
bayline_generated_towns = 3
bayline_generated_town_layout = grid2
bayline_seed = 1751
singleplayer_mode = false
CONF
printf 'screen_w = 1440\nscreen_h = 900\nenable_sound = false\n' >"$out/client.conf"
if [[ -n ${BAYLINE_NATIVE_TOOLS:-} ]]; then
  t=$(realpath "$BAYLINE_NATIVE_TOOLS")
  export PATH="$t/run/bin:$t/usr/bin:$PATH" LD_LIBRARY_PATH="$t/usr/lib/x86_64-linux-gnu${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
fi
export DISPLAY="127.0.0.1:$display" HOME="$out/home" LIBGL_ALWAYS_SOFTWARE=1 MESA_SHADER_CACHE_DISABLE=1
export XDG_CACHE_HOME="${LUANTTD_NATIVE_MEDIA_CACHE:-$out/cache}" LUANTI_GAME_PATH="$out/games" MINETEST_GAME_PATH="$out/games"
# Match an ordinary returning client. Test focus/rider behavior, not two
# cold media downloads competing for the same local server's quota.
if [[ -z ${LUANTTD_NATIVE_MEDIA_CACHE:-} ]]; then
  python3 tests/cache_luanti_game_media.py "$game" "$XDG_CACHE_HOME"
fi
cc -shared -fPIC tests/native_loopback.c -ldl -o "$out/loopback.so"
env LD_PRELOAD="$out/loopback.so" Xvfb ":$display" -screen 0 1440x900x24 -listen tcp -nolisten local -nolisten unix -ac -noreset >"$out/xvfb.log" 2>&1 &
xv=$!; server= client= observer=
trap 'for pid in "$client" "$observer" "$server" "$xv"; do [[ -z "$pid" ]] || kill "$pid" 2>/dev/null || true; done; wait 2>/dev/null || true' EXIT
for _ in {1..40}; do xdpyinfo >/dev/null 2>&1 && break; sleep .25; done
xdpyinfo > /dev/null || { cat "$out/xvfb.log"; exit 1; }
luantiserver --world "$out/world" --gameid luanttd --config "$out/server.conf" --logfile '' >"$out/server.log" 2>&1 &
server=$!
mark(){ for _ in {1..360}; do grep -q "$1" "$out/server.log" && return; kill -0 "$server" 2>/dev/null || break; sleep .25; done; tail -70 "$out/server.log"; return 1; }
mark 'listening on'
cp "$out/client.conf" "$out/observer.conf"
mkdir "$out/observer-home"
env HOME="$out/observer-home" luanti --go --address 127.0.0.1 --port "$port" --name RideWitness --password '' --config "$out/observer.conf" --logfile '' >"$out/observer.log" 2>&1 &
observer=$!
luanti --go --address 127.0.0.1 --port "$port" --name RideQA --password '' --config "$out/client.conf" --logfile '' >"$out/client.log" 2>&1 &
client=$!
win=$(xdotool search --sync --onlyvisible --pid "$client" | tail -n 1)
xdotool windowraise "$win" windowfocus --sync "$win"
for phase in bus cab coach; do
  mark "RIDE_READY $phase"
  xdotool windowraise "$win" windowfocus --sync "$win"
  sleep .30
  import -window root "$out/$phase-builder.png"
  if [[ "$phase" == cab ]]; then xdotool mousemove 682 232 click 1
  else xdotool mousemove 794 232 click 1
  fi
  mark "RIDE_VISIBLE $phase"
  sleep .35
  import -window root "$out/$phase-forward.png"
  xdotool keydown w; xdotool mousemove_relative -- 250 15; sleep 1; xdotool keyup w
  mark "RIDE_SIDE_VIEW $phase"
  sleep .15
  import -window root "$out/$phase-side.png"
  if [[ "$phase" == bus ]]; then xdotool keydown e; sleep .22; xdotool keyup e
  elif [[ "$phase" == cab ]]; then xdotool mousedown 3; sleep .22; xdotool mouseup 3
  else
    xdotool key i; sleep .65
    import -window root "$out/$phase-inventory.png"
    xdotool mousemove 720 469 click 1
  fi
  mark "PASS NATIVE PRIVATE RIDE $phase"
done
mark 'PASS NATIVE ALL SEATED MODES'
mark 'PASS NATIVE WORKER SEAT COMMAND /ride'
mark 'PASS NATIVE WORKER SEAT COMMAND /train'
python3 - "$out" <<'PYQA'
from pathlib import Path
from PIL import Image
from sys import argv
root=Path(argv[1])
def proportion(image, rect, test):
    colors=list(image.crop(rect).getdata())
    return sum(test(*rgb) for rgb in colors)/len(colors)
def warm(r,g,b):
    return r>b+9 and g>b-12
def outside(r,g,b):
    return (b-r>22 and b-g>6 and b>100) or (g-r>12 and g-b>12)
for mode in ("bus","cab","coach"):
    for view in ("forward","side"):
        shot=Image.open(root/f"{mode}-{view}.png").convert("RGB")
        structure=(585,100,850,235) if mode!="cab" or view=="side" else (40,80,320,235)
        assert proportion(shot,structure,warm)>.08,(mode,view,"cabin mesh missing")
        assert proportion(shot,(300,210,1130,545),outside)>.025,(mode,view,"outside scenery missing")
print("Six native views show the cabin and actual scenery through its windows")
PYQA
grep -E 'RIDE|PASS NATIVE' "$out/server.log"
! grep -E 'ERROR\[' "$out/server.log" "$out/client.log" "$out/observer.log"
