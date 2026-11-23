#!/usr/bin/env bash
# Isolated Linux client proof of real named tooltips and click/tap fallback.
# Requires Luanti/Luantiserver, Xvfb, xdotool, ImageMagick import and tesseract.
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ -n ${BAYLINE_NATIVE_TOOLS:-} ]]; then
  t=$(realpath "$BAYLINE_NATIVE_TOOLS")
  export PATH="$t/run/bin:$t/usr/bin:$PATH"
  export LD_LIBRARY_PATH="$t/usr/lib/x86_64-linux-gnu${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
fi
out=$(mktemp -d "${TMPDIR:-/tmp}/luanttd-depot-hover.XXXXXX")
echo "Native depot hover evidence: $out"
game="$out/games/depottest"
mod="$game/mods/luanttd_core"
mkdir -p "$mod" "$out/world" "$out/home" "$out/cache"
printf 'title = Depot hover test\nallowed_mapgens = singlenode\n' >"$game/game.conf"
printf 'name = luanttd_core\n' >"$mod/mod.conf"
cp mods/luanttd_core/{campaign_worker_depot_ui,depot_vehicle_help}.lua "$mod/"
cp tests/campaign_worker_depot_hover_native.lua "$mod/init.lua"
printf 'gameid = depottest\nbackend = sqlite3\nplayer_backend = sqlite3\nauth_backend = sqlite3\n' >"$out/world/world.mt"
port=${BAYLINE_NATIVE_PORT:-39193}
printf 'port = %s\nbind_address = 127.0.0.1\nmg_name = singlenode\n' "$port" >"$out/server.conf"
printf 'screen_w = 1180\nscreen_h = 760\nfullscreen = false\nenable_sound = false\nfps_max = 30\n' >"$out/client.conf"
export HOME="$out/home" XDG_CACHE_HOME="$out/cache" LUANTI_GAME_PATH="$out/games" MINETEST_GAME_PATH="$out/games"
export LIBGL_ALWAYS_SOFTWARE=1 MESA_SHADER_CACHE_DISABLE=1 ALSOFT_DRIVERS=null
display=${BAYLINE_NATIVE_DISPLAY:-373}
export DISPLAY="127.0.0.1:$display"
cc -shared -fPIC tests/native_loopback.c -ldl -o "$out/loopback.so"
env LD_PRELOAD="$out/loopback.so" Xvfb ":$display" -screen 0 1180x760x24 -listen tcp -nolisten local -nolisten unix -ac -noreset >"$out/xvfb.log" 2>&1 &
xv=$!; server= client=
trap '[[ -z "$client" ]] || kill "$client" 2>/dev/null || true; [[ -z "$server" ]] || kill "$server" 2>/dev/null || true; kill "$xv" 2>/dev/null || true; wait 2>/dev/null || true' EXIT
for _ in {1..40}; do xdpyinfo >/dev/null 2>&1 && break; sleep .25; done
xdpyinfo >/dev/null || { cat "$out/xvfb.log"; exit 1; }
luantiserver --world "$out/world" --gameid depottest --config "$out/server.conf" --logfile '' >"$out/server.log" 2>&1 &
server=$!
mark(){ for _ in {1..160}; do grep -q "$1" "$out/server.log" && return; kill -0 "$server" 2>/dev/null || break; sleep .25; done; tail -70 "$out/server.log"; return 1; }
mark 'listening on'
luanti --go --address 127.0.0.1 --port "$port" --name DepotQA --password '' --config "$out/client.conf" --logfile '' >"$out/client.log" 2>&1 &
client=$!
window=$(timeout 18 xdotool search --onlyvisible --sync --pid "$client" | tail -n 1)
xdotool windowfocus --sync "$window"
mark 'NATIVE DEPOT HOVER READY'
sleep 2
xdotool mousemove 70 80
import -window root "$out/before.png"
python3 - "$out" <<'PY'
from pathlib import Path
import csv, subprocess, sys
out=Path(sys.argv[1])
raw=subprocess.check_output(["tesseract",str(out/"before.png"),"stdout","--psm","11","tsv"],text=True,stderr=subprocess.DEVNULL)
r=list(csv.DictReader(raw.splitlines(),delimiter="\t"))
def word(x):
    p=next(row for row in r if row["text"]==x and int(row["top"])<500)
    return int(p["left"])+int(p["width"])//2,int(p["top"])+int(p["height"])//2
def save(key,name):
    (out/key).write_text(" ".join(map(str,word(name))))
save("buy_location","Witcombe")
save("owned_location","Truck")
PY
hover() {
  local x=$1 y=$2 key=$3
  xdotool mousemove "$x" "$y"
  sleep 1.4
  import -window root "$out/$key.png"
  import -window root -crop "390x145+$((x+16))+$((y+16))" "$out/$key-detail.png"
  tesseract "$out/$key-detail.png" "$out/$key" --psm 6 2>/dev/null
  grep -qi 'Oil Refinery' "$out/$key.txt"
}
read -r ox oy < <(cat "$out/buy_location"; echo)
read -r ux uy < <(cat "$out/owned_location"; echo)
hover "$ox" "$oy" purchase-hover
hover "$ux" "$uy" owned-hover
! grep -q 'NATIVE DEPOT ROW' "$out/server.log"
# A single click is the same formspec action emitted by a tap, and it
# must reveal the guide permanently even after the pointer leaves.
xdotool mousemove "$ox" "$oy" click 1 mousemove 70 80
mark 'NATIVE DEPOT ROW d1_offer_row2'
sleep 1
import -window root "$out/selected.png"
import -window root -crop '596x105+297+478' "$out/selected-detail.png"
tesseract "$out/selected-detail.png" "$out/selected" --psm 6 2>/dev/null
tr '\n' ' ' <"$out/selected.txt" | grep -qi 'Oil Refinery'
! grep -E 'ERROR\[' "$out/client.log" "$out/server.log"
echo 'PASS: Native Luanti purchase-row hover, owned-row hover and tap/click help without purchasing'
