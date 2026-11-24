#!/usr/bin/env bash
# Graphical isolated singleplayer. Lost-window-focus pause comes from
# Luanti itself; no setting or fallback is added to the game.
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ -n ${BAYLINE_NATIVE_TOOLS:-} ]]; then
  t=$(realpath "$BAYLINE_NATIVE_TOOLS")
  export PATH="$t/run/bin:$t/usr/bin:$PATH" LD_LIBRARY_PATH="$t/usr/lib/x86_64-linux-gnu${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
fi
out=$(mktemp -d "${TMPDIR:-/tmp}/luanttd-worker-focus.XXXXXX")
echo "Native graphical focus evidence: $out"
src=$(realpath "${BAYLINE_NATIVE_EXACT_GAME:-.}")
game="$out/games/luanttd"
mkdir -p "$game" "$out/world" "$out/home" "$out/cache"
cp "$src/game.conf" "$game/"
if cp -al "$src/mods" "$game/" 2>/dev/null; then
  cp "$game/mods/luanttd_core/init.lua" "$out/fixture-init.lua"
  mv "$out/fixture-init.lua" "$game/mods/luanttd_core/init.lua"
else
  cp -R "$src/mods/." "$game/mods/"
fi
mod="$game/mods/luanttd_core"
cp tests/campaign_worker_focus_geography.lua "$mod/"
python3 - "$mod/init.lua" <<'PY'
from pathlib import Path
import sys
p=Path(sys.argv[1]);s=p.read_text()
key='local world_options=WorldSetup.read(core,storage)'
insert='''if storage:get_string(WorldSetup.storage_key)=="" then
  storage:set_string(WorldSetup.storage_key,core.write_json(WorldSetup.defaults(core.settings)))
end
'''
assert key in s
s=s.replace(key,insert+key)
game='local api={Sim=Sim,s=S'
assert game in s
s=s.replace(game, 'if not resumed_owner then dofile(mod.."/campaign_worker_focus_geography.lua")(core,S,Sim,mod) end\n' + game,1)
p.write_text(s)
PY
printf '\n' >> "$mod/init.lua"
cat tests/campaign_worker_focus_native.lua >> "$mod/init.lua"
printf 'gameid = luanttd\nbackend = sqlite3\nplayer_backend = sqlite3\nauth_backend = sqlite3\nmod_storage_backend = sqlite3\n' > "$out/world/world.mt"
cat > "$out/native.conf" <<'CONF'
screen_w = 1180
screen_h = 760
fullscreen = false
enable_sound = false
pause_on_lost_focus = true
fps_max = 30
fps_max_unfocused = 12
bayline_seed = 1751
bayline_generated_map_width = 64
bayline_generated_map_depth = 64
bayline_generated_relief = 0
bayline_generated_coasts = 0
bayline_generated_towns = 6
bayline_generated_town_layout = grid2
CONF
if [[ ${BAYLINE_FOCUS_DEAD_END:-0} == 1 ]]; then
  printf '%s\n' 'luanttd_native_focus_dead_end = true' >>"$out/native.conf"
elif [[ ${BAYLINE_FOCUS_DEAD_END:-0} == depot ]]; then
  printf '%s\n' 'luanttd_native_focus_terminal_depot = true' >>"$out/native.conf"
fi
export HOME="$out/home" XDG_CACHE_HOME="${LUANTTD_NATIVE_MEDIA_CACHE:-$out/cache}" LUANTI_GAME_PATH="$out/games" MINETEST_GAME_PATH="$out/games"
export LIBGL_ALWAYS_SOFTWARE=1 MESA_SHADER_CACHE_DISABLE=1 ALSOFT_DRIVERS=null
display=${BAYLINE_NATIVE_DISPLAY:-369}
export DISPLAY="127.0.0.1:$display"
# Match an ordinary returning client. Test focus/rider behavior, not two
# cold media downloads competing for the same local server's quota.
if [[ -z ${LUANTTD_NATIVE_MEDIA_CACHE:-} ]]; then
  python3 tests/cache_luanti_game_media.py "$game" "$XDG_CACHE_HOME"
