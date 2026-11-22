#!/usr/bin/env bash
# Isolated native client proof. A private 14.1 .sav is required; never changed.
set -euo pipefail
cd "$(dirname "$0")/.."
repo=$PWD
if [[ $# -lt 1 || $# -gt 2 ]]; then
  echo "usage: $0 private-stock.sav [new-private-output-directory]" >&2
  exit 64
fi
source_save=$(realpath "$1")
before=$(sha256sum "$source_save")
if [[ $# -eq 2 ]]; then
  out=$(realpath -m "$2")
else
  out=$(mktemp -d /tmp/luanttd-terrain-survey.XXXXXX)
  rmdir "$out"
fi
if [[ -n ${BAYLINE_NATIVE_TOOLS:-} ]]; then
  tools=$(realpath "$BAYLINE_NATIVE_TOOLS")
  export PATH="$tools/run/bin:$tools/usr/bin:$PATH"
  export LD_LIBRARY_PATH="$tools/usr/lib/x86_64-linux-gnu${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
fi
python3 tests/terrain_survey_setup.py "$source_save" "$out"
echo "Private visual terrain survey: $out"
client=${BAYLINE_LUANTI_CLIENT:-luanti}
server=${BAYLINE_LUANTI_SERVER:-luantiserver}
for bin in "$client" "$server" Xvfb xdpyinfo xauth xdotool import; do
  command -v "$bin" >/dev/null || { echo "Missing $bin" >&2; exit 1; }
done
port=${BAYLINE_NATIVE_PORT:-39562}
disp=${BAYLINE_NATIVE_DISPLAY:-147}
pids=()
cleanup() {
  for pid in "${pids[@]}"; do kill -TERM "$pid" 2>/dev/null || true; done
  wait || true
}
trap cleanup EXIT
mkdir -p "$out/"{world,home,cache}
printf 'gameid = stock_survey\nbackend = sqlite3\nplayer_backend = sqlite3\nauth_backend = sqlite3\nmod_storage_backend = sqlite3\n' > "$out/world/world.mt"
cat > "$out/server.conf" <<EOF_SERVER
port = $port
bind_address = 127.0.0.1
server_announce = false
active_block_range = 2
server_map_save_interval = 15
EOF_SERVER
cat > "$out/client.conf" <<'EOF_CLIENT'
screen_w = 1360
screen_h = 850
fullscreen = false
enable_sound = false
viewing_range = 53
fog_start = 0.7
fps_max = 32
free_move = true
noclip = true
keymap_toggle_chat = KEY_F2
EOF_CLIENT
export HOME="$out/home" XDG_CACHE_HOME="$out/cache" XDG_CONFIG_HOME="$out/home/.config" \
  LUANTI_GAME_PATH="$out/games" MINETEST_GAME_PATH="$out/games" \
  LIBGL_ALWAYS_SOFTWARE=1 ALSOFT_DRIVERS=null
export DISPLAY=":$disp" XAUTHORITY="$out/Xauthority"
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
"${prefix[@]}" Xvfb ":$disp" -screen 0 1360x850x24 "${display_args[@]}" -auth "$XAUTHORITY" -noreset >"$out/xvfb.log" 2>&1 &
pids+=("$!")
for _ in {1..60}; do if xdpyinfo >/dev/null 2>&1; then break; fi; sleep .2; done
xdpyinfo >/dev/null 2>&1 || { cat "$out/xvfb.log"; exit 1; }
wait_log() {
  for _ in {1..180}; do
    if grep -Fq "$1" "$out/server.log"; then return 0; fi
    if grep -Eq 'ERROR\[.*(ModError|Lua|runtime error)' "$out/server.log"; then break; fi
    sleep .2
  done
  cat "$out/server.log"; [[ ! -f "$out/client.log" ]] || tail -60 "$out/client.log"
  return 1
}
"$server" --world "$out/world" --config "$out/server.conf" --gameid stock_survey --logfile '' > "$out/server.log" 2>&1 &
pids+=("$!")
wait_log 'listening'
"$client" --go --address 127.0.0.1 --port "$port" --config "$out/client.conf" --name SurveyQA --logfile '' > "$out/client.log" 2>&1 &
pids+=("$!")
client_pid="$!"
wait_log 'TERRAIN_SURVEY_READY coast'
win=$(xdotool search --sync --onlyvisible --pid "$client_pid" | tail -1)
xdotool windowfocus --sync "$win"
xdotool mousemove 680 425
xdotool key F2
sleep 2
import -window root "$out/coast.png"
survey() {
  xdotool key t; sleep .2; xdotool type "/survey $1"; xdotool key Return
}
survey roads
wait_log 'TERRAIN_SURVEY_READY roads'
sleep 2
import -window root "$out/roads.png"
survey fly
wait_log TERRAIN_SURVEY_FLY_START
if command -v ffmpeg >/dev/null; then
  mkdir -p "$out/frames"
  (
    for frame in {0..51}; do
      printf -v file '%03d' "$frame"
      import -window root -resize 1020x638! -quality 88 "$out/frames/$file.jpg"
      sleep .07
      if [[ $frame -ge 32 ]] && grep -q TERRAIN_SURVEY_FLY_END "$out/server.log"; then break; fi
    done
    ffmpeg -hide_banner -loglevel error -framerate 8 -i "$out/frames/%03d.jpg" \
      -an -c:v libx264 -threads 2 -preset fast -crf 24 -pix_fmt yuv420p "$out/flythrough.mp4"
  ) >"$out/ffmpeg.log" 2>&1 &
  video="$!"
  pids+=("$video")
fi
wait_log TERRAIN_SURVEY_CROSS
import -window root "$out/seam.png"
wait_log 'TERRAIN_SURVEY_READY fly'
sleep 2
import -window root "$out/arrival.png"
if [[ -n ${video:-} ]]; then wait "$video" || echo "Optional video unavailable; see $out/ffmpeg.log"; fi
[[ "$before" == "$(sha256sum "$source_save")" ]]
python3 - "$out" <<'PY_VERIFY'
from pathlib import Path
from PIL import Image
import json,re,sys
out=Path(sys.argv[1])
log=(out/"server.log").read_text()
rows=re.findall(r"TERRAIN_SURVEY_READY (\w+) built=(\d+) evicted=(\d+) maxbuilt=(\d+) resident=(\d+) road=(\d+) coast=(\d+) maxclear=(\d+)",log)
seen={k:[int(v) for v in rest] for k,*rest in rows}
crossed=[int(i) for i in re.findall(r"TERRAIN_SURVEY_CROSS chunk=(-?\d+)",log)]
assert all(k in seen for k in ("coast","roads","fly")) and len(set(crossed))>=2,(seen,crossed)
assert all(r[2]==2 and 0<r[3]<=36 and 0<=r[6]<=4 for r in seen.values())
assert seen["coast"][5]>0 and seen["roads"][4]>0
assert seen["fly"][1]>seen["roads"][1]>0 and seen["fly"][0]>seen["roads"][0]
for name in ("coast","roads","seam","arrival"):
    im=Image.open(out/(name+".png")).convert("RGB")
    assert im.size==(1360,850)
    area=im.crop((50,240,1310,830))
    pixels=[area.getpixel((x,y)) for y in range(0,area.height,5) for x in range(0,area.width,7)]
    green=sum(g>r*1.08 and g>b*1.08 and g<190 for r,g,b in pixels)/len(pixels)
    water=sum(65<b<180 and r<81 and b>1.14*g and g>1.2*r for r,g,b in pixels)/len(pixels)
    assert len(set(pixels))>250 and green>.22,(name,"missing textured terrain",green)
    if name=="coast": assert water>.075,(name,"missing coastal water",water)
    if name in {"roads","seam"}:
        road=sum(40<r<114 and max(r,g,b)-min(r,g,b)<17 for r,g,b in pixels)/len(pixels)
        assert road>.006,(name,"missing ordinary road asphalt",road)
report={"modes":seen,"crossed_columns":crossed,"source_unchanged":True,
        "fields":["chunks_built_total","chunks_evicted_total","max_chunks_per_update","max_resident","road_tiles_mounted_total","coasts_mounted_total","max_chunks_cleared_per_update"]}
(out/"proof.json").write_text(json.dumps(report,indent=2)+"\n")
print("Native terrain streaming proof:",report)
PY_VERIFY
if grep -Ei 'ERROR\[|could not load' "$out/client.log" "$out/server.log"; then exit 1; fi
