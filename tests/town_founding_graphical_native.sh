#!/usr/bin/env bash
# Real game, disposable prepared campaign, native mouse/keyboard. No chat.
set -euo pipefail
cd "$(dirname "$0")/.."
out=$(mktemp -d "${TMPDIR:-/tmp}/luanttd-found-town.XXXXXX")
echo "$out"
game="$out/games/luanttd"
mod="$game/mods/luanttd_core"
mkdir -p "$game" "$out/world" "$out/home" "$out/cache"
cp game.conf "$game/"
cp -al mods "$game/"
cp "$mod/init.lua" "$out/real-init"
cat >"$out/prepare.lua" <<'LUA'
local mod=core.get_modpath(core.get_current_modname())
local function m(n) return dofile(mod.."/"..n..".lua") end
for _,k in ipairs({"stone","water_source","river_water_source"}) do core.register_alias("mapgen_"..k,"air") end
local Sim=m("sim")
local s=m("campaign_generation")(core,mod,Sim,m("world_setup")).run({
  width=128,depth=128,year=1950,seed=1751,relief=1,sea=0,coast=16,rivers=2,
  trees=2,towns=4,custom_towns=4,larger_towns=3,industries=0,variety=0,smooth=1,layout="original",growth_rate=2,found_town=0,
})
assert(Sim.open_company(s,"singleplayer"))
s.companies.singleplayer.cash,s.speed=80000000,0
local disk=m("campaign_checkpoint")(core,m("packed_campaign"),"luanttd-campaign-owner.chk")
disk.write_state(s)
core.register_on_mods_loaded(function()
  core.after(.1,function() core.request_shutdown("Prepared Town Founding QA world",false,0) end)
end)
LUA
mv "$out/prepare.lua" "$mod/init.lua"
printf 'gameid = luanttd\nbackend = sqlite3\nplayer_backend = sqlite3\nauth_backend = sqlite3\nmod_storage_backend = sqlite3\n' >"$out/world/world.mt"
port=${BAYLINE_NATIVE_PORT:-40158}
disp=${BAYLINE_NATIVE_DISPLAY:-194}
cat >"$out/local.conf" <<CONF
port = $port
bind_address = 127.0.0.1
server_announce = false
screen_w = 1440
screen_h = 900
fullscreen = false
enable_sound = false
gui_scaling = 1.0
CONF
export DISPLAY="127.0.0.1:$disp" HOME="$out/home" LIBGL_ALWAYS_SOFTWARE=1 MESA_SHADER_CACHE_DISABLE=1 ALSA_CONFIG_PATH=/dev/null
export XDG_CACHE_HOME="${LUANTTD_NATIVE_MEDIA_CACHE:-$out/cache}"
export LUANTI_GAME_PATH="$out/games" MINETEST_GAME_PATH="$out/games"
timeout 60 luantiserver --world "$out/world" --gameid luanttd --config "$out/local.conf" --logfile '' >"$out/prepare.log" 2>&1   || { tail -45 "$out/prepare.log";exit 1; }
test -s "$out/world/luanttd-campaign-owner.chk"
mv "$out/real-init" "$mod/init.lua"
cat >>"$mod/init.lua" <<'LUA'
local draw=core.show_formspec
core.show_formspec=function(name,form,body)
  if form=="luanttd_core:worker_finance" then
    if body:find("Found town here",1,true) then
      core.log("action","FOUND_UI_FINANCE")
    elseif body:find("Town founding set to Custom layout.",1,true) then
      core.log("action","FOUND_UI_RULE_APPLIED")
    elseif body:find("Custom layout lets each company",1,true) then
      core.log("action","FOUND_UI_RULE_INPUT")
    elseif body:find("_founding_rules;Town founding rules]",1,true) then
      core.log("action","FOUND_UI_WORLD_RULES")
    elseif body:find("_world_rules;World rules]",1,true) then
      core.log("action","FOUND_UI_START")
    end
  elseif form=="luanttd_core:found_town" then
    if body:find("Founded Rivermark",1,true) then
      assert(body:find("Starting population: 804",1,true))
      core.log("action","FOUND_UI_CITY")
    elseif body:find("Founding cost:",1,true) then
      core.log("action","FOUND_UI_QUOTE "..body)
    else core.log("action","FOUND_UI_FORM "..body) end
  end
  return draw(name,form,body)
