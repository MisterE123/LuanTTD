#!/usr/bin/env bash
# Real monorail hotbar and pointer in a fresh native campaign.
set -euo pipefail
cd "$(dirname "$0")/.."
out=$(mktemp -d "${TMPDIR:-/tmp}/luanttd-monorail-control-native.XXXXXX")
type=${BAYLINE_GUIDEWAY_TYPE:-mono}
[[ "$type" == mono || "$type" == maglev ]]
echo "Native $type input evidence: $out"
game="$out/games/luanttd"
mkdir -p "$game" "$out/"{world,home,cache}
cp game.conf "$game/"
cp -al mods "$game/" 2>/dev/null || cp -a mods/. "$game/mods/"
cp "$game/mods/luanttd_core/init.lua" "$out/native-init"
mv "$out/native-init" "$game/mods/luanttd_core/init.lua"
printf '\n' >>"$game/mods/luanttd_core/init.lua"
cat tests/monorail_controls_native.lua >>"$game/mods/luanttd_core/init.lua"
printf 'gameid = luanttd\nbackend = sqlite3\nplayer_backend = sqlite3\nauth_backend = sqlite3\nmod_storage_backend = sqlite3\n' >"$out/world/world.mt"
printf '%s\n' "$type" >"$out/world/qa-guideway.txt"
year=2010
[[ "$type" != maglev ]] || year=2025
port=${BAYLINE_NATIVE_PORT:-40615}
display=${BAYLINE_NATIVE_DISPLAY:-195}
cat >"$out/server.conf" <<CONF
port = $port
prometheus_listener_address = 127.0.0.1:$port
bind_address = 127.0.0.1
server_announce = false
bayline_generated_map_width = 64
bayline_generated_map_depth = 64
bayline_generated_relief = 0
bayline_generated_coasts = 0
bayline_generated_tree_placer = 0
bayline_stock_bus_start_year = $year
CONF
cat >"$out/client.conf" <<CONF
screen_w = 1280
screen_h = 800
enable_sound = false
enable_shaders = false
viewing_range = 44
fps_max = 30
CONF
if [[ -n ${BAYLINE_NATIVE_TOOLS:-} ]]; then
  t=$(realpath "$BAYLINE_NATIVE_TOOLS")
  export PATH="$t/run/bin:$t/usr/bin:$PATH" LD_LIBRARY_PATH="$t/usr/lib/x86_64-linux-gnu${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
fi
export DISPLAY="127.0.0.1:$display" HOME="$out/home" LIBGL_ALWAYS_SOFTWARE=1 LP_NUM_THREADS=2
export XDG_CACHE_HOME="${LUANTTD_NATIVE_MEDIA_CACHE:-$out/cache}" LUANTI_GAME_PATH="$out/games" MINETEST_GAME_PATH="$out/games"
# This QA checks the gameplay, not media download. Seed an isolated
# content-addressed cache exactly like a returning Linux client.
python3 - "$XDG_CACHE_HOME" <<'PYCACHE'
from pathlib import Path
from hashlib import sha1
import os, shutil, sys
root=Path(sys.argv[1])/"minetest/media"
root.mkdir(parents=True,exist_ok=True)
for p in Path("mods").rglob("*"):
    if not p.is_file() or not {"models","textures","sounds"}.intersection(p.parts):
        continue
    out=root/sha1(p.read_bytes()).hexdigest()
    if not out.exists():
        try: os.link(p,out)
        except OSError: shutil.copyfile(p,out)
PYCACHE
cc -shared -fPIC tests/native_loopback.c -ldl -o "$out/loopback.so"
env LD_PRELOAD="$out/loopback.so" Xvfb ":$display" -screen 0 1280x800x24 -listen tcp -nolisten local -nolisten unix -ac -noreset >"$out/xvfb.log" 2>&1 &
xv=$!; server= client=
trap 'kill "$xv" 2>/dev/null || true; [[ -z "$client" ]] || kill "$client" 2>/dev/null || true; [[ -z "$server" ]] || kill "$server" 2>/dev/null || true; wait 2>/dev/null || true' EXIT
for _ in {1..40}; do xdpyinfo >/dev/null 2>&1 && break; sleep .25; done
luantiserver --world "$out/world" --gameid luanttd --config "$out/server.conf" --logfile '' >"$out/server.log" 2>&1 &
server=$!
mark(){
  for _ in {1..300}; do
    grep -q "$1" "$out/server.log" && return
    kill -0 "$server" 2>/dev/null || break
    sleep .20
  done
  tail -60 "$out/server.log"; return 1
}
mark 'listening on'
luanti --go --address 127.0.0.1 --port "$port" --name MonoQA --password '' --config "$out/client.conf" --logfile '' >"$out/client.log" 2>&1 &
client=$!
window=$(xdotool search --sync --limit 1 --onlyvisible --pid "$client"|tail -1)
xdotool windowfocus --sync "$window"
snap(){ import -window root "$out/$1.png"; }
slot(){
  local signal="MONO_UI_$1"
  mark "$signal "
  local k
  k=$(grep "$signal " "$out/server.log" | tail -1 | awk '{print $NF}')
  [[ "$k" != 10 ]] || k=0
  xdotool key "$k"; sleep .4
}
tap(){ xdotool mousedown "${1:-1}"; sleep .20; xdotool mouseup "${1:-1}"; }
click_word(){
  local key=$1 pattern=$2
  tesseract "$out/$key.png" "$out/$key" --psm 11 tsv 2>/dev/null
  local ax ay
  read -r ax ay < <(awk -F '	' -v word="$pattern" 'tolower($12)~word {print $7+int($9/2),$8+int($10/2);exit}' "$out/$key.tsv")
  [[ -n "$ax" && -n "$ay" ]]
  xdotool mousemove "$ax" "$ay"; tap
}
if [[ "$type" == maglev ]]; then
  slot FINANCE_HOME; tap
  slot FINANCE_BUTTON; tap
  mark MONO_UI_FINANCE_OPEN
  for turn in 1 2 3; do
    sleep 1
    snap finance
    xdotool mousemove 525 427; tap
  done
  mark MONO_UI_FINANCED
  xdotool key Escape; sleep .6
  slot FINANCE_BACK; tap
fi
for menu in HOME RAILWORKS OPS ENG TYPE TYPE_BACK ENG_BACK OPS_BACK; do
  slot "$menu"
  if [[ "$menu" == TYPE ]]; then snap rail-types; fi
  tap
done
slot TRACK; xdotool mousedown 1
mark MONO_UI_TRACK_GHOST; snap track-ghost; xdotool mouseup 1
mark MONO_UI_TRACK_BUILT
slot DEPOT; tap
mark MONO_UI_DEPOT_BUILT
for stage in ONE TWO; do
  slot "STATION_$stage"; xdotool mousedown 1
  mark "MONO_UI_STATION_${stage}_AIM"; sleep .8; xdotool mouseup 1
  mark "MONO_UI_STATION_${stage}_BUILT"
done
slot DEPOT_FOCUS; tap 3
mark MONO_UI_DEPOT_OPEN
sleep .8; snap depot
click_word depot assemble
sleep 1; snap assembly; mark MONO_UI_ASSEMBLY
xdotool key Escape; sleep .6; tap 3
sleep .9; snap buy
click_word buy '^buy$'
mark MONO_UI_BOUGHT; sleep 1; snap orders
click_word orders '^start$'
mark MONO_UI_PASS; sleep .8; snap dispatched
! grep 'ERROR\[' "$out/"{client,server}.log
grep MONO_UI_ "$out/server.log"
