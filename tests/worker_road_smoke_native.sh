#!/usr/bin/env bash
# Isolated Linux client proof of real projected vehicle breakdown smoke.
# Requires Luanti/Luantiserver, Xvfb, xdotool, ImageMagick import.
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ -n ${BAYLINE_NATIVE_TOOLS:-} ]]; then
  t=$(realpath "$BAYLINE_NATIVE_TOOLS")
  export PATH="$t/run/bin:$t/usr/bin:$PATH"
  export LD_LIBRARY_PATH="$t/usr/lib/x86_64-linux-gnu${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
fi
out=$(mktemp -d "${TMPDIR:-/tmp}/luanttd-road-smoke.XXXXXX")
echo "Native road smoke evidence: $out"
game="$out/games/smoketest"
mod="$game/mods/luanttd_core"
mkdir -p "$mod" "$out/world" "$out/home" "$out/cache"
printf 'title = Road smoke test\nallowed_mapgens = singlenode\n' >"$game/game.conf"
printf 'name = luanttd_core\n' >"$mod/mod.conf"
mkdir -p "$mod"/{openttd,models,textures}
cp mods/luanttd_core/{campaign_actor_projection,campaign_projected_actors,road_fault_view,road_motion,road_stock_media,road_lanes}.lua "$mod/"
cp mods/luanttd_core/openttd/road_breakdowns.lua "$mod/openttd/"
cp mods/luanttd_core/models/bl_town_flyer.obj "$mod/models/"
cp mods/luanttd_core/textures/{bl_vehicle_palette,bl_road_breakdown_smoke}.png "$mod/textures/"
cp tests/worker_road_smoke_native.lua "$mod/init.lua"
printf 'gameid = smoketest\nbackend = sqlite3\nplayer_backend = sqlite3\nauth_backend = sqlite3\n' >"$out/world/world.mt"
port=${BAYLINE_NATIVE_PORT:-39197}
printf 'port = %s\nbind_address = 127.0.0.1\nmg_name = singlenode\ntime_speed = 0\n' "$port" >"$out/server.conf"
printf 'screen_w = 1180\nscreen_h = 760\nfullscreen = false\nenable_sound = false\nfps_max = 30\n' >"$out/client.conf"
export HOME="$out/home" XDG_CACHE_HOME="$out/cache" LUANTI_GAME_PATH="$out/games" MINETEST_GAME_PATH="$out/games"
export LIBGL_ALWAYS_SOFTWARE=1 MESA_SHADER_CACHE_DISABLE=1 ALSOFT_DRIVERS=null
display=${BAYLINE_NATIVE_DISPLAY:-379}
export DISPLAY="127.0.0.1:$display"
cc -shared -fPIC tests/native_loopback.c -ldl -o "$out/loopback.so"
env LD_PRELOAD="$out/loopback.so" Xvfb ":$display" -screen 0 1180x760x24 -listen tcp -nolisten local -nolisten unix -ac -noreset >"$out/xvfb.log" 2>&1 &
xv=$!; server= client=
trap '[[ -z "$client" ]] || kill "$client" 2>/dev/null || true; [[ -z "$server" ]] || kill "$server" 2>/dev/null || true; kill "$xv" 2>/dev/null || true; wait 2>/dev/null || true' EXIT
for _ in {1..40}; do xdpyinfo >/dev/null 2>&1 && break; sleep .25; done
xdpyinfo >/dev/null || { cat "$out/xvfb.log"; exit 1; }
luantiserver --world "$out/world" --gameid smoketest --config "$out/server.conf" --logfile '' >"$out/server.log" 2>&1 &
server=$!
mark(){ for _ in {1..160}; do grep -q "$1" "$out/server.log" && return; kill -0 "$server" 2>/dev/null || break; sleep .25; done; tail -70 "$out/server.log"; return 1; }
mark 'listening on'
luanti --go --address 127.0.0.1 --port "$port" --name SmokeQA --password '' --config "$out/client.conf" --logfile '' >"$out/client.log" 2>&1 &
client=$!
window=$(timeout 18 xdotool search --onlyvisible --sync --pid "$client" | tail -n 1)
xdotool windowfocus --sync "$window"
mark 'NATIVE ROAD SMOKE HEALTHY'
import -window root "$out/healthy.png"
mark 'NATIVE ROAD SMOKE ACTIVE'
sleep .6
import -window root "$out/broken.png"
mark 'NATIVE ROAD SMOKE RECOVERED'
sleep 1.2
import -window root "$out/recovered.png"
mark 'NATIVE ROAD SMOKE COMPLETE'
python3 - "$out" <<'PYQA'
from pathlib import Path
from PIL import Image, ImageChops
import sys
path = Path(sys.argv[1])
def pixels(first, second):
    a,b=(Image.open(path / (k+'.png')).convert('RGB').crop((420,240,765,465)) for k in (first,second))
    return sum(max(p)>9 for p in ImageChops.difference(a,b).getdata())
on,off=pixels('healthy','broken'),pixels('healthy','recovered')
assert on>=30 and on>off+20, (on,off)
print(f'PASS native vehicle breakdown plume: {on} changed pixels while broken, {off} after recovery')
PYQA