fi
cc -shared -fPIC tests/native_loopback.c -ldl -o "$out/loopback.so"
env LD_PRELOAD="$out/loopback.so" Xvfb ":$display" -screen 0 1180x760x24 -listen tcp -nolisten local -nolisten unix -ac -noreset >"$out/xvfb.log" 2>&1 &
xv=$!;client=;sink=
trap '[[ -z "$client" ]] || kill "$client" 2>/dev/null || true; [[ -z "$sink" ]] || kill "$sink" 2>/dev/null || true; kill "$xv" 2>/dev/null || true;wait 2>/dev/null || true' EXIT
for _ in {1..40}; do xdpyinfo >/dev/null 2>&1 && break; sleep .25; done
xdpyinfo >/dev/null
await_log() {
  for _ in {1..220}; do
    grep -q "$1" "$log" && return
    kill -0 "$client" 2>/dev/null || break
    sleep .25
  done
  tail -n 60 "$log"; return 1
}
open() {
  log="$out/$1.log"
  luanti --world "$out/world" --go --gameid luanttd --config "$out/native.conf" --logfile '' >"$log" 2>&1 &
  client=$!
  window=$(timeout 20 xdotool search --onlyvisible --sync --pid "$client" | tail -n 1)
  xdotool windowfocus --sync "$window"
  await_log 'FOCUS_NATIVE_POSITION'
}
open first
printf '%s\n' initial > "$out/world/native-focus-step"
await_log 'FOCUS_NATIVE_RECEIPT initial'
import -window root "$out/before.png"
xmessage -title FocusSink -geometry 300x125+780+550 "Native test: window outside Luanti." >"$out/xmessage.log" 2>&1 &
sink=$!
target=$(timeout 7 xdotool search --onlyvisible --sync --name FocusSink | tail -n 1)
xdotool windowfocus --sync "$target"
sleep 9
xdotool windowfocus --sync "$window"
# The Luanti setting opened its normal pause menu. Escape resumes the
# engine; there is no LuanTTD restart or recovery menu to dismiss.
xdotool key Escape
sleep 1.3
printf '%s\n' focus-return > "$out/world/native-focus-step"
await_log 'FOCUS_NATIVE_RECEIPT focus-return'
xdotool keydown d; sleep 1.1; xdotool keyup d
sleep 1
import -window root "$out/after-focus.png"
await_log 'FOCUS_NATIVE_PAID'
kill "$sink" 2>/dev/null || true
sink=
if [[ ${LUANTTD_NATIVE_ROAD_GESTURES:-0} == 1 ]]; then
  do_road() {
    printf '%s\n' "road-$1" > "$out/world/native-focus-step"
    await_log "NATIVE_ROAD_GESTURE_$2"
  }
  do_road x-start X
  slot=$(sed -n 's/.*NATIVE_ROAD_GESTURE_X slot=//p' "$log" | tail -1)
  xdotool key "$slot"; sleep .4; xdotool mousedown 1; sleep .5
  do_road x-end X_RELEASE
  sleep .65; import -window root -resize 960x600 "$out/x-preview.jpg"
  xdotool mouseup 1; sleep .85
  do_road check-x X_PASS
  do_road remove-start REMOVE
  slot=$(sed -n 's/.*NATIVE_ROAD_GESTURE_REMOVE slot=//p' "$log" | tail -1)
  xdotool key "$slot"; sleep .4; xdotool mousedown 1; sleep .5
  do_road remove-end REMOVE_RELEASE
  sleep .65; import -window root -resize 960x600 "$out/remove-preview.jpg"
  xdotool mouseup 1; sleep .85
  do_road check-remove REMOVE_PASS
fi
if [[ ${LUANTTD_NATIVE_REJOIN:-0} == 1 ]]; then
  printf '%s\n' set-rejoin > "$out/world/native-focus-step"
  await_log 'FOCUS_NATIVE_REJOIN_SET'
fi
kill -TERM "$client"
wait "$client" || true
client=
open reopened
printf '%s\n' reopen > "$out/world/native-focus-step"
await_log 'FOCUS_NATIVE_RECEIPT reopen'
if [[ ${LUANTTD_NATIVE_ROAD_GESTURES:-0} == 1 ]]; then
  do_road reopen REOPEN_PASS
  grep 'NATIVE_ROAD_GESTURE_.*PASS' "$out/"{first,reopened}.log
fi
if [[ ${LUANTTD_NATIVE_REJOIN:-0} == 1 ]]; then
  sleep .6
  printf '%s\n' check-rejoin > "$out/world/native-focus-step"
  await_log 'FOCUS_NATIVE_REJOIN_PASS'
  grep 'FOCUS_NATIVE_REJOIN_PASS' "$log"
fi
xdotool keydown d; sleep 1.1; xdotool keyup d
sleep 1
import -window root "$out/after-reopen.png"
python3 - "$out" <<'PY'
from pathlib import Path
import re, sys
p=Path(sys.argv[1])
a=(p/'first.log').read_text()
b=(p/'reopened.log').read_text()
def stamp(text,s):
    n=re.search(r'FOCUS_NATIVE_RECEIPT '+s+r' day=(\d+) cash=(\d+) bus=(\d+) delivered=(\d+) revenue=(\d+)',text)
    return tuple(map(int,n.groups()))
initial=stamp(a,'initial')
focus=stamp(a,'focus-return')
reopen=stamp(b,'reopen')
assert focus[0]>initial[0] and reopen[0]>=focus[0] and initial[2]==focus[2]==reopen[2],(initial,focus,reopen)
arrive=re.search(r'FOCUS_NATIVE_PAID bus=(\d+) delivered=(\d+) revenue=(\d+)',a)
bus,paid,revenue=map(int,arrive.groups())
assert bus==focus[2] and paid>focus[3] and reopen[3]>=paid and reopen[4]>=revenue>focus[4]
def movement(log,phase):
    span=log.split('FOCUS_NATIVE_RECEIPT '+phase,1)[1].split('FOCUS_NATIVE_REJOIN_MOVE',1)[0]
    pos=[(float(x),float(z)) for x,y,z in re.findall(r'FOCUS_NATIVE_POSITION (-?\d+.\d+) (-?\d+.\d+) (-?\d+.\d+)',span)]
    return max(abs(x-pos[0][0])+abs(z-pos[0][1]) for x,z in pos)
after_focus=movement(a,'focus-return'); after_reopen=movement(b,'reopen')
assert after_focus>.8 and after_reopen>.8,(after_focus,after_reopen)
assert 'simulation owner stopped' not in a+b
print(f'WORKER_GRAPHICAL_FOCUS_REOPEN_PASS days {initial[0]}→{focus[0]}→{reopen[0]}; movement after focus {after_focus:.2f}, after reopen {after_reopen:.2f}; same company and bus {bus}, {paid} paid passengers')
PY
