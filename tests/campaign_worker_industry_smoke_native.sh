#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
out=$(mktemp -d "${TMPDIR:-/tmp}/luanttd-industry-smoke-native.XXXXXX")
echo "Native industry smoke evidence: $out"
game="$out/games/luanttd"
mkdir -p "$game" "$out/world" "$out/home" "$out/cache"
cp game.conf "$game/"
cp -al mods "$game/" 2>/dev/null || cp -a mods/. "$game/mods/"
cp mods/luanttd_core/init.lua "$out/init.lua"
mv "$out/init.lua" "$game/mods/luanttd_core/init.lua"
printf '\n' >>"$game/mods/luanttd_core/init.lua"
cat tests/campaign_worker_industry_smoke_native.lua >>"$game/mods/luanttd_core/init.lua"
printf 'gameid = luanttd\nbackend = sqlite3\nplayer_backend = sqlite3\nauth_backend = sqlite3\nmod_storage_backend = sqlite3\n' >"$out/world/world.mt"
port=${BAYLINE_NATIVE_PORT:-42662}
display=${BAYLINE_NATIVE_DISPLAY:-389}
cat >"$out/server.conf" <<CONF
port = $port
bind_address = 127.0.0.1
prometheus_listener_address = 127.0.0.1:$port
server_announce = false
bayline_generated_map_width = 128
bayline_generated_map_depth = 128
bayline_generated_relief = 0
bayline_generated_coasts = 0
bayline_generated_towns = 3
bayline_generated_industries = 6
bayline_generated_industry_count = 32
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
cc -shared -fPIC tests/native_loopback.c -ldl -o "$out/loopback.so"
env LD_PRELOAD="$out/loopback.so" Xvfb ":$display" -screen 0 1440x900x24 -listen tcp -nolisten local -nolisten unix -ac -noreset >"$out/xvfb.log" 2>&1 &
xv=$!; server= client=
trap '[[ -z "$client" ]] || kill "$client" 2>/dev/null || true; [[ -z "$server" ]] || kill "$server" 2>/dev/null || true; kill "$xv" 2>/dev/null || true;wait 2>/dev/null || true' EXIT
for _ in {1..40}; do xdpyinfo >/dev/null 2>&1 && break; sleep .25; done
xdpyinfo > /dev/null || { cat "$out/xvfb.log"; exit 1; }
luantiserver --world "$out/world" --gameid luanttd --config "$out/server.conf" --logfile '' >"$out/server.log" 2>&1 &
server=$!
mark(){ for _ in {1..360}; do grep -q "$1" "$out/server.log" && return; kill -0 "$server" 2>/dev/null || break; sleep .25; done; tail -70 "$out/server.log"; return 1; }
mark 'listening on'
luanti --go --address 127.0.0.1 --port "$port" --name IndustrySmokeQA --password '' --config "$out/client.conf" --logfile '' >"$out/client.log" 2>&1 &
client=$!
mark 'INDUSTRY_SMOKE_BASELINE'
sleep 1
import -window root "$out/no-smoke.png"
mark 'INDUSTRY_SMOKE_ONSCREEN'
sleep .45
import -window root "$out/industry-smoke.png"
mark 'PASS NATIVE WORKER INDUSTRY SMOKE'
python3 - "$out" <<'PYQA'
from collections import Counter
from PIL import Image
from pathlib import Path
from statistics import median
from sys import argv
root=Path(argv[1])
still,active=(Image.open(root/f).convert("RGB") for f in ("no-smoke.png","industry-smoke.png"))
def plumes(im, regions):
    counts=Counter()
    for y in range(338, 480):
        # The native client can gently adjust sky exposure; compare each
        # plume to unobstructed sky on the same row, not globally to the
        # earlier frame. Its crosshair has only five bright pixels here.
        level=median(sum(im.getpixel((x,y))) for x in (500,510,525,880,890,900))
        for tag,(a,b) in regions.items():
            counts[tag]+=sum(sum(im.getpixel((x,y)))>level+10 for x in range(a,b))
    return dict(counts)
regions={"left chimney":(637,715),"right chimney":(770,860),"empty side":(520,600)}
base=plumes(still,regions)
live=plumes(active,regions)
assert all(base[k]<=12 for k in regions),base
assert live["left chimney"]>45 and live["right chimney"]>45 and live["empty side"]<=16,live
print("Visible exhaust above both actual stacks compared to unobstructed sky:",live)
PYQA
grep -E 'INDUSTRY_SMOKE|PASS NATIVE WORKER INDUSTRY SMOKE' "$out/server.log"
! grep -E 'ERROR\[' "$out/server.log" "$out/client.log"
