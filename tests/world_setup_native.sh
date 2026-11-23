#!/usr/bin/env bash
# Native Linux singleplayer setup: one click starts real generation,
# one reopen loads the prepared state, and a transient placement failure retries.
set -euo pipefail
cd "$(dirname "$0")/.."
root=$PWD
out=$(mktemp -d "${TMPDIR:-/tmp}/luanttd-world-setup-native.XXXXXX")
echo "$out"
game="$out/games/luanttd"
mkdir -p "$game" "$out/world" "$out/home" "$out/cache"
if [[ -n ${LUANTTD_NATIVE_MEDIA_CACHE:-} ]]; then
  cp -al "$LUANTTD_NATIVE_MEDIA_CACHE/." "$out/cache/"
fi
cp game.conf "$game/"
cp -al mods "$game/"
if [[ ${BAYLINE_QA_OWNER:-0} == 1 ]]; then
  printf 'return function() return {authoritative_boot=true,interval=.23} end
' >"$game/mods/luanttd_core/qa_layout.lua"
fi
cp mods/luanttd_core/init.lua "$out/init.lua"
mv "$out/init.lua" "$game/mods/luanttd_core/init.lua"
cat > "$out/probe.lua" <<'LUA'
local previous_show=core.show_formspec
local progress_channel={}
core.show_formspec=function(name,form,body)
  if form=="luanttd_core:generating_world" or form=="luanttd_core:placing_terrain" then
    local pct=body:match(";(%d+)%%%]")
    local stage=body:match("label%[%s*%.55,1.20;([^%]]+)%]")
    if pct and (progress_channel[form]~=pct or (stage or ""):find("Retrying",1,true)) then
      progress_channel[form]=pct
      core.log("action","WORLD_CREATION_PROGRESS "..form.." "..pct.." "..(stage or ""))
    end
  elseif form=="luanttd_core:world_setup" then
    core.log("action","WORLD_CREATION_OPTIONS")
  end
  return previous_show(name,form,body)
end
LUA
cat "$game/mods/luanttd_core/init.lua" >> "$out/probe.lua"
cat >> "$out/probe.lua" <<'LUA'
assert(placement and Sim.W==128 and Sim.H==128 and S.stock_generated_profile.industries)
assert(core.get_mod_storage():get_string("campaign")=="")
local raw_place=render.place_world
local once
render.place_world=function(done,notify)
  if not once then
    once=true
    core.log("action","WORLD_CREATION_TEST_EDGES simulating one transient emergence failure")
    return core.after(.15,done,false,"disposable test failure")
  end
  return raw_place(done,notify)
end
local complete,movement_origin,moved
core.register_globalstep(function()
  local p=core.get_player_by_name("singleplayer")
  if p and not complete and not placement and #api.world.hotbar_layout(p)>0 then
    assert(worker_boot)
    if worker_boot then
      assert(authority.status()=="owned" and api.authority_handoff and not S.companies["singleplayer"])
      local disk=assert(OwnerCheckpoint.read())
      assert(disk.companies["singleplayer"] and disk.stock_generated_profile.width==128)
      core.log("action","WORLD_CREATION_WORKER_READY")
    end
    complete=true
    core.log("action","WORLD_CREATION_PLAYABLE "..S.stock_generated_profile.width)
  end
  if not p or not complete then return end
  local pos=p:get_pos()
  if not movement_origin and p:get_player_control().right then
    movement_origin=pos
    core.log("action","WORLD_CREATION_STRAFE_INPUT")
  elseif movement_origin and not moved then
    local dx,dz=pos.x-movement_origin.x,pos.z-movement_origin.z
    if dx*dx+dz*dz>=1 then
      moved=true
      core.log("action",string.format("WORLD_CREATION_STRAFE_PASS %.2f",math.sqrt(dx*dx+dz*dz)))
    end
  end
end)
LUA
mv "$out/probe.lua" "$game/mods/luanttd_core/init.lua"
printf 'gameid = luanttd\nbackend = sqlite3\nplayer_backend = sqlite3\nauth_backend = sqlite3\nmod_storage_backend = sqlite3\n' >"$out/world/world.mt"
cat > "$out/local.conf" <<'CONF'
screen_w = 1440
screen_h = 900
fullscreen = false
enable_sound = false
gui_scaling = 1.0
bayline_seconds_per_day = 8
bayline_generated_map_width = 128
bayline_generated_map_depth = 128
CONF
if [[ -n ${BAYLINE_NATIVE_TOOLS:-} ]]; then
  t=$(realpath "$BAYLINE_NATIVE_TOOLS")
  export PATH="$t/run/bin:$t/usr/bin:$PATH" LD_LIBRARY_PATH="$t/usr/lib/x86_64-linux-gnu${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
