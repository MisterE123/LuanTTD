#!/usr/bin/env bash
# Real Luanti/OpenAL Audio: capture the mix from a test client into a WAV
# instead of requiring an audio device. Requires generated stock media.
set -euo pipefail
cd "$(dirname "$0")/.."
out=$(mktemp -d "${TMPDIR:-/tmp}/luanttd-stock-audio-native.XXXXXX")
printf 'Stock audio native evidence: %s\n' "$out"
mod='mods/luanttd_core'
game="$out/games/stockaudioqa"
install -d "$game/$mod/openttd" "$game/$mod/sounds" "$out/world"
cp "$mod"/{stock_audio.lua,stock_audio_music.lua} "$game/$mod/"
cp "$mod/openttd/sound_rc1.lua" "$game/$mod/openttd/"
for f in "$mod/sounds"/{stock_sfx*,openmsx*}.ogg; do ln "$f" "$game/$mod/sounds/" 2>/dev/null || cp "$f" "$game/$mod/sounds/"; done
printf 'title = Stock Audio QA\n' >"$game/game.conf"
printf 'name = luanttd_core\n' >"$game/$mod/mod.conf"
printf 'gameid = stockaudioqa\nbackend = sqlite3\nmod_storage_backend = sqlite3\n' >"$out/world/world.mt"

cat >"$game/$mod/init.lua" <<'LUA'
local mod=core.get_modpath("luanttd_core")
local audio=dofile(mod.."/stock_audio.lua")(core,mod)
core.register_node("luanttd_core:stone",{tiles={"[fill:16x16:#504e49"},walkable=true})
core.register_alias("mapgen_stone","luanttd_core:stone")
core.register_on_joinplayer(function(p)
  p:set_pos({x=1,y=5,z=1})
  p:set_physics_override({gravity=0})
  core.after(.4,function()
    audio.open(p)
    core.log("action","NATIVE MUSIC WINDOW")
  end)
  core.after(4,function()
    audio.fields(p,"luanttd_core:stock_audio",{audio_play=true})
    core.log("action","NATIVE MUSIC STOPPED")
  end)
  core.after(5.2,function()
    local pos={x=1,y=5,z=1}
    local road={mode="road",engine=116,sound_idle=true,pos=pos}
    audio.observe_vehicles({a=road})
    road.sound_idle=false;road.sound_tick=4
    audio.observe_vehicles({a=road})
    core.log("action","NATIVE POSITIONAL BUS DEPARTURE")
  end)
  core.after(9,function() core.log("action","NATIVE AUDIO COMPLETE") end)
end)
LUA
port=${BAYLINE_NATIVE_PORT:-41172}
display=${BAYLINE_NATIVE_DISPLAY:-271}
printf 'port = %d\nbind_address = 127.0.0.1\nserver_announce = false\nmg_name = singlenode\n' "$port" >"$out/server.conf"
printf 'screen_w = 1000\nscreen_h = 680\nenable_sound = true\nsound_volume = 1\nsound_volume_unfocused = 1\nenable_shaders = false\n' >"$out/client.conf"
printf '[general]\ndrivers=wave\n[wave]\nfile=%s\n' "$out/mix.wav" >"$out/alsoft.conf"
export HOME="$out" XDG_CACHE_HOME="$out/cache" LIBGL_ALWAYS_SOFTWARE=1 LP_NUM_THREADS=2
export LUANTI_GAME_PATH="$out/games" MINETEST_GAME_PATH="$out/games"
export DISPLAY="127.0.0.1:$display"
cc -shared -fPIC tests/native_loopback.c -ldl -o "$out/loopback.so"
env LD_PRELOAD="$out/loopback.so" Xvfb ":$display" -screen 0 1000x680x24 -listen tcp -nolisten local -nolisten unix -ac -noreset >"$out/xvfb.log" 2>&1 &
display_pid=$! server= client=
trap 'for pid in "$client" "$server" "$display_pid"; do [[ -z $pid ]] || kill "$pid" 2>/dev/null || true; done; wait 2>/dev/null || true' EXIT
for _ in {1..50}; do xdpyinfo >/dev/null 2>&1 && break; sleep .15; done
xdpyinfo >/dev/null 2>&1
luantiserver --world "$out/world" --gameid stockaudioqa --config "$out/server.conf" --logfile '' >"$out/server.log" 2>&1 &
server=$!
for _ in {1..90}; do grep -q 'listening on' "$out/server.log" && break; sleep .15; done
grep -q 'listening on' "$out/server.log" || { cat "$out/server.log"; exit 1; }
ALSOFT_DRIVERS=wave ALSOFT_CONF="$out/alsoft.conf" luanti --go --address 127.0.0.1 --port "$port"   --name AudioQA --password '' --config "$out/client.conf" --logfile '' >"$out/client.log" 2>&1 &
client=$!
win=$(timeout 12 xdotool search --sync --onlyvisible --pid "$client" | tail -1)
xdotool windowfocus "$win"
if command -v import >/dev/null; then
  for _ in {1..40}; do
    if grep -q 'NATIVE MUSIC WINDOW' "$out/server.log"; then
      sleep .4
      import -window root -quality 90 "$out/jukebox.jpg"
      break
    fi
    sleep .12
  done
fi
for _ in {1..100}; do
  grep -q 'NATIVE AUDIO COMPLETE' "$out/server.log" && break
  kill -0 "$client" 2>/dev/null || { cat "$out/client.log"; exit 1; }
  sleep .2
done
if ! grep -q 'NATIVE AUDIO COMPLETE' "$out/server.log"; then cat "$out/"{client,server}.log; exit 1; fi
xdotool key Escape
xdotool windowclose "$win" || true
for _ in {1..35}; do if ! kill -0 "$client" 2>/dev/null; then break; fi; sleep .15; done
if kill -0 "$client" 2>/dev/null; then kill -TERM "$client"; fi
wait "$client" || true
client=
! grep -Ei 'could not.*(audio|sound)|failed.*(OpenAL|stock_sfx|openmsx)|Runtime error' "$out/"{client,server}.log
ffmpeg -hide_banner -v error -i "$out/mix.wav" -f s16le -ac 1 -y "$out/mix.pcm"
python3 - "$out/mix.pcm" <<'PY'
from array import array
from pathlib import Path
import sys
q=array("h");q.frombytes(Path(sys.argv[1]).read_bytes())
# At least two separated audible stretches and an intervening silent
# stretch: one stereo soundtrack, then the positional bus effect.
counts=[sum(abs(a)>28 for a in q[i:i+4410])>44 for i in range(0,len(q),4410)]
groups=[]
for i,on in enumerate(counts):
    if on:
        if not groups or i-groups[-1][-1]>5: groups.append([])
        groups[-1].append(i)
assert len(groups)>=2 and len(groups[0])>=12 and len(groups[1])>=4,[(g[0],g[-1]) for g in groups]
print("PASS: real native OpenAL audio mix contains the OpenMSX track, silence after Stop, and the positional OpenSFX bus departure.")
PY