end
core.register_on_joinplayer(function(p)
  local n=p:get_player_name()
  local function ready()
    local u=core.get_player_by_name(n)
    if not u then return end
    if not api.worker_town_founding then return core.after(.2,ready) end
    u:set_pos({x=138,y=15,z=128})
    u:set_look_vertical(math.pi*.495)
    local target=api.world.target(u)
    if target~=8133 then return core.after(.2,ready) end
    core.log("action","FOUND_UI_TARGET 8133")
    core.after(.45,function() if core.get_player_by_name(n) then ui.open_finance(u) end end)
  end
  core.after(.25,ready)
end)
LUA
cc -shared -fPIC tests/native_loopback.c -ldl -o "$out/loopback.so"
env LD_PRELOAD="$out/loopback.so" Xvfb ":$disp" -screen 0 1440x900x24 -listen tcp -nolisten local -nolisten unix -ac -noreset >"$out/xvfb.log" 2>&1 &
xv=$!; client=""
cleanup(){ if [[ -n "$client" ]]; then kill "$client" 2>/dev/null || true; fi; kill "$xv" 2>/dev/null || true; }
trap cleanup EXIT
for _ in {1..40}; do xdpyinfo >/dev/null 2>&1 && break; sleep .25; done
luanti --go --world "$out/world" --gameid luanttd --config "$out/local.conf" --logfile '' >"$out/client.log" 2>&1 &
client=$!
mark(){ for _ in {1..200}; do grep -q "$1" "$out/client.log" && return; kill -0 "$client" 2>/dev/null || break; sleep .25; done; tail -50 "$out/client.log"; return 1; }
mark FOUND_UI_START
win=$(xdotool search --sync --limit 1 --onlyvisible --pid "$client" | tail -1)
xdotool windowfocus --sync "$win"
sleep .45
xdotool mousemove 612 598 click 1
mark FOUND_UI_WORLD_RULES
sleep .45
xdotool mousemove 612 489 click 1
mark FOUND_UI_RULE_INPUT
sleep .4
import -window root -resize 960x600 "$out/rules.png"
xdotool mousemove 760 444 click 1
sleep .18
xdotool key End Return
sleep .25
xdotool mousemove 869 444 click 1
mark FOUND_UI_RULE_APPLIED
sleep .45
xdotool mousemove 610 533 click 1
sleep .45
xdotool mousemove 610 552 click 1
mark FOUND_UI_FINANCE
sleep .5
import -window root -resize 960x600 "$out/finance.png"
xdotool mousemove 831 564 click 1
mark FOUND_UI_FORM
sleep .45
import -window root -resize 960x600 "$out/options.png"
xdotool mousemove 615 394 click 1 key ctrl+a type --clearmodifiers Rivermark
xdotool mousemove 695 450 click 1
sleep .18
xdotool key Home Down Return
xdotool mousemove 735 445 click 1
sleep .18
xdotool mousemove 695 510 click 1
sleep .18
xdotool key End Return
sleep .28
import -window root -resize 960x600 "$out/filled.png"
xdotool mousemove 831 510 click 1
mark FOUND_UI_QUOTE
sleep .35
import -window root -resize 960x600 "$out/quote.png"
xdotool mousemove 831 522 click 1
mark FOUND_UI_CITY
sleep .35
import -window root -resize 960x600 "$out/founded.png"
grep 'FOUND_UI_CITY' "$out/client.log"
! grep -E 'ERROR\[' "$out/client.log"