fi
disp=${BAYLINE_NATIVE_DISPLAY:-190}
export DISPLAY="127.0.0.1:$disp" HOME="$out/home" XDG_CACHE_HOME="$out/cache" LIBGL_ALWAYS_SOFTWARE=1 MESA_SHADER_CACHE_DISABLE=1
export LUANTI_GAME_PATH="$out/games" MINETEST_GAME_PATH="$out/games"
cc -shared -fPIC tests/native_loopback.c -ldl -o "$out/loopback.so"
env LD_PRELOAD="$out/loopback.so" Xvfb ":$disp" -screen 0 1440x900x24 -listen tcp -nolisten local -nolisten unix -ac -noreset >"$out/xvfb.log" 2>&1 &
xv=$!
client=""
trap 'if [[ -n "$client" ]]; then kill "$client" 2>/dev/null || true; fi; kill "$xv" 2>/dev/null || true; wait 2>/dev/null || true' EXIT
for _ in {1..40}; do xdpyinfo >/dev/null 2>&1 && break; sleep .25; done
"${BAYLINE_LUANTI_CLIENT:-luanti}" --go --world "$out/world" --gameid luanttd --config "$out/local.conf" --logfile '' >"$out/client.log" 2>&1 &
client=$!
waitmark(){ for _ in {1..300}; do grep -q "$1" "$out/client.log" && return; kill -0 "$client" || return 1; sleep .25; done; tail -40 "$out/client.log"; return 1; }
snap(){ import -window root -resize 720x450 -quality 85 "$out/$1.jpg"; }
waitmark WORLD_CREATION_OPTIONS
win=$(xdotool search --sync --limit 1 --onlyvisible --pid "$client" | tail -1)
xdotool windowfocus --sync "$win"
sleep .75
snap options
xdotool mousemove 916 686 click 1
for _ in {1..160}; do
  if grep -q 'generating_world 90' "$out/client.log"; then break; fi
  if grep -q 'generating_world 5 ' "$out/client.log" && [[ ! -f "$out/progress.jpg" ]]; then snap progress; fi
  kill -0 "$client"; sleep .18
done
grep -E 'generating_world (0|5|62|87|90) ' "$out/client.log"
sleep 1.5
test -s "$out/world/luanttd-prepared-campaign.chk"
# Direct --go mode can return to the main menu rather than reconnecting.
# Start the already-prepared world once, never rerun the generator there.
if ! grep -q 'WORLD_CREATION_PLAYABLE' "$out/client.log"; then
  kill "$client" 2>/dev/null || true
  wait "$client" || true
  mv "$out/client.log" "$out/first.log"
  "${BAYLINE_LUANTI_CLIENT:-luanti}" --go --world "$out/world" --gameid luanttd --config "$out/local.conf" --logfile '' >"$out/client.log" 2>&1 &
  client=$!
fi
waitmark WORLD_CREATION_PLAYABLE
sleep .45
snap playable
win=$(xdotool search --sync --limit 1 --onlyvisible --pid "$client" | tail -1)
xdotool windowfocus --sync "$win"
xdotool keydown d
sleep 1.6
xdotool keyup d
grep -q WORLD_CREATION_STRAFE_INPUT "$out/client.log"
grep -q WORLD_CREATION_STRAFE_PASS "$out/client.log"
grep -E 'WORLD_CREATION_(PROGRESS|PLAYABLE|STRAFE_PASS)' "$out/client.log"
grep -q 'placing_terrain 100' "$out/client.log"
grep -q WORLD_CREATION_WORKER_READY "$out/client.log"
grep -q 'disposable test failure' "$out/client.log"
! grep -E 'ERROR\[' "$out/client.log"
